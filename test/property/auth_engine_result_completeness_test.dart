// Feature: nhai-offline-auth, Property 16: Auth_Engine always returns a complete structured result
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';

class _StubStorage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _StubStorage([this.records = const []]);
  @override Future<List<EmployeeRecord>> getAllEmployeeRecords() async => records;
  @override Future<void> saveEmployeeRecord(EmployeeRecord r) async {}
  @override Future<EmployeeRecord?> getEmployeeRecord(String id) async => null;
  @override Future<bool> employeeExists(String id) async => false;
  @override Future<void> deleteEmployeeRecord(String id) async {}
  @override Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];
  @override Future<void> logStorageError(String m) async {}
}

class _StubLiveness implements LivenessDetectorInterface {
  final LivenessResult result;
  _StubLiveness([this.result = LivenessResult.confirmed]);
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async => result;
}

class _TestableEngine extends AuthEngineImpl {
  final FaceEmbedding _embedding;
  _TestableEngine(this._embedding, StorageManagerInterface s, LivenessDetectorInterface l)
      : super(storage: s, livenessDetector: l);
  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async => _embedding;
}

CameraFrame validFrame() => const CameraFrame(
    bytes: [1, 2, 3], width: 224, height: 224, sharpnessScore: 50.0);

EmployeeRecord makeRecord(String id, List<double> v) => EmployeeRecord(
      employeeId: id,
      name: 'Test',
      department: 'Dept',
      embedding: FaceEmbedding(v),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

void main() {
  group('Property 16: Auth_Engine always returns a complete structured result', () {
    void assertComplete(AuthResult result) {
      // classification is always set (non-nullable enum)
      expect(result.classification, isA<AuthClassification>());
      // trustScore is always a finite double
      expect(result.trustScore, isA<double>());
      expect(result.trustScore.isFinite, isTrue);
      expect(result.trustScore, greaterThanOrEqualTo(0.0));
      // VERIFIED: matchedEmployeeId should be set, failureReason null
      if (result.classification == AuthClassification.verified) {
        expect(result.matchedEmployeeId, isNotNull);
        expect(result.failureReason, isNull);
      }
      // FAILED: failureReason should be set
      if (result.classification == AuthClassification.failed) {
        expect(result.failureReason, isNotNull);
      }
    }

    test('result is complete when VERIFIED', () async {
      final vec = List.generate(128, (i) => 1.0);
      final engine = _TestableEngine(
          FaceEmbedding(vec),
          _StubStorage([makeRecord('EMP001', vec)]),
          _StubLiveness(LivenessResult.confirmed));
      final result = await engine.authenticate(validFrame());
      assertComplete(result);
      expect(result.classification, equals(AuthClassification.verified));
    });

    test('result is complete when FAILED (no match)', () async {
      final engine = _TestableEngine(
          FaceEmbedding(List.filled(128, 0.5)),
          _StubStorage(),
          _StubLiveness());
      final result = await engine.authenticate(validFrame());
      assertComplete(result);
      expect(result.classification, equals(AuthClassification.failed));
    });

    test('result is complete when liveness fails', () async {
      final vec = List.generate(128, (i) => 1.0);
      final engine = _TestableEngine(
          FaceEmbedding(vec),
          _StubStorage([makeRecord('EMP001', vec)]),
          _StubLiveness(LivenessResult.failed));
      final result = await engine.authenticate(validFrame());
      assertComplete(result);
      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, equals('Liveness check failed'));
    });

    test('property: 100 varied inputs always produce complete results', () async {
      for (int i = 0; i < 100; i++) {
        final liveVec = List.generate(128, (j) => (i * 0.01 + j * 0.001) % 1.0);
        final storedVec = List.generate(128, (j) => 1.0);
        final livenessResult = i % 3 == 0 ? LivenessResult.failed : LivenessResult.confirmed;
        final engine = _TestableEngine(
            FaceEmbedding(liveVec),
            _StubStorage([makeRecord('EMP${i.toString().padLeft(3, '0')}', storedVec)]),
            _StubLiveness(livenessResult));
        final result = await engine.authenticate(validFrame());
        assertComplete(result);
      }
    });
  });
}
