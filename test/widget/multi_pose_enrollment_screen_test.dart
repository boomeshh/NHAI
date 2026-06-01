import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';
import 'package:nhai_auth/ui/screens/multi_pose_enrollment_screen.dart';

class _FakeModule implements EnrollmentModuleInterface {
  Map<FacePose, List<CameraFrame>>? captured;
  final EnrollmentResult result;
  _FakeModule(this.result);

  @override
  ValidationResult validateForm(String id, String name, String dept) =>
      const ValidationResult(isValid: true);
  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;
  @override
  Future<EnrollmentResult> enroll(
          EmployeeFormData formData, List<CameraFrame> frames) async =>
      throw UnimplementedError();
  @override
  Future<EnrollmentResult> enrollMultiPose(
    EmployeeFormData formData,
    Map<FacePose, List<CameraFrame>> posedFrames,
  ) async {
    captured = posedFrames;
    return result;
  }
}

CameraFrame _frame() =>
    const CameraFrame(bytes: [1], width: 112, height: 112, sharpnessScore: 50.0);

FaceTemplate _tpl(FacePose p) => FaceTemplate(
      embedding: FaceEmbedding(List.filled(192, 0.1)),
      poseLabel: p,
      yaw: 0,
      pitch: 0,
      qualityScore: 1.0,
      createdAt: DateTime.utc(2026, 1, 1),
      pipelineVersion: 3,
    );

EnrollmentResult _success5() => EnrollmentResult(
      success: true,
      record: EmployeeRecord(
        employeeId: 'EMP1',
        name: 'A',
        department: 'D',
        embedding: FaceEmbedding(List.filled(192, 0.1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
        templates: FacePose.values.map(_tpl).toList(),
      ),
    );

Stream<PoseObservation> _allFivePoses() => Stream.fromIterable([
      for (final a in const [
        [0.0, 0.0], [-20.0, 0.0], [20.0, 0.0], [0.0, 15.0], [0.0, -15.0]
      ])
        for (var i = 0; i < 5; i++)
          PoseObservation(frame: _frame(), yaw: a[0], pitch: a[1], valid: true),
    ]);

Widget _wrap(MultiPoseEnrollmentScreen screen) =>
    MaterialApp(home: screen, routes: {'/home': (_) => const SizedBox()});

// Drains the pose stream + async enrollMultiPose without pumpAndSettle (the
// processing spinner animates forever and would make pumpAndSettle time out).
Future<void> _drain(WidgetTester t) async {
  await t.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('shows the first pose instruction and progress on start',
      (tester) async {
    final module = _FakeModule(_success5());
    await tester.pumpWidget(_wrap(MultiPoseEnrollmentScreen(
      enrollmentModule: module,
      formData: const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
      poseProvider: () => const Stream.empty(),
    )));
    await tester.pump();
    expect(find.text('Look Straight'), findsOneWidget);
    expect(find.text('Pose 1/5'), findsOneWidget);
    expect(find.text('Frames 0/5'), findsOneWidget);
  });

  testWidgets('pose progression: 5 frontal frames advance to the LEFT pose',
      (tester) async {
    final module = _FakeModule(_success5());
    await tester.pumpWidget(_wrap(MultiPoseEnrollmentScreen(
      enrollmentModule: module,
      formData: const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
      poseProvider: () => Stream.fromIterable([
        for (var i = 0; i < 5; i++)
          PoseObservation(frame: _frame(), yaw: 0, pitch: 0, valid: true),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Turn Slightly Left'), findsOneWidget);
    expect(find.text('Pose 2/5'), findsOneWidget);
  });

  testWidgets('complete flow: 5 poses × 5 frames → success + 5 templates',
      (tester) async {
    final module = _FakeModule(_success5());
    await tester.pumpWidget(_wrap(MultiPoseEnrollmentScreen(
      enrollmentModule: module,
      formData: const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
      poseProvider: _allFivePoses,
    )));
    await _drain(tester);

    // enrollMultiPose was called with all 5 poses, 5 frames each.
    expect(module.captured, isNotNull);
    expect(module.captured!.keys.toSet(), FacePose.values.toSet());
    expect(module.captured![FacePose.frontal]!.length, 5);

    // Success UI shows the stored template count.
    expect(find.byKey(const Key('enrollment_success')), findsOneWidget);
    expect(find.text('5 pose templates stored'), findsOneWidget);
  });

  testWidgets('enrollment failure surfaces an error', (tester) async {
    final module = _FakeModule(
        const EnrollmentResult(success: false, errorMessage: 'No usable frames'));
    await tester.pumpWidget(_wrap(MultiPoseEnrollmentScreen(
      enrollmentModule: module,
      formData: const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
      poseProvider: _allFivePoses,
    )));
    await _drain(tester);
    expect(find.byKey(const Key('enroll_error')), findsOneWidget);
    expect(find.text('No usable frames'), findsOneWidget);
  });
}
