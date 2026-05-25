import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/auth_engine/embedding_error.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Stub storage that holds an in-memory list of [EmployeeRecord]s.
class _StubStorage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _StubStorage(this.records);

  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => records;

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord record) async {}

  @override
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async => null;

  @override
  Future<bool> employeeExists(String employeeId) async => false;

  @override
  Future<void> deleteEmployeeRecord(String employeeId) async {}

  @override
  Future<void> logAuthAttempt(AuthLogEntry entry) async {}

  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];

  @override
  Future<void> logStorageError(String message) async {}
}

/// Stub liveness detector that returns a configurable result.
class _StubLiveness implements LivenessDetectorInterface {
  final LivenessResult result;
  _StubLiveness(this.result);

  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> frameStream) async =>
      result;
}

/// [AuthEngineImpl] subclass that overrides [runInference] to return a
/// fixed embedding, allowing tests to bypass the real TFLite model.
class _FakeAuthEngine extends AuthEngineImpl {
  final FaceEmbedding? _fixedEmbedding;
  final EmbeddingError? _inferenceError;

  _FakeAuthEngine({
    required super.storage,
    required super.livenessDetector,
    FaceEmbedding? fixedEmbedding,
    EmbeddingError? inferenceError,
  })  : _fixedEmbedding = fixedEmbedding,
        _inferenceError = inferenceError;

  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async {
    final err = _inferenceError;
    if (err != null) throw err;
    return _fixedEmbedding!;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a 128-dim vector filled with [value].
List<double> _vec(double value) => List.filled(128, value);

/// Creates a normalised 128-dim vector pointing in the direction of [value].
List<double> _normVec(double value) {
  final v = List.filled(128, value);
  final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
  return v.map((x) => x / norm).toList();
}

/// Builds a valid [CameraFrame] with non-empty bytes and good sharpness.
CameraFrame _goodFrame() => const CameraFrame(
      bytes: [1, 2, 3],
      width: 112,
      height: 112,
      sharpnessScore: 50.0,
    );

/// Builds an [EmployeeRecord] with the given [id] and [embedding].
EmployeeRecord _record(String id, List<double> embedding) => EmployeeRecord(
      employeeId: id,
      name: 'Test Employee',
      department: 'Engineering',
      embedding: FaceEmbedding(embedding),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // A plain engine instance used for pure-math tests (no inference needed).
  late AuthEngineImpl engine;

  setUp(() {
    engine = AuthEngineImpl(
      storage: _StubStorage([]),
      livenessDetector: _StubLiveness(LivenessResult.confirmed),
    );
  });

  // -------------------------------------------------------------------------
  // 1. cosineSimilarity — known vector pairs
  // -------------------------------------------------------------------------
  group('cosineSimilarity', () {
    test('identical vectors → 1.0', () {
      final a = _vec(0.5);
      expect(engine.cosineSimilarity(a, a), closeTo(1.0, 1e-9));
    });

    test('identical unit vectors → 1.0', () {
      final a = _normVec(1.0);
      expect(engine.cosineSimilarity(a, a), closeTo(1.0, 1e-9));
    });

    test('opposite vectors → -1.0', () {
      final a = _normVec(1.0);
      final b = a.map((x) => -x).toList();
      expect(engine.cosineSimilarity(a, b), closeTo(-1.0, 1e-9));
    });

    test('orthogonal vectors → 0.0', () {
      // a has non-zero values only in even indices, b only in odd indices.
      final a = List<double>.generate(128, (i) => i.isEven ? 1.0 : 0.0);
      final b = List<double>.generate(128, (i) => i.isOdd ? 1.0 : 0.0);
      expect(engine.cosineSimilarity(a, b), closeTo(0.0, 1e-9));
    });

    test('zero vector → 0.0 (no division by zero)', () {
      final a = _vec(0.0);
      final b = _vec(1.0);
      expect(engine.cosineSimilarity(a, b), equals(0.0));
    });

    test('both zero vectors → 0.0', () {
      final a = _vec(0.0);
      expect(engine.cosineSimilarity(a, a), equals(0.0));
    });

    test('known partial overlap produces expected score', () {
      // a = [1, 0, 0, …], b = [1, 1, 0, …] (128-dim)
      final a = List<double>.generate(128, (i) => i == 0 ? 1.0 : 0.0);
      final b = List<double>.generate(128, (i) => i < 2 ? 1.0 : 0.0);
      // cos = 1 / (1 * sqrt(2)) = 1/sqrt(2) ≈ 0.7071
      expect(engine.cosineSimilarity(a, b),
          closeTo(1.0 / math.sqrt(2), 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  // 2. classify — threshold boundary
  // -------------------------------------------------------------------------
  group('classify', () {
    test('score 0.75 → VERIFIED (at threshold)', () {
      expect(engine.classify(0.75), equals(AuthClassification.verified));
    });

    test('score 0.74 → FAILED (just below threshold)', () {
      expect(engine.classify(0.74), equals(AuthClassification.failed));
    });

    test('score 1.0 → VERIFIED', () {
      expect(engine.classify(1.0), equals(AuthClassification.verified));
    });

    test('score 0.0 → FAILED', () {
      expect(engine.classify(0.0), equals(AuthClassification.failed));
    });

    test('score 0.9 → VERIFIED', () {
      expect(engine.classify(0.9), equals(AuthClassification.verified));
    });

    test('score 0.749999 → FAILED', () {
      expect(engine.classify(0.749999), equals(AuthClassification.failed));
    });

    test('score 0.750001 → VERIFIED', () {
      expect(engine.classify(0.750001), equals(AuthClassification.verified));
    });
  });

  // -------------------------------------------------------------------------
  // 3. extractEmbedding — error conditions
  // -------------------------------------------------------------------------
  group('extractEmbedding', () {
    test('empty bytes → EmbeddingError(noFaceDetected)', () async {
      const emptyFrame = CameraFrame(
        bytes: [],
        width: 112,
        height: 112,
        sharpnessScore: 50.0,
      );
      expect(
        () => engine.extractEmbedding(emptyFrame),
        throwsA(
          isA<EmbeddingError>().having(
            (e) => e.code,
            'code',
            EmbeddingErrorCode.noFaceDetected,
          ),
        ),
      );
    });

    test('low sharpness → EmbeddingError(lowQualityFrame)', () async {
      const blurryFrame = CameraFrame(
        bytes: [1, 2, 3],
        width: 112,
        height: 112,
        sharpnessScore: 5.0, // below 10.0 threshold
      );
      expect(
        () => engine.extractEmbedding(blurryFrame),
        throwsA(
          isA<EmbeddingError>().having(
            (e) => e.code,
            'code',
            EmbeddingErrorCode.lowQualityFrame,
          ),
        ),
      );
    });

    test('sharpness exactly 10.0 passes quality check', () async {
      // Use a _FakeAuthEngine so runInference returns a known embedding.
      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(_vec(0.5)),
      );
      const borderFrame = CameraFrame(
        bytes: [1, 2, 3],
        width: 112,
        height: 112,
        sharpnessScore: 10.0,
      );
      final embedding = await fakeEngine.extractEmbedding(borderFrame);
      expect(embedding.vector.length, equals(128));
    });

    test('inference error is wrapped as modelInferenceFailed', () async {
      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        inferenceError: const EmbeddingError(
          EmbeddingErrorCode.modelInferenceFailed,
          'TFLite error',
        ),
      );
      expect(
        () => fakeEngine.extractEmbedding(_goodFrame()),
        throwsA(
          isA<EmbeddingError>().having(
            (e) => e.code,
            'code',
            EmbeddingErrorCode.modelInferenceFailed,
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 4. authenticate — matching embedding → VERIFIED
  // -------------------------------------------------------------------------
  group('authenticate — matching embedding', () {
    test('identical embedding → VERIFIED with correct matchedEmployeeId',
        () async {
      final liveVec = _normVec(1.0);
      final storedRecord = _record('EMP001', liveVec);

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([storedRecord]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.verified));
      expect(result.matchedEmployeeId, equals('EMP001'));
      expect(result.failureReason, isNull);
      expect(result.trustScore, closeTo(1.0, 1e-9));
    });

    test('best-matching employee is returned when multiple records exist',
        () async {
      final liveVec = _normVec(1.0);
      final closeVec = _normVec(0.99); // very similar but not identical
      final farVec = _normVec(-1.0);   // opposite direction

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([
          _record('EMP_FAR', farVec),
          _record('EMP_CLOSE', closeVec),
        ]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.verified));
      expect(result.matchedEmployeeId, equals('EMP_CLOSE'));
    });
  });

  // -------------------------------------------------------------------------
  // 5. authenticate — non-matching embedding → FAILED
  // -------------------------------------------------------------------------
  group('authenticate — non-matching embedding', () {
    test('low similarity → FAILED with "Face not recognized"', () async {
      final liveVec = _normVec(1.0);
      // Orthogonal stored vector → similarity ≈ 0.0
      final storedVec =
          List<double>.generate(128, (i) => i.isOdd ? 1.0 : 0.0);
      final norm =
          math.sqrt(storedVec.fold(0.0, (s, x) => s + x * x));
      final normStoredVec = storedVec.map((x) => x / norm).toList();

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', normStoredVec)]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, equals('Face not recognized'));
      expect(result.matchedEmployeeId, isNull);
    });

    test('score just below threshold (0.74) → FAILED', () async {
      // Construct two vectors whose cosine similarity is just below 0.75.
      // We use a known pair: a = [1, 0, 0, …], b = [cos θ, sin θ, 0, …]
      // where θ = arccos(0.74).
      final theta = math.acos(0.74);
      final liveVec = List<double>.generate(128, (i) => i == 0 ? 1.0 : 0.0);
      final storedVec = List<double>.generate(
          128, (i) => i == 0 ? math.cos(theta) : (i == 1 ? math.sin(theta) : 0.0));

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', storedVec)]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.trustScore, closeTo(0.74, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  // 6. authenticate — empty store → FAILED
  // -------------------------------------------------------------------------
  group('authenticate — empty store', () {
    test('no stored records → FAILED with "Face not recognized"', () async {
      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(_normVec(1.0)),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, equals('Face not recognized'));
      expect(result.trustScore, equals(0.0));
    });
  });

  // -------------------------------------------------------------------------
  // 7. authenticate — liveness failure propagation
  // -------------------------------------------------------------------------
  group('authenticate — liveness failure', () {
    test('liveness failed → FAILED with "Liveness check failed"', () async {
      final liveVec = _normVec(1.0);

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', liveVec)]),
        livenessDetector: _StubLiveness(LivenessResult.failed), // liveness fails
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, equals('Liveness check failed'));
      // matchedEmployeeId is still set (face matched before liveness check)
      expect(result.matchedEmployeeId, equals('EMP001'));
    });

    test('liveness not triggered when face match fails', () async {
      // Use a liveness stub that would return confirmed — but it should
      // never be called because the face match fails first.
      var livenessCallCount = 0;

      final countingLiveness = _CountingLiveness(
        result: LivenessResult.confirmed,
        onCall: () => livenessCallCount++,
      );

      final liveVec = _normVec(1.0);
      final orthogonalVec =
          List<double>.generate(128, (i) => i.isOdd ? 1.0 : 0.0);
      final norm =
          math.sqrt(orthogonalVec.fold(0.0, (s, x) => s + x * x));
      final normOrthogonal = orthogonalVec.map((x) => x / norm).toList();

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', normOrthogonal)]),
        livenessDetector: countingLiveness,
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(livenessCallCount, equals(0),
          reason: 'Liveness must not be triggered when face match fails');
    });
  });

  // -------------------------------------------------------------------------
  // 8. authenticate — embedding extraction error → FAILED
  // -------------------------------------------------------------------------
  group('authenticate — embedding extraction error', () {
    test('noFaceDetected error → FAILED with error message', () async {
      const frame = CameraFrame(
        bytes: [],
        width: 112,
        height: 112,
        sharpnessScore: 50.0,
      );

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', _normVec(1.0))]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(_normVec(1.0)),
      );

      final result = await fakeEngine.authenticate(frame);

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, isNotNull);
      expect(result.failureReason, contains('No face detected'));
    });

    test('lowQualityFrame error → FAILED with error message', () async {
      const blurryFrame = CameraFrame(
        bytes: [1, 2, 3],
        width: 112,
        height: 112,
        sharpnessScore: 3.0,
      );

      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', _normVec(1.0))]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(_normVec(1.0)),
      );

      final result = await fakeEngine.authenticate(blurryFrame);

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, isNotNull);
      expect(result.failureReason, contains('quality'));
    });

    test('modelInferenceFailed error → FAILED with error message', () async {
      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage([_record('EMP001', _normVec(1.0))]),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        inferenceError: const EmbeddingError(
          EmbeddingErrorCode.modelInferenceFailed,
          'TFLite crashed',
        ),
      );

      final result = await fakeEngine.authenticate(_goodFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, isNotNull);
      expect(result.failureReason, contains('TFLite crashed'));
    });
  });

  // -------------------------------------------------------------------------
  // 9. Performance: authenticate completes within 2 seconds (Req 7.1)
  // -------------------------------------------------------------------------
  group('performance', () {
    test('authenticate completes within 2 seconds', () async {
      // Build a store with 100 records to simulate a realistic load.
      final records = List.generate(
        100,
        (i) => _record('EMP${i.toString().padLeft(3, '0')}', _normVec(i * 0.01)),
      );

      final liveVec = _normVec(1.0);
      final fakeEngine = _FakeAuthEngine(
        storage: _StubStorage(records),
        livenessDetector: _StubLiveness(LivenessResult.confirmed),
        fixedEmbedding: FaceEmbedding(liveVec),
      );

      final stopwatch = Stopwatch()..start();
      await fakeEngine.authenticate(_goodFrame());
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'authenticate must complete within 2 seconds (Req 7.1)',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Additional test double for liveness call counting
// ---------------------------------------------------------------------------

class _CountingLiveness implements LivenessDetectorInterface {
  final LivenessResult result;
  final void Function() onCall;

  _CountingLiveness({required this.result, required this.onCall});

  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> frameStream) async {
    onCall();
    return result;
  }
}
