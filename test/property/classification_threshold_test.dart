// Feature: nhai-offline-auth, Property 1: Classification threshold is a total function
//
// **Validates: Requirements 6.4, 6.5**
//
// Property: For any pair of face embeddings (live and stored), the cosine
// similarity score determines the classification deterministically:
//   - a score >= 0.75 always produces VERIFIED
//   - a score < 0.75 always produces FAILED
//   - no other outcomes are possible
//
// Minimum 100 iterations.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/core/camera_frame.dart';

// ---------------------------------------------------------------------------
// Stubs — no network, no I/O
// ---------------------------------------------------------------------------

class _StubStorage implements StorageManagerInterface {
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async {}
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => null;
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => [];
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

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Generates a random unit-normalised 128-dimensional vector.
///
/// Normalising ensures cosine similarity is well-defined and spans [-1, 1].
List<double> _randomUnitVector(Random rng) {
  final v = List.generate(128, (_) => rng.nextDouble() * 2.0 - 1.0);
  final norm = sqrt(v.fold(0.0, (acc, x) => acc + x * x));
  if (norm == 0.0) return List.filled(128, 1.0 / sqrt(128));
  return v.map((x) => x / norm).toList();
}

/// Generates a random 128-dimensional vector with components in [-1, 1].
/// Not normalised — tests that cosineSimilarity handles arbitrary magnitudes.
List<double> _randomVector(Random rng) {
  return List.generate(128, (_) => rng.nextDouble() * 2.0 - 1.0);
}

/// Constructs a pair of vectors whose cosine similarity is approximately
/// [targetScore] by interpolating between a base vector and its negation.
///
/// similarity(a, lerp(a, -a, t)) ≈ 1 - 2t  for unit vectors.
/// So t = (1 - targetScore) / 2.
List<double> _vectorWithSimilarity(List<double> base, double targetScore) {
  final t = (1.0 - targetScore) / 2.0;
  final raw = List.generate(128, (i) => base[i] * (1.0 - t) + (-base[i]) * t);
  // Normalise so the cosine similarity formula is exact.
  final norm = sqrt(raw.fold(0.0, (acc, x) => acc + x * x));
  if (norm == 0.0) return List.filled(128, 0.0);
  return raw.map((x) => x / norm).toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 1: Classification threshold is a total function', () {
    late AuthEngineImpl engine;

    setUp(() {
      // This property suite validates the threshold MECHANISM at 0.75 (the
      // value it was written against). Production default is now 0.85.
      engine = AuthEngineImpl(
        storage: _StubStorage(),
        livenessDetector: _StubLiveness(),
        verificationThreshold: 0.75,
      );
    });

    // -----------------------------------------------------------------------
    // Core property: classify() is a total function over all double scores
    // -----------------------------------------------------------------------

    test(
        'property: 100 random scores always produce exactly VERIFIED or FAILED '
        'with no other outcomes', () {
      final rng = Random(42);
      final allClassifications = AuthClassification.values.toSet();

      for (int i = 0; i < 100; i++) {
        // Generate scores uniformly across [0.0, 1.0]
        final score = rng.nextDouble();
        final result = engine.classify(score);

        // Must be one of the two valid classifications — no other outcome
        expect(
          allClassifications.contains(result),
          isTrue,
          reason: 'Iteration $i: classify($score) returned an unexpected value',
        );

        // Must follow the threshold rule deterministically
        if (score >= 0.75) {
          expect(
            result,
            equals(AuthClassification.verified),
            reason: 'Iteration $i: score $score >= 0.75 must produce VERIFIED',
          );
        } else {
          expect(
            result,
            equals(AuthClassification.failed),
            reason: 'Iteration $i: score $score < 0.75 must produce FAILED',
          );
        }
      }
    });

    // -----------------------------------------------------------------------
    // Property: scores >= 0.75 always produce VERIFIED (100 iterations)
    // -----------------------------------------------------------------------

    test('property: 100 random scores >= 0.75 always produce VERIFIED', () {
      final rng = Random(7);

      for (int i = 0; i < 100; i++) {
        // Generate score in [0.75, 1.0]
        final score = 0.75 + rng.nextDouble() * 0.25;
        final result = engine.classify(score);

        expect(
          result,
          equals(AuthClassification.verified),
          reason: 'Iteration $i: score $score (>= 0.75) must produce VERIFIED '
              'but got $result',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: scores < 0.75 always produce FAILED (100 iterations)
    // -----------------------------------------------------------------------

    test('property: 100 random scores < 0.75 always produce FAILED', () {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        // Generate score in [0.0, 0.75)
        final score = rng.nextDouble() * 0.75;
        final result = engine.classify(score);

        expect(
          result,
          equals(AuthClassification.failed),
          reason: 'Iteration $i: score $score (< 0.75) must produce FAILED '
              'but got $result',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: classify() is deterministic — same score always same result
    // -----------------------------------------------------------------------

    test(
        'property: classify() is deterministic — same score always returns '
        'the same classification across 100 repeated calls', () {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        final score = rng.nextDouble();
        final first = engine.classify(score);
        final second = engine.classify(score);
        final third = engine.classify(score);

        expect(first, equals(second),
            reason: 'Iteration $i: classify($score) was not deterministic '
                '(first=$first, second=$second)');
        expect(second, equals(third),
            reason: 'Iteration $i: classify($score) was not deterministic '
                '(second=$second, third=$third)');
      }
    });

    // -----------------------------------------------------------------------
    // Property: cosineSimilarity + classify pipeline is a total function
    // for 100 random embedding pairs
    // -----------------------------------------------------------------------

    test(
        'property: cosineSimilarity + classify pipeline always produces '
        'VERIFIED or FAILED for 100 random embedding pairs', () {
      final rng = Random(17);

      for (int i = 0; i < 100; i++) {
        final a = _randomVector(rng);
        final b = _randomVector(rng);

        final score = engine.cosineSimilarity(a, b);
        final result = engine.classify(score);

        // Result must be one of the two valid classifications
        expect(
          result == AuthClassification.verified ||
              result == AuthClassification.failed,
          isTrue,
          reason: 'Iteration $i: pipeline produced an unexpected result',
        );

        // Threshold rule must hold
        if (score >= 0.75) {
          expect(result, equals(AuthClassification.verified),
              reason:
                  'Iteration $i: cosine=$score >= 0.75 must produce VERIFIED');
        } else {
          expect(result, equals(AuthClassification.failed),
              reason: 'Iteration $i: cosine=$score < 0.75 must produce FAILED');
        }
      }
    });

    // -----------------------------------------------------------------------
    // Property: engineered embedding pairs with known similarity scores
    // produce the correct classification (100 iterations)
    // -----------------------------------------------------------------------

    test(
        'property: engineered embedding pairs with known similarity scores '
        'always produce the correct classification (100 iterations)', () {
      final rng = Random(31);

      for (int i = 0; i < 100; i++) {
        // Pick a target score uniformly in [0.0, 1.0]
        final targetScore = rng.nextDouble();
        final base = _randomUnitVector(rng);
        final other = _vectorWithSimilarity(base, targetScore);

        final actualScore = engine.cosineSimilarity(base, other);
        final result = engine.classify(actualScore);

        // The actual score may differ slightly from targetScore due to
        // floating-point arithmetic, so we classify based on actualScore.
        if (actualScore >= 0.75) {
          expect(result, equals(AuthClassification.verified),
              reason:
                  'Iteration $i: actualScore=$actualScore >= 0.75 must be VERIFIED');
        } else {
          expect(result, equals(AuthClassification.failed),
              reason:
                  'Iteration $i: actualScore=$actualScore < 0.75 must be FAILED');
        }
      }
    });

    // -----------------------------------------------------------------------
    // Boundary conditions
    // -----------------------------------------------------------------------

    test('exactly 0.75 produces VERIFIED (lower boundary)', () {
      expect(engine.classify(0.75), equals(AuthClassification.verified));
    });

    test('0.7499999999 produces FAILED (just below boundary)', () {
      expect(engine.classify(0.7499999999), equals(AuthClassification.failed));
    });

    test('0.7500000001 produces VERIFIED (just above boundary)', () {
      expect(
          engine.classify(0.7500000001), equals(AuthClassification.verified));
    });

    test('0.0 produces FAILED (minimum score)', () {
      expect(engine.classify(0.0), equals(AuthClassification.failed));
    });

    test('1.0 produces VERIFIED (maximum score)', () {
      expect(engine.classify(1.0), equals(AuthClassification.verified));
    });

    test('negative score produces FAILED', () {
      expect(engine.classify(-0.5), equals(AuthClassification.failed));
    });

    // -----------------------------------------------------------------------
    // Boundary: identical vectors have cosine similarity = 1.0 → VERIFIED
    // -----------------------------------------------------------------------

    test('identical vectors have cosine similarity 1.0 and produce VERIFIED',
        () {
      final vec = List.generate(128, (i) => (i + 1) * 0.01);
      final score = engine.cosineSimilarity(vec, vec);
      expect(score, closeTo(1.0, 1e-9));
      expect(engine.classify(score), equals(AuthClassification.verified));
    });

    // -----------------------------------------------------------------------
    // Boundary: zero vector produces cosine similarity 0.0 → FAILED
    // -----------------------------------------------------------------------

    test('zero vector produces cosine similarity 0.0 and FAILED', () {
      final zero = List.filled(128, 0.0);
      final other = List.generate(128, (i) => i * 0.01);
      final score = engine.cosineSimilarity(zero, other);
      expect(score, equals(0.0));
      expect(engine.classify(score), equals(AuthClassification.failed));
    });

    // -----------------------------------------------------------------------
    // Exhaustive sweep: 200 evenly-spaced scores across [0.0, 1.0]
    // -----------------------------------------------------------------------

    test(
        'exhaustive sweep: 200 evenly-spaced scores across [0.0, 1.0] '
        'all classified correctly', () {
      for (int i = 0; i <= 200; i++) {
        final score = i / 200.0;
        final result = engine.classify(score);

        if (score >= 0.75) {
          expect(result, equals(AuthClassification.verified),
              reason: 'score=$score should be VERIFIED');
        } else {
          expect(result, equals(AuthClassification.failed),
              reason: 'score=$score should be FAILED');
        }
      }
    });
  });
}
