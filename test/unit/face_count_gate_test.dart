import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

class _StubStorage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _StubStorage(this.records);
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => records;
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async {}
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => null;
  @override
  Future<bool> employeeExists(String id) async => false;
  @override
  Future<void> deleteEmployeeRecord(String id) async {}
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];
  @override
  Future<void> logStorageError(String m) async {}
}

class _StubLiveness implements LivenessDetectorInterface {
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async =>
      LivenessResult.confirmed;
}

class _FakeEngine extends AuthEngineImpl {
  _FakeEngine(StorageManagerInterface s)
      : super(storage: s, livenessDetector: _StubLiveness());
  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async =>
      FaceEmbedding(List<double>.filled(128, 1.0));
}

CameraFrame _frame({required int faceCount}) => CameraFrame(
      bytes: const [1, 2, 3],
      width: 112,
      height: 112,
      sharpnessScore: 50.0,
      faceCount: faceCount,
    );

void main() {
  group('Fail-closed face-count gate (Task 11)', () {
    test('no face (faceCount=0) → FAILED "No face detected"', () async {
      final engine = _FakeEngine(_StubStorage([]));
      final r = await engine.authenticate(_frame(faceCount: 0));
      expect(r.classification, AuthClassification.failed);
      expect(r.failureReason, 'No face detected');
      expect(r.trustScore, 0.0);
    });

    test('multiple faces (faceCount=2) → FAILED "Multiple faces detected"',
        () async {
      final engine = _FakeEngine(_StubStorage([]));
      final r = await engine.authenticate(_frame(faceCount: 2));
      expect(r.classification, AuthClassification.failed);
      expect(r.failureReason, 'Multiple faces detected');
    });

    test('single face proceeds to matching (default faceCount=1)', () async {
      // Empty store → "Face not recognized", proving the gate let it through.
      final engine = _FakeEngine(_StubStorage([]));
      final r = await engine.authenticate(_frame(faceCount: 1));
      expect(r.classification, AuthClassification.failed);
      expect(r.failureReason, 'Face not recognized');
    });
  });
}
