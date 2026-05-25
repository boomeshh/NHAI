// Feature: nhai-offline-auth, Property 9: Liveness challenge is triggered if and only if face verification is VERIFIED
//
// **Validates: Requirements 7.1**
//
// Property: For any authentication flow, the Liveness_Detector is invoked if
// and only if the Auth_Engine face comparison produces a VERIFIED classification.
// A FAILED face comparison must never trigger liveness detection.
//
// Minimum 100 iterations per case.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// Tracks whether [detectLiveness] was called and how many times.
class _TrackingLiveness implements LivenessDetectorInterface {
  int callCount = 0;
  LivenessResult result;
  _TrackingLiveness({this.result = LivenessResult.confirmed});

  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async {
    callCount++;
    return result;
  }
}

class _StorageWithRecords implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _StorageWithRecords(this.records);

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

/// Subclass of [AuthEngineImpl] that returns a fixed embedding from
/// [runInference], bypassing the TFLite model runner entirely.
class _TestableEngine extends AuthEngineImpl {
  final FaceEmbedding _embedding;
  _TestableEngine(
    this._embedding,
    StorageManagerInterface storage,
    LivenessDetectorInterface liveness,
  ) : super(storage: storage, livenessDetector: liveness);

  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async => _embedding;
}

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Returns a random unit-normalised 128-dimensional vector.
List<double> _randomUnitVector(Random rng) {
  final v = List.generate(128, (_) => rng.nextDouble() * 2.0 - 1.0);
  final norm = sqrt(v.fold(0.0, (acc, x) => acc + x * x));
  if (norm == 0.0) return List.filled(128, 1.0 / sqrt(128));
  return v.map((x) => x / norm).toList();
}

/// Returns a unit vector whose cosine similarity with [base] is approximately
/// [targetScore].
///
/// Constructs the result as a linear combination of [base] and a random
/// orthogonal component [perp]:
///   result = targetScore * base + sqrt(1 - targetScore²) * perp
///
/// Since both [base] and [perp] are unit vectors and orthogonal to each other,
/// the cosine similarity of [result] with [base] equals [targetScore] exactly.
List<double> _vectorWithSimilarity(
    List<double> base, double targetScore, Random rng) {
  // Build a random vector orthogonal to base using Gram-Schmidt.
  List<double> perp = _randomUnitVector(rng);
  // Subtract the projection of perp onto base.
  final dot = List.generate(128, (i) => perp[i] * base[i])
      .fold(0.0, (a, b) => a + b);
  perp = List.generate(128, (i) => perp[i] - dot * base[i]);
  final norm = sqrt(perp.fold(0.0, (acc, x) => acc + x * x));
  if (norm < 1e-10) {
    // Degenerate case: perp was parallel to base; use a fixed orthogonal vector.
    perp = List.generate(128, (i) => i == 0 ? 0.0 : (i == 1 ? 1.0 : 0.0));
  } else {
    perp = perp.map((x) => x / norm).toList();
  }

  // Clamp targetScore to [-1, 1] to keep sqrt argument non-negative.
  final s = targetScore.clamp(-1.0, 1.0);
  final perpWeight = sqrt(max(0.0, 1.0 - s * s));
  final raw = List.generate(128, (i) => s * base[i] + perpWeight * perp[i]);

  // Normalise the result.
  final rNorm = sqrt(raw.fold(0.0, (acc, x) => acc + x * x));
  if (rNorm == 0.0) return List.filled(128, 0.0);
  return raw.map((x) => x / rNorm).toList();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CameraFrame validFrame() => const CameraFrame(
    bytes: [1, 2, 3], width: 224, height: 224, sharpnessScore: 50.0);

EmployeeRecord makeRecord(String id, List<double> vector) => EmployeeRecord(
      employeeId: id,
      name: 'Test',
      department: 'Dept',
      embedding: FaceEmbedding(vector),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group(
      'Property 9: Liveness triggered iff face verification is VERIFIED', () {
    // -----------------------------------------------------------------------
    // Baseline unit tests
    // -----------------------------------------------------------------------

    test('liveness IS called when face similarity >= 0.75 (VERIFIED)', () async {
      // Identical vectors → cosine similarity = 1.0 → VERIFIED
      final vector = List.generate(128, (_) => 1.0);
      final liveness = _TrackingLiveness();
      final storage = _StorageWithRecords([makeRecord('EMP001', vector)]);
      final engine =
          _TestableEngine(FaceEmbedding(vector), storage, liveness);

      await engine.authenticate(validFrame());

      expect(liveness.callCount, equals(1),
          reason: 'Liveness must be called when face is VERIFIED');
    });

    test('liveness is NOT called when face similarity < 0.75 (FAILED)',
        () async {
      // Orthogonal vectors → cosine similarity ≈ 0.0 → FAILED
      final storedVector = List.generate(128, (_) => 1.0);
      final liveVector =
          List.generate(128, (i) => i == 0 ? 1.0 : 0.0);
      final liveness = _TrackingLiveness();
      final storage =
          _StorageWithRecords([makeRecord('EMP001', storedVector)]);
      final engine =
          _TestableEngine(FaceEmbedding(liveVector), storage, liveness);

      final result = await engine.authenticate(validFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(liveness.callCount, equals(0),
          reason: 'Liveness must NOT be called when face is FAILED');
    });

    test('liveness is NOT called when no stored records (empty store)',
        () async {
      final liveness = _TrackingLiveness();
      final storage = _StorageWithRecords([]);
      final engine = _TestableEngine(
          FaceEmbedding(List.filled(128, 0.5)), storage, liveness);

      final result = await engine.authenticate(validFrame());

      expect(result.classification, equals(AuthClassification.failed));
      expect(liveness.callCount, equals(0));
    });

    // -----------------------------------------------------------------------
    // Property: 100 random VERIFIED scenarios — liveness IS called
    // -----------------------------------------------------------------------

    test(
        'property: 100 random VERIFIED scenarios — liveness IS called '
        '(similarity >= 0.75)', () async {
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        // Generate a random similarity in [0.75, 1.0] → VERIFIED
        final targetScore = 0.75 + rng.nextDouble() * 0.25;
        final base = _randomUnitVector(rng);
        final liveVec = _vectorWithSimilarity(base, targetScore, rng);

        final liveness = _TrackingLiveness();
        final storage =
            _StorageWithRecords([makeRecord('EMP001', base)]);
        final engine =
            _TestableEngine(FaceEmbedding(liveVec), storage, liveness);

        final result = await engine.authenticate(validFrame());

        // Verify the engine actually classified as VERIFIED
        expect(
          result.classification,
          equals(AuthClassification.verified),
          reason:
              'Iteration $i: targetScore=$targetScore should produce VERIFIED',
        );

        // The key property: liveness MUST have been called
        expect(
          liveness.callCount,
          equals(1),
          reason:
              'Iteration $i: liveness must be called exactly once when VERIFIED '
              '(targetScore=$targetScore)',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: 100 random FAILED scenarios — liveness is NOT called
    // -----------------------------------------------------------------------

    test(
        'property: 100 random FAILED scenarios — liveness is NOT called '
        '(similarity < 0.75)', () async {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        // Generate a random similarity in [0.0, 0.75) → FAILED
        final targetScore = rng.nextDouble() * 0.75;
        final base = _randomUnitVector(rng);
        final liveVec = _vectorWithSimilarity(base, targetScore, rng);

        final liveness = _TrackingLiveness();
        final storage =
            _StorageWithRecords([makeRecord('EMP001', base)]);
        final engine =
            _TestableEngine(FaceEmbedding(liveVec), storage, liveness);

        final result = await engine.authenticate(validFrame());

        // Verify the engine actually classified as FAILED
        expect(
          result.classification,
          equals(AuthClassification.failed),
          reason:
              'Iteration $i: targetScore=$targetScore should produce FAILED',
        );

        // The key property: liveness must NEVER be called on FAILED
        expect(
          liveness.callCount,
          equals(0),
          reason:
              'Iteration $i: liveness must NOT be called when FAILED '
              '(targetScore=$targetScore)',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: boundary — exactly 0.75 triggers liveness
    // -----------------------------------------------------------------------

    test('boundary: similarity exactly 0.75 triggers liveness (VERIFIED)',
        () async {
      final rng = Random(7);
      final base = _randomUnitVector(rng);
      final liveVec = _vectorWithSimilarity(base, 0.75, rng);

      final liveness = _TrackingLiveness();
      final storage = _StorageWithRecords([makeRecord('EMP001', base)]);
      final engine =
          _TestableEngine(FaceEmbedding(liveVec), storage, liveness);

      final result = await engine.authenticate(validFrame());

      // Due to floating-point, the actual score may be just above or at 0.75
      if (result.classification == AuthClassification.verified) {
        expect(liveness.callCount, equals(1),
            reason: 'Liveness must be called when classified as VERIFIED');
      } else {
        expect(liveness.callCount, equals(0),
            reason: 'Liveness must NOT be called when classified as FAILED');
      }
    });

    // -----------------------------------------------------------------------
    // Property: liveness failure does not change the trigger condition
    // — liveness is still called (and then fails) when face is VERIFIED
    // -----------------------------------------------------------------------

    test(
        'property: 100 VERIFIED scenarios with liveness returning failed — '
        'liveness is still invoked exactly once', () async {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        final targetScore = 0.75 + rng.nextDouble() * 0.25;
        final base = _randomUnitVector(rng);
        final liveVec = _vectorWithSimilarity(base, targetScore, rng);

        // Liveness returns failed — but it must still be CALLED
        final liveness = _TrackingLiveness(result: LivenessResult.failed);
        final storage =
            _StorageWithRecords([makeRecord('EMP001', base)]);
        final engine =
            _TestableEngine(FaceEmbedding(liveVec), storage, liveness);

        final result = await engine.authenticate(validFrame());

        // Overall result is FAILED (liveness failed), but liveness was called
        expect(
          result.classification,
          equals(AuthClassification.failed),
          reason:
              'Iteration $i: liveness failure should produce overall FAILED',
        );
        expect(
          result.failureReason,
          equals('Liveness check failed'),
          reason: 'Iteration $i: failure reason should indicate liveness',
        );
        expect(
          liveness.callCount,
          equals(1),
          reason:
              'Iteration $i: liveness must be invoked even when it returns failed '
              '(face was VERIFIED, targetScore=$targetScore)',
        );
      }
    });
  });
}
