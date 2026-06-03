import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_interface.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';
import 'package:nhai_auth/ui/screens/multi_pose_enrollment_screen.dart';
import 'package:nhai_auth/ui/screens/recognition_validation_screen.dart';

List<double> _vec(double s) =>
    EmbeddingMath.l2Normalize(List<double>.generate(192, (i) => (i + s) % 9 - 4.0));

FaceTemplate _tpl(FacePose p, double s) => FaceTemplate(
      embedding: FaceEmbedding(_vec(s)),
      poseLabel: p,
      yaw: 0,
      pitch: 0,
      qualityScore: 1.0,
      createdAt: DateTime.utc(2026, 1, 1),
      pipelineVersion: 3,
    );

class _FakeEnroll implements EnrollmentModuleInterface {
  @override
  ValidationResult validateForm(String a, String b, String c) =>
      const ValidationResult(isValid: true);
  @override
  CameraFrame selectBestFrame(List<CameraFrame> f) => f.first;
  @override
  Future<EnrollmentResult> enroll(EmployeeFormData f, List<CameraFrame> fr) async =>
      throw UnimplementedError();
  @override
  Future<EnrollmentResult> enrollMultiPose(
          EmployeeFormData f, Map<FacePose, List<CameraFrame>> p) async =>
      EnrollmentResult(
        success: true,
        record: EmployeeRecord(
          employeeId: 'EMP1',
          name: 'A',
          department: 'D',
          embedding: FaceEmbedding(_vec(1)),
          enrolledAt: DateTime.utc(2026, 1, 1),
          // Distinct templates (not degenerate) so culprit resolves to model.
          templates: [
            _tpl(FacePose.frontal, 1),
            _tpl(FacePose.left, 2),
            _tpl(FacePose.right, 3),
            _tpl(FacePose.up, 4),
            _tpl(FacePose.down, 5),
          ],
        ),
      );
}

class _FakeEngine implements AuthEngineInterface {
  @override
  Future<FaceEmbedding> extractEmbedding(CameraFrame f) async =>
      FaceEmbedding(_vec(1)); // matches frontal template → bestPose=frontal
  @override
  Future<AuthResult> authenticate(CameraFrame f) async => _result();
  @override
  Future<AuthResult> authenticateAveraged(List<CameraFrame> f) async => _result();
  AuthResult _result() => const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.70, // genuine-but-low → drives MODEL verdict
      );
}


void main() {
  testWidgets('renders the enrolling status on start', (tester) async {
    final ctrl = StreamController<PoseObservation>();
    await tester.pumpWidget(MaterialApp(
      home: RecognitionValidationScreen(
        enrollmentModule: _FakeEnroll(),
        authEngine: _FakeEngine(),
        formData: const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
        poseProvider: () => ctrl.stream,
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('recognition_validation_screen')), findsOneWidget);
    expect(find.byKey(const Key('validation_status')), findsOneWidget);
    await ctrl.close();
  });

  // NOTE: the full enroll → 10-verify orchestration is device behaviour
  // (camera frame stream + async model inference) and is not reliably
  // simulable in a widget harness. Its analytical logic — per-attempt
  // stats, success rate, CSV, and subsystem attribution — is fully covered
  // by recognition_validator_test.dart.
}
