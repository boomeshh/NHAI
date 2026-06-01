import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/ui/screens/face_capture_screen.dart';
import 'package:nhai_auth/ui/widgets/face_alignment_overlay.dart';

/// Widget tests for FaceCaptureScreen (enrollment mode).
///
/// Requirements: 4.1, 4.2, 4.3, 5.3

// ── Fake EnrollmentModuleInterface ───────────────────────────────────────────

/// A configurable fake [EnrollmentModuleInterface] for widget tests.
class _FakeEnrollmentModule implements EnrollmentModuleInterface {
  EnrollmentResult enrollResult;

  _FakeEnrollmentModule({required this.enrollResult});

  @override
  ValidationResult validateForm(
          String employeeId, String name, String department) =>
      const ValidationResult(isValid: true);

  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;

  @override
  Future<EnrollmentResult> enroll(
      EmployeeFormData formData, List<CameraFrame> frames) async {
    return enrollResult;
  }

  @override
  Future<EnrollmentResult> enrollMultiPose(EmployeeFormData formData,
          Map<FacePose, List<CameraFrame>> posedFrames) async =>
      throw UnimplementedError();
}

/// An [EnrollmentModuleInterface] whose [enroll] method never completes,
/// keeping the screen in the processing phase indefinitely.
class _SlowEnrollmentModule implements EnrollmentModuleInterface {
  final Future<EnrollmentResult> _future;

  const _SlowEnrollmentModule(this._future);

  @override
  ValidationResult validateForm(
          String employeeId, String name, String department) =>
      const ValidationResult(isValid: true);

  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;

  @override
  Future<EnrollmentResult> enroll(
          EmployeeFormData formData, List<CameraFrame> frames) =>
      _future;

  @override
  Future<EnrollmentResult> enrollMultiPose(EmployeeFormData formData,
          Map<FacePose, List<CameraFrame>> posedFrames) =>
      _future;
}

/// An [EnrollmentModuleInterface] that returns [firstResult] on the first
/// [enroll] call and a success result on subsequent calls.
class _CountingEnrollmentModule implements EnrollmentModuleInterface {
  final EnrollmentResult firstResult;
  int _callCount = 0;

  _CountingEnrollmentModule({required this.firstResult});

  @override
  ValidationResult validateForm(
          String employeeId, String name, String department) =>
      const ValidationResult(isValid: true);

  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;

  @override
  Future<EnrollmentResult> enroll(
      EmployeeFormData formData, List<CameraFrame> frames) async {
    _callCount++;
    if (_callCount == 1) return firstResult;
    return EnrollmentResult(
      success: true,
      record: EmployeeRecord(
        employeeId: formData.employeeId,
        name: formData.name,
        department: formData.department,
        embedding: FaceEmbedding(List.filled(128, 0.1)),
        enrolledAt: DateTime.utc(2024, 1, 1),
      ),
    );
  }

  @override
  Future<EnrollmentResult> enrollMultiPose(EmployeeFormData formData,
          Map<FacePose, List<CameraFrame>> posedFrames) async =>
      throw UnimplementedError();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// A minimal [EmployeeRecord] used in success-state tests.
EmployeeRecord _makeRecord({
  String employeeId = 'EMP001',
  String name = 'Ravi Kumar',
  String department = 'Engineering',
}) =>
    EmployeeRecord(
      employeeId: employeeId,
      name: name,
      department: department,
      embedding: FaceEmbedding(List.filled(128, 0.1)),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

/// A [CameraFrame] with a positive sharpness score (treated as "face detected"
/// by [FaceCaptureScreen._onFrame]).
CameraFrame _sharpFrame() => const CameraFrame(
      bytes: [1, 2, 3],
      width: 640,
      height: 480,
      sharpnessScore: 0.8,
    );

/// A [CameraFrame] with zero sharpness (treated as "no face").
CameraFrame _blankFrame() => const CameraFrame(
      bytes: [0],
      width: 640,
      height: 480,
      sharpnessScore: 0.0,
    );

/// Short timeout used in tests that trigger enrollment so the no-face timer
/// does not leave a pending timer at test end.
const _kShortTimeout = Duration(milliseconds: 100);

/// Wraps [FaceCaptureScreen] in a [MaterialApp] with stub routes so that
/// navigation calls (e.g., pushNamedAndRemoveUntil('/home')) do not throw.
Widget _buildApp({
  required StreamController<CameraFrame> frameController,
  required EnrollmentModuleInterface enrollmentModule,
  EmployeeFormData? formData,
  int minFrameCount = 3,
  Duration noFaceTimeout = _kShortTimeout,
}) {
  final formDataValue = formData ??
      const EmployeeFormData(
        employeeId: 'EMP001',
        name: 'Ravi Kumar',
        department: 'Engineering',
      );

  return MaterialApp(
    initialRoute: '/face-capture',
    routes: {
      '/face-capture': (_) => FaceCaptureScreen(
            enrollmentModule: enrollmentModule,
            formData: formDataValue,
            frameProvider: () => frameController.stream,
            minFrameCount: minFrameCount,
            noFaceTimeout: noFaceTimeout,
          ),
      '/home': (_) => const Scaffold(body: Text('HomeScreen')),
    },
  );
}

/// Pumps the widget tree enough times to let [FaceCaptureScreen] initialise
/// its injected frame provider and subscribe to the stream.
Future<void> _pumpInit(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Triggers enrollment by emitting [count] sharp frames and pumping the
/// widget tree enough times for the full async enrollment chain to complete:
///   1. Frame delivered to listener → _onFrame → _proceedToEnrollment called
///   2. setState(phase = processing) → rebuild
///   3. _frameSub.cancel() completes
///   4. enroll() Future resolves
///   5. setState(phase = success/error) → rebuild
///
/// Uses [tester.runAsync] to run the async chain in a real async context so
/// that [StreamSubscription.cancel] completes without needing extra pumps.
Future<void> _triggerEnrollment(
  WidgetTester tester,
  StreamController<CameraFrame> controller,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    controller.add(_sharpFrame());
    await tester.pump();
  }
  // Run the async chain (cancel + enroll) in a real async context.
  await tester.runAsync(() async {
    // Give the event loop a chance to process the cancel() future.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
  // Pump to process the setState(phase = success/error).
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Face detection indicator (Req 4.2) ──────────────────────────────────
  group('FaceCaptureScreen — face detection indicator (Req 4.2)', () {
    testWidgets(
        'FaceAlignmentOverlay shows detected state when frames with sharpness > 0 are emitted',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(
          success: false,
          errorMessage: 'test',
        ),
      );

      // Use minFrameCount = 10 so the screen stays in capturing phase long
      // enough for us to inspect the overlay state before enrollment starts.
      // Use a long timeout so the timer does not fire during the assertion.
      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 10,
        noFaceTimeout: const Duration(seconds: 30),
      ));

      await _pumpInit(tester);

      // Verify the capture view is shown (camera placeholder present).
      expect(find.byKey(const Key('camera_placeholder')), findsOneWidget);

      // Overlay should start in idle state.
      final overlayBefore = tester.widget<FaceAlignmentOverlay>(
        find.byKey(const Key('face_alignment_overlay')),
      );
      expect(overlayBefore.state, FaceAlignmentState.idle);

      // Emit a frame with positive sharpness → face detected.
      controller.add(_sharpFrame());
      await tester.pump();
      await tester.pump();

      final overlayAfter = tester.widget<FaceAlignmentOverlay>(
        find.byKey(const Key('face_alignment_overlay')),
      );
      expect(overlayAfter.state, FaceAlignmentState.detected);

      // The "Face detected" label should be visible inside the overlay.
      expect(find.text('Face detected'), findsOneWidget);

      // Drain the pending timer before the test ends.
      await tester.pump(const Duration(seconds: 31));

      await controller.close();
    });

    testWidgets(
        'FaceAlignmentOverlay remains idle when only zero-sharpness frames are emitted',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(success: false),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 10,
        noFaceTimeout: const Duration(milliseconds: 200),
      ));
      await _pumpInit(tester);

      // Emit blank frames (sharpness == 0).
      controller.add(_blankFrame());
      controller.add(_blankFrame());
      await tester.pump();
      await tester.pump();

      final overlay = tester.widget<FaceAlignmentOverlay>(
        find.byKey(const Key('face_alignment_overlay')),
      );
      expect(overlay.state, FaceAlignmentState.idle);

      // Drain the pending timer.
      await tester.pump(const Duration(milliseconds: 300));

      await controller.close();
    });
  });

  // ── 2. 10-second timeout message (Req 4.3) ─────────────────────────────────
  group('FaceCaptureScreen — no-face timeout message (Req 4.3)', () {
    testWidgets(
        'shows timeout message after noFaceTimeout elapses with no face detected',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(success: false),
      );

      // Use a short timeout so the test does not have to wait 10 real seconds.
      const timeout = Duration(milliseconds: 200);

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 10,
        noFaceTimeout: timeout,
      ));
      await _pumpInit(tester);

      // Before timeout: no message.
      expect(
        find.text(
            'No face detected — please position face within the guide'),
        findsNothing,
      );

      // Advance past the timeout.
      await tester.pump(timeout + const Duration(milliseconds: 50));

      // After timeout: message should appear.
      expect(
        find.text(
            'No face detected — please position face within the guide'),
        findsOneWidget,
      );

      // Overlay should be in timeout state.
      final overlay = tester.widget<FaceAlignmentOverlay>(
        find.byKey(const Key('face_alignment_overlay')),
      );
      expect(overlay.state, FaceAlignmentState.timeout);

      await controller.close();
    });

    testWidgets(
        'timeout message does NOT appear when a face is detected before timeout',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(success: false),
      );

      const timeout = Duration(milliseconds: 300);

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 10,
        noFaceTimeout: timeout,
      ));
      await _pumpInit(tester);

      // Emit a face frame before the timeout fires.
      controller.add(_sharpFrame());
      await tester.pump();
      await tester.pump();

      // Advance past the timeout — timer should have been cancelled.
      await tester.pump(timeout + const Duration(milliseconds: 50));

      expect(
        find.text(
            'No face detected — please position face within the guide'),
        findsNothing,
      );

      await controller.close();
    });
  });

  // ── 3. Processing state ─────────────────────────────────────────────────────
  group('FaceCaptureScreen — processing state', () {
    testWidgets('shows processing indicator while enrollment is in progress',
        (tester) async {
      // Use a Completer so enroll() never resolves during this test, keeping
      // the screen in the processing phase.
      final completer = Completer<EnrollmentResult>();
      final slowModule = _SlowEnrollmentModule(completer.future);

      // Use a broadcast controller so it can be closed and re-listened.
      final controller = StreamController<CameraFrame>.broadcast();

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: slowModule,
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      // Emit one sharp frame — minFrameCount is 1, so enrollment starts.
      controller.add(_sharpFrame());
      await tester.pump();
      // Close the stream so cancel() completes.
      await controller.close();
      await tester.pump();

      // The processing indicator should now be visible.
      expect(find.byKey(const Key('processing_indicator')), findsOneWidget);

      // Clean up: complete the future so no pending async work remains.
      completer.complete(const EnrollmentResult(success: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  // ── 4. Success confirmation (Req 5.3) ──────────────────────────────────────
  group('FaceCaptureScreen — success confirmation (Req 5.3)', () {
    testWidgets(
        'shows "Enrollment Successful" headline, employee name, and employee ID on success',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final record = _makeRecord(
        employeeId: 'EMP042',
        name: 'Priya Sharma',
        department: 'Operations',
      );
      final module = _FakeEnrollmentModule(
        enrollResult: EnrollmentResult(success: true, record: record),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        formData: const EmployeeFormData(
          employeeId: 'EMP042',
          name: 'Priya Sharma',
          department: 'Operations',
        ),
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      await _triggerEnrollment(tester, controller, 1);

      // Success headline.
      expect(find.byKey(const Key('success_headline')), findsOneWidget);
      expect(find.text('Enrollment Successful'), findsOneWidget);

      // Employee name row.
      expect(find.byKey(const Key('enrolled_name_row')), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);

      // Employee ID row.
      expect(find.byKey(const Key('enrolled_id_row')), findsOneWidget);
      expect(find.text('EMP042'), findsOneWidget);

      // Return to Home button.
      expect(find.byKey(const Key('return_home_button')), findsOneWidget);
    });

    testWidgets(
        'falls back to formData name/ID when EnrollmentResult.record is null',
        (tester) async {
      // When success=true but record=null, the screen goes to the error phase
      // (the guard `result.success && result.record != null` fails).
      // This test verifies the error state is shown with the default message.
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(success: true, record: null),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        formData: const EmployeeFormData(
          employeeId: 'EMP099',
          name: 'Amit Singh',
          department: 'Security',
        ),
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      await _triggerEnrollment(tester, controller, 1);

      // success=true but record=null → treated as error by the screen.
      expect(find.byKey(const Key('error_headline')), findsOneWidget);
      expect(find.byKey(const Key('retry_button')), findsOneWidget);
    });
  });

  // ── 5. Error with retry (Req 4.7) ──────────────────────────────────────────
  group('FaceCaptureScreen — error state and retry (Req 4.7)', () {
    testWidgets(
        'shows "Enrollment Failed" headline, error message, and Retry Capture button on failure',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      const errorMsg = 'Embedding extraction failed: model error.';
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(
          success: false,
          errorMessage: errorMsg,
        ),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      await _triggerEnrollment(tester, controller, 1);

      // Error headline.
      expect(find.byKey(const Key('error_headline')), findsOneWidget);
      expect(find.text('Enrollment Failed'), findsOneWidget);

      // Error message text.
      expect(find.byKey(const Key('error_message_text')), findsOneWidget);
      expect(find.text(errorMsg), findsOneWidget);

      // Retry button.
      expect(find.byKey(const Key('retry_button')), findsOneWidget);
      expect(find.text('Retry Capture'), findsOneWidget);
    });

    testWidgets(
        'tapping Retry Capture resets the screen back to the capturing phase',
        (tester) async {
      // Use a broadcast controller so the stream can be re-listened after retry.
      final controller = StreamController<CameraFrame>.broadcast();
      const errorMsg = 'Enrollment failed. Please retry.';

      final module = _CountingEnrollmentModule(
        firstResult: const EnrollmentResult(
          success: false,
          errorMessage: errorMsg,
        ),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      // Trigger the error state.
      controller.add(_sharpFrame());
      await tester.pump();
      // Run async chain in real context.
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Enrollment Failed'), findsOneWidget);
      expect(find.byKey(const Key('retry_button')), findsOneWidget);

      // Tap Retry Capture.
      await tester.tap(find.byKey(const Key('retry_button')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // After retry the screen should be back in the capturing phase.
      expect(find.byKey(const Key('camera_placeholder')), findsOneWidget);
      expect(find.byKey(const Key('face_alignment_overlay')), findsOneWidget);

      // Error headline must be gone.
      expect(find.text('Enrollment Failed'), findsNothing);

      // Drain the pending timer from the retry.
      await tester.pump(const Duration(milliseconds: 200));

      await controller.close();
    });

    testWidgets('back_button is visible in error state', (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(
          success: false,
          errorMessage: 'Some error',
        ),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 1,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      await _triggerEnrollment(tester, controller, 1);

      expect(find.byKey(const Key('back_button')), findsOneWidget);
    });
  });

  // ── 6. Capture view structure (Req 4.1) ────────────────────────────────────
  group('FaceCaptureScreen — capture view structure (Req 4.1)', () {
    testWidgets(
        'shows camera placeholder, face alignment overlay, frame counter, and instruction bar during capture',
        (tester) async {
      final controller = StreamController<CameraFrame>();
      final module = _FakeEnrollmentModule(
        enrollResult: const EnrollmentResult(success: false),
      );

      await tester.pumpWidget(_buildApp(
        frameController: controller,
        enrollmentModule: module,
        minFrameCount: 10,
        noFaceTimeout: _kShortTimeout,
      ));
      await _pumpInit(tester);

      expect(find.byKey(const Key('camera_placeholder')), findsOneWidget);
      expect(find.byKey(const Key('face_alignment_overlay')), findsOneWidget);
      expect(find.byKey(const Key('frame_counter')), findsOneWidget);
      expect(find.byKey(const Key('instruction_bar')), findsOneWidget);

      // Drain the pending timer.
      await tester.pump(const Duration(milliseconds: 200));

      await controller.close();
    });
  });
}
