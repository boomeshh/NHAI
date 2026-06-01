import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/core/recognition/stable_embedding_collector.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

class _Storage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _Storage(this.records);
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

class _Liveness implements LivenessDetectorInterface {
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async =>
      LivenessResult.confirmed;
}

/// Counts extraction calls and returns a distinct embedding per frame, so a
/// test can prove every collected frame was embedded and averaged.
class _CountingEngine extends AuthEngineImpl {
  int extractCalls = 0;
  _CountingEngine(StorageManagerInterface s)
      : super(storage: s, livenessDetector: _Liveness(), livenessEnabled: false);

  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async {
    extractCalls++;
    // Distinct vector keyed by the frame's first byte.
    final seed = frame.bytes.first.toDouble();
    return FaceEmbedding(List<double>.generate(128, (i) => (i + seed) % 7 + 1));
  }
}

CameraFrame _frame(int seed) => CameraFrame(
    bytes: [seed], width: 112, height: 112, sharpnessScore: 50.0);

void main() {
  group('StableEmbeddingCollector', () {
    test('ignores offers until armed', () {
      final c = StableEmbeddingCollector<int>(target: 5);
      expect(c.offer(1, valid: true), isFalse);
      expect(c.count, 0);
    });

    test('collects exactly [target] valid frames then completes', () {
      final c = StableEmbeddingCollector<int>(target: 5);
      c.arm();
      for (var i = 1; i <= 5; i++) {
        expect(c.offer(i, valid: true), isTrue);
        expect(c.count, i);
      }
      expect(c.isComplete, isTrue);
      // Further offers are ignored once complete.
      expect(c.offer(6, valid: true), isFalse);
      expect(c.count, 5);
    });

    test('invalid frames (blink/occlusion) are ignored, never reset buffer', () {
      final c = StableEmbeddingCollector<int>(target: 5);
      c.arm();
      c.offer(1, valid: true);
      c.offer(2, valid: true);
      // Blink: eyes-closed (invalid) frames must NOT clear the buffer.
      expect(c.offer(99, valid: false), isFalse);
      expect(c.offer(98, valid: false), isFalse);
      expect(c.count, 2); // preserved — this is the bug fix
      c.offer(3, valid: true);
      c.offer(4, valid: true);
      c.offer(5, valid: true);
      expect(c.isComplete, isTrue);
    });

    test('reset disarms and clears', () {
      final c = StableEmbeddingCollector<int>(target: 3);
      c.arm();
      c.offer(1, valid: true);
      c.reset();
      expect(c.isArmed, isFalse);
      expect(c.count, 0);
    });
  });

  group('authenticateAveraged uses ALL collected embeddings (runtime proof)', () {
    test('5 collected frames → 5 embeddings extracted and averaged', () async {
      // Enroll the exact average of the 5 frame embeddings so a correct
      // multi-frame average matches (and a single-frame path would not).
      final engine0 = _CountingEngine(_Storage([]));
      final vecs = <List<double>>[];
      for (var i = 1; i <= 5; i++) {
        vecs.add((await engine0.runInference(_frame(i))).vector);
      }
      final avg = EmbeddingMath.averageNormalized(vecs);

      final engine = _CountingEngine(_Storage([
        EmployeeRecord(
          employeeId: 'EMP1',
          name: 'A',
          department: 'D',
          embedding: FaceEmbedding(avg),
          enrolledAt: DateTime.utc(2026, 1, 1),
        ),
      ]));

      final frames = [for (var i = 1; i <= 5; i++) _frame(i)];
      final result = await engine.authenticateAveraged(frames);

      // Proves every collected frame was embedded (not just 1).
      expect(engine.extractCalls, equals(5));
      // The averaged live embedding matches the enrolled average → verified.
      expect(result.classification, AuthClassification.verified);
      expect(result.trustScore, closeTo(1.0, 1e-6));
    });
  });
}
