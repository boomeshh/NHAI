import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/app.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_interface.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/ui/screens/multi_pose_enrollment_screen.dart'
    show PoseObservation;

import '../helpers/in_memory_storage.dart';

class _PipelineAuthEngine implements AuthEngineInterface {
  final InMemoryStorage storage;
  final FaceEmbedding embedding;

  _PipelineAuthEngine(this.storage)
      : embedding = FaceEmbedding(List.filled(128, 1.0));

  @override
  Future<FaceEmbedding> extractEmbedding(CameraFrame frame) async {
    return embedding;
  }

  @override
  Future<AuthResult> authenticate(CameraFrame frame) async {
    final records = await storage.getAllEmployeeRecords();
    if (records.isEmpty) {
      return const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: 'Face not recognized',
      );
    }

    return AuthResult(
      classification: AuthClassification.verified,
      trustScore: 0.96,
      matchedEmployeeId: records.first.employeeId,
    );
  }

  @override
  Future<AuthResult> authenticateAveraged(List<CameraFrame> frames) =>
      authenticate(frames.last);
}

CameraFrame _sharpFrame() {
  return const CameraFrame(
    bytes: [1, 2, 3],
    width: 640,
    height: 480,
    sharpnessScore: 1.0,
  );
}

NhaiApp _buildPipelineApp({
  required InMemoryStorage storage,
  required StreamController<CameraFrame> captureFrames,
  required StreamController<CameraFrame> authFrames,
  String initialRoute = '/home',
}) {
  final authEngine = _PipelineAuthEngine(storage);
  final enrollmentModule = EnrollmentModuleImpl(
    authEngine: authEngine,
    storage: storage,
  );

  return NhaiApp(
    storageManager: storage,
    authEngine: authEngine,
    enrollmentModule: enrollmentModule,
    initialRoute: initialRoute,
    faceCaptureFrameProvider: () => captureFrames.stream,
    authFrameProvider: () => authFrames.stream,
    multiPoseProvider: _poseObservations,
    faceCaptureMinFrameCount: 1,
    faceCaptureNoFaceTimeout: const Duration(milliseconds: 500),
  );
}

/// 5 valid frames for each of the 5 poses → completes the guided enrollment.
Stream<PoseObservation> _poseObservations() => Stream.fromIterable([
      for (final a in const [
        [0.0, 0.0], [-20.0, 0.0], [20.0, 0.0], [0.0, 15.0], [0.0, -15.0]
      ])
        for (var i = 0; i < 5; i++)
          PoseObservation(
              frame: _sharpFrame(), yaw: a[0], pitch: a[1], valid: true),
    ]);

Future<void> _flushAsync(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
  await tester.pump();
}

Future<void> _submitEnrollmentForm(
  WidgetTester tester, {
  required String employeeId,
  required String name,
  required String department,
}) async {
  await tester.enterText(
      find.byKey(const Key('employee_id_field')), employeeId);
  await tester.enterText(find.byKey(const Key('name_field')), name);
  await tester.enterText(find.byKey(const Key('department_field')), department);
  await tester.tap(find.byKey(const Key('submit_button')));
  await tester.pump();
  await _flushAsync(tester);
}

void main() {
  group('Application shell and enrollment-authentication pipeline', () {
    testWidgets('critical error screen blocks operations when storage fails',
        (tester) async {
      await tester.pumpWidget(
        const CriticalErrorApp(
          message: 'AES key unavailable',
        ),
      );

      expect(find.byKey(const Key('critical_error_screen')), findsOneWidget);
      expect(find.text('Secure Storage Unavailable'), findsOneWidget);
      expect(find.text('AES key unavailable'), findsOneWidget);
      expect(find.byKey(const Key('enroll_employee_button')), findsNothing);
      expect(
          find.byKey(const Key('authenticate_employee_button')), findsNothing);
    });

    testWidgets('launches to HomeScreen within 3 seconds', (tester) async {
      final storage = InMemoryStorage();
      final captureFrames = StreamController<CameraFrame>.broadcast();
      final authFrames = StreamController<CameraFrame>.broadcast();

      await tester.pumpWidget(
        _buildPipelineApp(
          storage: storage,
          captureFrames: captureFrames,
          authFrames: authFrames,
          initialRoute: '/',
        ),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('NHAI Authentication'), findsOneWidget);
      expect(find.text('Offline Mode Active'), findsOneWidget);

      await captureFrames.close();
      await authFrames.close();
    });

    testWidgets('full flow: enroll employee then authenticate same employee',
        (tester) async {
      final storage = InMemoryStorage();
      final captureFrames = StreamController<CameraFrame>.broadcast();
      final authFrames = StreamController<CameraFrame>.broadcast();

      await tester.pumpWidget(
        _buildPipelineApp(
          storage: storage,
          captureFrames: captureFrames,
          authFrames: authFrames,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('enroll_employee_button')));
      await tester.pumpAndSettle();

      await _submitEnrollmentForm(
        tester,
        employeeId: 'EMP100',
        name: 'Ananya Rao',
        department: 'Operations',
      );

      // Guided multi-pose enrollment screen — drains the 25-frame pose stream.
      expect(find.byKey(const Key('multi_pose_enrollment_screen')),
          findsOneWidget);
      await _flushAsync(tester);
      await _flushAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('Enrollment Successful'), findsOneWidget);
      expect(storage.records['EMP100']?.name, 'Ananya Rao');
      expect(storage.records['EMP100']?.templates?.length, 5);

      await tester.tap(find.byKey(const Key('return_home_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('authenticate_employee_button')));
      await tester.pump();
      await tester.pump();

      authFrames.add(_sharpFrame());
      await tester.pump();
      await _flushAsync(tester);

      expect(find.text('Identity Verified'), findsOneWidget);
      expect(find.text('Ananya Rao'), findsOneWidget);
      expect(find.text('EMP100'), findsOneWidget);
      expect(find.text('Operations'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);
      expect(storage.logs, hasLength(1));
      expect(storage.logs.single.employeeId, 'EMP100');

      await captureFrames.close();
      await authFrames.close();
    });

    testWidgets('duplicate ID overwrite flow replaces the record',
        (tester) async {
      final storage = InMemoryStorage();
      final captureFrames = StreamController<CameraFrame>.broadcast();
      final authFrames = StreamController<CameraFrame>.broadcast();

      await storage.saveEmployeeRecord(
        EmployeeRecord(
          employeeId: 'EMP200',
          name: 'Old Name',
          department: 'Old Department',
          embedding: FaceEmbedding(List.filled(128, 0.2)),
          enrolledAt: DateTime.utc(2025, 1, 1),
        ),
      );

      await tester.pumpWidget(
        _buildPipelineApp(
          storage: storage,
          captureFrames: captureFrames,
          authFrames: authFrames,
          initialRoute: '/enroll',
        ),
      );
      await tester.pump();

      await _submitEnrollmentForm(
        tester,
        employeeId: 'EMP200',
        name: 'New Name',
        department: 'New Department',
      );

      expect(find.text('Duplicate Record'), findsOneWidget);
      await tester.tap(find.byKey(const Key('duplicate_dialog_overwrite')));
      await tester.pumpAndSettle();

      // Drain the 25-frame pose stream + async enrollMultiPose.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump();

      // The overwrite replaced the record with a 5-pose gallery (the purpose of
      // this test). UI success is covered by the full-flow + screen tests.
      expect(storage.records['EMP200']?.name, 'New Name');
      expect(storage.records['EMP200']?.department, 'New Department');
      expect(storage.records['EMP200']?.templates?.length, 5);

      await captureFrames.close();
      await authFrames.close();
    });
  });
}
