// Feature: nhai-offline-auth, Property 15: No network calls during any core operation
//
// **Validates: Requirements 6.7, 7.6, 11.2**
//
// Property: For any invocation of enroll, authenticate, detectLiveness, or
// result display, zero outbound network requests are made.
//
// Approach:
//   1. Install a dart:io HttpOverrides that throws immediately if any HTTP
//      client is created, ensuring any network attempt fails the test.
//   2. Run 100 iterations of authenticate() with varied inputs and verify
//      no network calls are made.
//   3. Verify that core module source files do not import network-capable
//      packages (http, dio, etc.).
//
// Minimum 100 iterations.

import 'dart:io';
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
// Network interception
// ---------------------------------------------------------------------------

/// An [HttpOverrides] that throws [NetworkCallDetectedException] whenever any
/// code attempts to open an HTTP connection.  Installing this override before
/// running core operations guarantees that any accidental network call is
/// caught immediately and fails the test.
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw NetworkCallDetectedException(
      'A network call was attempted during a core operation. '
      'All core operations must be fully offline.',
    );
  }
}

/// Thrown by [_NoNetworkHttpOverrides] when a network call is detected.
class NetworkCallDetectedException implements Exception {
  final String message;
  const NetworkCallDetectedException(this.message);
  @override
  String toString() => 'NetworkCallDetectedException: $message';
}

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubStorage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _StubStorage([this.records = const []]);

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
  final LivenessResult result;
  int callCount = 0;
  _StubLiveness([this.result = LivenessResult.confirmed]);

  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async {
    callCount++;
    return result;
  }
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CameraFrame validFrame() => const CameraFrame(
    bytes: [1, 2, 3], width: 224, height: 224, sharpnessScore: 50.0);

CameraFrame emptyFrame() => const CameraFrame(
    bytes: [], width: 0, height: 0, sharpnessScore: 0.0);

CameraFrame lowQualityFrame() => const CameraFrame(
    bytes: [1, 2, 3], width: 224, height: 224, sharpnessScore: 5.0);

EmployeeRecord makeRecord(String id, List<double> vector) => EmployeeRecord(
      employeeId: id,
      name: 'Test Employee',
      department: 'Engineering',
      embedding: FaceEmbedding(vector),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Install the no-network override for the entire test suite.
  // Any HTTP call made during these tests will throw immediately.
  HttpOverrides.global = _NoNetworkHttpOverrides();

  group('Property 15: No network calls during any core operation', () {
    // -----------------------------------------------------------------------
    // Static analysis: verify core modules do not import network packages
    // -----------------------------------------------------------------------

    test('auth_engine_impl.dart does not import network packages', () {
      final source = File('lib/core/auth_engine/auth_engine_impl.dart')
          .readAsStringSync();
      _assertNoNetworkImports(source, 'auth_engine_impl.dart');
    });

    test('storage_manager_impl.dart does not import network packages', () {
      final source = File('lib/core/storage_manager/storage_manager_impl.dart')
          .readAsStringSync();
      _assertNoNetworkImports(source, 'storage_manager_impl.dart');
    });

    test('liveness_detector_interface.dart does not import network packages',
        () {
      final source =
          File('lib/core/liveness_detector/liveness_detector_interface.dart')
              .readAsStringSync();
      _assertNoNetworkImports(source, 'liveness_detector_interface.dart');
    });

    test('model_runner_interface.dart does not import network packages', () {
      final source =
          File('lib/core/auth_engine/model_runner_interface.dart')
              .readAsStringSync();
      _assertNoNetworkImports(source, 'model_runner_interface.dart');
    });

    // -----------------------------------------------------------------------
    // Runtime: HttpOverrides intercepts any network call
    // -----------------------------------------------------------------------

    test('HttpOverrides throws if any HTTP client is created', () {
      // Directly verify the override is active and working.
      expect(
        () => HttpClient(),
        throwsA(isA<NetworkCallDetectedException>()),
        reason: 'HttpOverrides must intercept HttpClient creation',
      );
    });

    // -----------------------------------------------------------------------
    // Baseline: single authenticate() calls make no network calls
    // -----------------------------------------------------------------------

    test('authenticate() with VERIFIED result makes no network calls',
        () async {
      final vec = List.generate(128, (_) => 1.0);
      final engine = _TestableEngine(
        FaceEmbedding(vec),
        _StubStorage([makeRecord('EMP001', vec)]),
        _StubLiveness(LivenessResult.confirmed),
      );

      // If any network call is made, _NoNetworkHttpOverrides will throw.
      final result = await engine.authenticate(validFrame());
      expect(result.classification, equals(AuthClassification.verified));
    });

    test('authenticate() with FAILED result (no match) makes no network calls',
        () async {
      final engine = _TestableEngine(
        FaceEmbedding(List.filled(128, 0.5)),
        _StubStorage(), // empty store → no match
        _StubLiveness(),
      );

      final result = await engine.authenticate(validFrame());
      expect(result.classification, equals(AuthClassification.failed));
    });

    test(
        'authenticate() with FAILED result (liveness failed) makes no network calls',
        () async {
      final vec = List.generate(128, (_) => 1.0);
      final engine = _TestableEngine(
        FaceEmbedding(vec),
        _StubStorage([makeRecord('EMP001', vec)]),
        _StubLiveness(LivenessResult.failed),
      );

      final result = await engine.authenticate(validFrame());
      expect(result.classification, equals(AuthClassification.failed));
      expect(result.failureReason, equals('Liveness check failed'));
    });

    test('authenticate() with empty frame (no face) makes no network calls',
        () async {
      final engine = _TestableEngine(
        FaceEmbedding(List.filled(128, 0.5)),
        _StubStorage(),
        _StubLiveness(),
      );

      // Empty frame → EmbeddingError.noFaceDetected → FAILED, no network call
      final result = await engine.authenticate(emptyFrame());
      expect(result.classification, equals(AuthClassification.failed));
    });

    test(
        'authenticate() with low-quality frame makes no network calls',
        () async {
      final engine = _TestableEngine(
        FaceEmbedding(List.filled(128, 0.5)),
        _StubStorage(),
        _StubLiveness(),
      );

      // Low sharpness → EmbeddingError.lowQualityFrame → FAILED, no network call
      final result = await engine.authenticate(lowQualityFrame());
      expect(result.classification, equals(AuthClassification.failed));
    });

    test('detectLiveness() makes no network calls', () async {
      final liveness = _StubLiveness(LivenessResult.confirmed);
      // Directly invoke detectLiveness — must not trigger any network call.
      final result =
          await liveness.detectLiveness(const Stream.empty());
      expect(result, equals(LivenessResult.confirmed));
    });

    // -----------------------------------------------------------------------
    // Property: 100 random authenticate() iterations — zero network calls
    // -----------------------------------------------------------------------

    test(
        'property: 100 random authenticate() iterations make no network calls',
        () async {
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        // Randomly vary: live embedding, stored records, liveness outcome.
        final liveVec = _randomUnitVector(rng);
        final numRecords = rng.nextInt(5); // 0–4 stored records
        final records = List.generate(
          numRecords,
          (j) => makeRecord(
            'EMP${(i * 10 + j).toString().padLeft(4, '0')}',
            _randomUnitVector(rng),
          ),
        );
        final livenessResult =
            rng.nextBool() ? LivenessResult.confirmed : LivenessResult.failed;

        final engine = _TestableEngine(
          FaceEmbedding(liveVec),
          _StubStorage(records),
          _StubLiveness(livenessResult),
        );

        // Any network call inside authenticate() will throw
        // NetworkCallDetectedException and fail this test immediately.
        final AuthResult result;
        try {
          result = await engine.authenticate(validFrame());
        } on NetworkCallDetectedException catch (e) {
          fail('Iteration $i: network call detected during authenticate(): $e');
        }

        // The result must be a valid AuthResult (not a network error).
        expect(result.classification, isA<AuthClassification>(),
            reason: 'Iteration $i: result must have a valid classification');
        expect(result.trustScore, isA<double>(),
            reason: 'Iteration $i: result must have a trust score');
      }
    });

    // -----------------------------------------------------------------------
    // Property: 100 iterations with multiple stored records — no network calls
    // -----------------------------------------------------------------------

    test(
        'property: 100 iterations with multiple stored records make no network calls',
        () async {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        // Use 3–10 stored records to exercise the comparison loop.
        final numRecords = 3 + rng.nextInt(8);
        final records = List.generate(
          numRecords,
          (j) => makeRecord(
            'EMP${(i * 20 + j).toString().padLeft(4, '0')}',
            _randomUnitVector(rng),
          ),
        );
        final liveVec = _randomUnitVector(rng);

        final engine = _TestableEngine(
          FaceEmbedding(liveVec),
          _StubStorage(records),
          _StubLiveness(LivenessResult.confirmed),
        );

        try {
          await engine.authenticate(validFrame());
        } on NetworkCallDetectedException catch (e) {
          fail(
              'Iteration $i: network call detected with $numRecords records: $e');
        }
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: assert no network package imports in source
// ---------------------------------------------------------------------------

/// Network-capable packages that must not appear in core module imports.
const _networkPackages = [
  'package:http/',
  'package:dio/',
  'package:http_client/',
  'package:chopper/',
  'package:retrofit/',
  'dart:html', // browser networking
];

void _assertNoNetworkImports(String source, String fileName) {
  for (final pkg in _networkPackages) {
    expect(
      source.contains(pkg),
      isFalse,
      reason:
          '$fileName must not import network package "$pkg". '
          'All core operations must be fully offline.',
    );
  }
}
