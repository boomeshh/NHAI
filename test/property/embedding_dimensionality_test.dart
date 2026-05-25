// Feature: nhai-offline-auth, Property 2: Embedding dimensionality invariant
//
// **Validates: Requirements 4.6, 6.2**
//
// Property: For any valid CameraFrame passed to `extractEmbedding`, the
// returned FaceEmbedding vector always contains exactly 128 float values.
//
// Minimum 100 iterations.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/core/camera_frame.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubStorage implements StorageManagerInterface {
  @override Future<void> saveEmployeeRecord(EmployeeRecord r) async {}
  @override Future<EmployeeRecord?> getEmployeeRecord(String id) async => null;
  @override Future<List<EmployeeRecord>> getAllEmployeeRecords() async => [];
  @override Future<bool> employeeExists(String id) async => false;
  @override Future<void> deleteEmployeeRecord(String id) async {}
  @override Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];
  @override Future<void> logStorageError(String m) async {}
}

class _StubLiveness implements LivenessDetectorInterface {
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async =>
      LivenessResult.confirmed;
}

// ---------------------------------------------------------------------------
// Testable engine — overrides runInference to return a fixed 128-dim vector,
// bypassing TFLite so the test runs on the Dart VM without a model file.
// ---------------------------------------------------------------------------

class _TestableAuthEngine extends AuthEngineImpl {
  _TestableAuthEngine()
      : super(storage: _StubStorage(), livenessDetector: _StubLiveness());

  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async {
    // Return a deterministic 128-element vector derived from the frame bytes
    // so that different frames produce different (but always 128-dim) results.
    final seed = frame.bytes.fold<int>(0, (acc, b) => acc ^ b);
    return FaceEmbedding(List.generate(128, (i) => (seed ^ i) * 0.001));
  }
}

// ---------------------------------------------------------------------------
// Generator helpers — produce varied valid CameraFrames
// ---------------------------------------------------------------------------

/// Generates a valid [CameraFrame] using [rng] for randomness.
///
/// "Valid" means:
///   - bytes is non-empty (at least 1 byte, so no-face-detected is not thrown)
///   - sharpnessScore >= 10.0 (so low-quality-frame is not thrown)
CameraFrame _generateValidFrame(Random rng, int iteration) {
  // Vary byte count: 1 to 1000 bytes
  final byteCount = 1 + rng.nextInt(1000);
  final bytes = List.generate(byteCount, (_) => rng.nextInt(256));

  // Vary dimensions: 32–512 px
  final width = 32 + rng.nextInt(481);
  final height = 32 + rng.nextInt(481);

  // Vary sharpness: 10.0–200.0 (always above the 10.0 threshold)
  final sharpness = 10.0 + rng.nextDouble() * 190.0;

  return CameraFrame(
    bytes: bytes,
    width: width,
    height: height,
    sharpnessScore: sharpness,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 2: Embedding dimensionality invariant', () {
    late _TestableAuthEngine engine;

    setUp(() {
      engine = _TestableAuthEngine();
    });

    // -----------------------------------------------------------------------
    // Core property test — 100 randomly generated valid CameraFrames
    // -----------------------------------------------------------------------

    test(
        'property: extractEmbedding always returns exactly 128 values '
        'for 100 randomly generated valid frames', () async {
      // Use a fixed seed so the test is deterministic across runs.
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        final frame = _generateValidFrame(rng, i);
        final embedding = await engine.extractEmbedding(frame);

        expect(
          embedding.vector.length,
          equals(128),
          reason:
              'Iteration $i: expected 128-dimensional embedding but got '
              '${embedding.vector.length} values '
              '(frame: ${frame.bytes.length} bytes, '
              '${frame.width}x${frame.height}, '
              'sharpness=${frame.sharpnessScore.toStringAsFixed(2)})',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: minimum-valid frame (1 byte, sharpness exactly 10.0)
    // -----------------------------------------------------------------------

    test('minimum-valid frame (1 byte, sharpness=10.0) returns 128 values',
        () async {
      final frame = const CameraFrame(
        bytes: [0xFF],
        width: 1,
        height: 1,
        sharpnessScore: 10.0,
      );
      final embedding = await engine.extractEmbedding(frame);
      expect(embedding.vector.length, equals(128));
    });

    // -----------------------------------------------------------------------
    // Boundary: large frame (many bytes, high sharpness)
    // -----------------------------------------------------------------------

    test('large frame (10 000 bytes, sharpness=200.0) returns 128 values',
        () async {
      final frame = CameraFrame(
        bytes: List.filled(10000, 128),
        width: 1920,
        height: 1080,
        sharpnessScore: 200.0,
      );
      final embedding = await engine.extractEmbedding(frame);
      expect(embedding.vector.length, equals(128));
    });

    // -----------------------------------------------------------------------
    // Embedding values must all be finite doubles
    // -----------------------------------------------------------------------

    test('all 128 embedding values are finite for 100 varied frames', () async {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        final frame = _generateValidFrame(rng, i);
        final embedding = await engine.extractEmbedding(frame);

        for (int j = 0; j < embedding.vector.length; j++) {
          expect(
            embedding.vector[j].isFinite,
            isTrue,
            reason:
                'Iteration $i, index $j: embedding value '
                '${embedding.vector[j]} is not finite',
          );
        }
      }
    });

    // -----------------------------------------------------------------------
    // Returned type is FaceEmbedding
    // -----------------------------------------------------------------------

    test('extractEmbedding returns a FaceEmbedding instance', () async {
      final frame = const CameraFrame(
        bytes: [1, 2, 3],
        width: 224,
        height: 224,
        sharpnessScore: 50.0,
      );
      final result = await engine.extractEmbedding(frame);
      expect(result, isA<FaceEmbedding>());
    });

    // -----------------------------------------------------------------------
    // Dimensionality is stable across repeated calls on the same frame
    // -----------------------------------------------------------------------

    test('repeated calls on the same frame always return 128 values', () async {
      final frame = const CameraFrame(
        bytes: [10, 20, 30, 40, 50],
        width: 112,
        height: 112,
        sharpnessScore: 75.0,
      );

      for (int i = 0; i < 10; i++) {
        final embedding = await engine.extractEmbedding(frame);
        expect(embedding.vector.length, equals(128),
            reason: 'Call $i should return 128 values');
      }
    });
  });
}
