import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import '../recognition/embedding_math.dart';
import '../../models/face_embedding.dart';
import '../../models/auth_result.dart';
import '../../models/employee_record.dart';
import '../camera_frame.dart';
import '../liveness_detector/liveness_detector_interface.dart';
import '../storage_manager/storage_manager_interface.dart';
import 'auth_engine_interface.dart';
import 'embedding_error.dart';
import 'model_runner_interface.dart';

/// A [ModelRunnerInterface] that always throws [EmbeddingErrorCode.modelInferenceFailed].
///
/// Used as the default when no runner is injected, so that:
/// - Tests that override [AuthEngineImpl.runInference] never reach this.
/// - Production code must inject a real [TfliteModelRunner] (from
///   `tflite_model_runner.dart`) at the application shell level.
class _UnloadedModelRunner implements ModelRunnerInterface {
  const _UnloadedModelRunner();

  @override
  Future<List<double>> runEmbedding(CameraFrame frame) async {
    throw const EmbeddingError(
      EmbeddingErrorCode.modelInferenceFailed,
      'No ModelRunner injected — pass a TfliteModelRunner in production.',
    );
  }

  @override
  void dispose() {}
}

class AuthEngineImpl implements AuthEngineInterface {
  /// Hardened default verification threshold (Phase 8).
  ///
  /// Raised from the original 0.75 to 0.85. Rationale: for L2-normalised
  /// MobileFaceNet embeddings, genuine same-identity pairs typically score
  /// 0.85–0.97 while different-identity pairs score below ~0.6; 0.75 leaves a
  /// wide impostor band. 0.85 sits in the documented secure range (0.82–0.88),
  /// trading a small increase in false rejects for a large drop in false
  /// accepts. Configurable per deployment via the constructor.
  static const double defaultVerificationThreshold = 0.85;

  final double _verificationThreshold;

  /// The active verification threshold (exposed for tests / diagnostics).
  double get verificationThreshold => _verificationThreshold;

  final StorageManagerInterface _storage;
  final LivenessDetectorInterface _livenessDetector;

  /// Whether the blink-based liveness challenge is run after a face match.
  ///
  /// Defaults to `true` (production-intent, and all existing tests rely on it).
  /// It is disabled at the application shell (see `main.dart`) only while
  /// MediaPipe landmark extraction — which populates [CameraFrame.landmarks]
  /// for [LivenessDetectorImpl] — is not yet wired into the camera pipeline.
  /// When disabled, a verified face match is accepted without the blink check.
  final bool _livenessEnabled;

  /// ML model runner.
  ///
  /// - In production, inject a `TfliteModelRunner` instance (imported from
  ///   `tflite_model_runner.dart`) at the application shell level.
  /// - In tests, either inject a stub [ModelRunnerInterface] or subclass
  ///   [AuthEngineImpl] and override [runInference] directly.
  ///
  /// Defaults to [_UnloadedModelRunner] which throws on use, ensuring that
  /// this file never imports `tflite_flutter` and the VM test runner can
  /// compile it cleanly.
  final ModelRunnerInterface _modelRunner;

  AuthEngineImpl({
    required StorageManagerInterface storage,
    required LivenessDetectorInterface livenessDetector,
    ModelRunnerInterface? modelRunner,
    bool livenessEnabled = true,
    double verificationThreshold = defaultVerificationThreshold,
  })  : _storage = storage,
        _livenessDetector = livenessDetector,
        _modelRunner = modelRunner ?? const _UnloadedModelRunner(),
        _livenessEnabled = livenessEnabled,
        _verificationThreshold = verificationThreshold;

  // ---------------------------------------------------------------------------
  // Embedding extraction
  // ---------------------------------------------------------------------------

  /// Extracts a 128-dimensional embedding from [frame].
  ///
  /// Throws [EmbeddingError] with:
  /// - [EmbeddingErrorCode.noFaceDetected] when the frame has no pixel data.
  /// - [EmbeddingErrorCode.lowQualityFrame] when sharpness is below threshold.
  /// - [EmbeddingErrorCode.modelInferenceFailed] on any TFLite error.
  @override
  Future<FaceEmbedding> extractEmbedding(CameraFrame frame) async {
    if (frame.bytes.isEmpty) {
      throw const EmbeddingError(
          EmbeddingErrorCode.noFaceDetected, 'No face detected in frame');
    }
    // DEBUG: log actual sharpness vs threshold before the quality gate.
    // ignore: avoid_print
    debugPrint(
      '[AuthEngine] extractEmbedding: '
      'sharpnessScore=${frame.sharpnessScore} threshold=10.0 '
      'pass=${frame.sharpnessScore >= 10.0}',
    );
    if (frame.sharpnessScore < 10.0) {
      throw const EmbeddingError(
          EmbeddingErrorCode.lowQualityFrame, 'Frame quality too low');
    }
    try {
      final emb = await runInference(frame);
      final v = emb.vector;
      // Phase 3 — embedding diagnostics + validity check.
      debugPrint('[Embedding] ${EmbeddingMath.diagnostics(v)}');
      if (!EmbeddingMath.isUsable(v)) {
        throw const EmbeddingError(
          EmbeddingErrorCode.modelInferenceFailed,
          'Degenerate embedding (near-zero / NaN / empty)',
        );
      }
      // Phase 7 — store L2-normalized embeddings for stable comparison/averaging.
      return FaceEmbedding(EmbeddingMath.l2Normalize(v));
    } on EmbeddingError {
      rethrow;
    } catch (e) {
      throw EmbeddingError(
          EmbeddingErrorCode.modelInferenceFailed, 'Inference failed: $e');
    }
  }

  /// Runs MobileFaceNet inference on [frame] and returns a 128-dim embedding.
  ///
  /// This method is intentionally non-private so that test subclasses can
  /// override it to inject a known embedding without requiring a real model
  /// file or a physical device.
  ///
  /// Production flow:
  ///   1. Delegate to [_modelRunner] ([TfliteModelRunner]) which lazily loads
  ///      the interpreter from the Flutter asset bundle on first call.
  ///   2. Pre-process the raw bytes into a [112 × 112 × 3] float32 tensor.
  ///   3. Run inference and read the 128-float output vector.
  ///   4. Return a [FaceEmbedding] wrapping that vector.
  Future<FaceEmbedding> runInference(CameraFrame frame) async {
    final vector = await _modelRunner.runEmbedding(frame);
    return FaceEmbedding(vector);
  }

  // ---------------------------------------------------------------------------
  // Cosine similarity and classification
  // ---------------------------------------------------------------------------

  /// Cosine similarity: (a · b) / (||a|| × ||b||)
  double cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length, 'Vectors must have equal length');
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    if (denom == 0.0) return 0.0;
    return dot / denom;
  }

  /// Classifies a similarity score against the threshold.
  AuthClassification classify(double score) =>
      score >= _verificationThreshold
          ? AuthClassification.verified
          : AuthClassification.failed;

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  @override
  Future<AuthResult> authenticate(CameraFrame frame) async {
    final gate = _faceCountGate(frame.faceCount);
    if (gate != null) return gate;

    final FaceEmbedding liveEmbedding;
    try {
      liveEmbedding = await extractEmbedding(frame);
    } on EmbeddingError catch (e) {
      return AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: e.message,
      );
    }
    return _matchAndDecide(liveEmbedding, frame);
  }

  /// Phase 7 — averages embeddings from multiple stable frames for a more
  /// robust live template, then matches. Skips frames that fail extraction.
  @override
  Future<AuthResult> authenticateAveraged(List<CameraFrame> frames) async {
    if (frames.isEmpty) {
      return const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: 'No face detected',
      );
    }
    final gate = _faceCountGate(frames.last.faceCount);
    if (gate != null) return gate;

    final vectors = <List<double>>[];
    for (final f in frames) {
      try {
        final e = await extractEmbedding(f);
        if (EmbeddingMath.isUsable(e.vector)) vectors.add(e.vector);
      } on EmbeddingError {
        // Skip a bad frame; keep the good ones.
      }
    }
    if (vectors.isEmpty) {
      return const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: 'Could not capture a clear face',
      );
    }
    debugPrint('[Recognition] averaged ${vectors.length}/${frames.length} '
        'frame embeddings');
    final averaged = FaceEmbedding(EmbeddingMath.averageNormalized(vectors));
    return _matchAndDecide(averaged, frames.last);
  }

  /// Returns a failed [AuthResult] if the face-count gate fails, else null.
  AuthResult? _faceCountGate(int faceCount) {
    if (faceCount == 0) {
      debugPrint('[Decision] REJECTED reason="No face detected"');
      return const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: 'No face detected',
      );
    }
    if (faceCount > 1) {
      debugPrint('[Decision] REJECTED reason="Multiple faces detected"');
      return const AuthResult(
        classification: AuthClassification.failed,
        trustScore: 0.0,
        failureReason: 'Multiple faces detected',
      );
    }
    return null;
  }

  /// Matches [liveEmbedding] against stored records (skipping corrupt ones),
  /// classifies, runs liveness, and returns the decision.
  Future<AuthResult> _matchAndDecide(
      FaceEmbedding liveEmbedding, CameraFrame frame) async {
    final List<EmployeeRecord> records = await _storage.getAllEmployeeRecords();

    double maxScore = 0.0;
    String? matchedId;
    int skipped = 0;
    for (final record in records) {
      final stored = record.embedding.vector;
      // Phase 4 — skip corrupt / mismatched-length / degenerate stored records.
      if (stored.length != liveEmbedding.vector.length ||
          !EmbeddingMath.isUsable(stored)) {
        skipped++;
        continue;
      }
      final score = cosineSimilarity(liveEmbedding.vector, stored);
      if (score > maxScore) {
        maxScore = score;
        matchedId = record.employeeId;
      }
    }
    if (skipped > 0) {
      debugPrint('[Recognition] skipped $skipped invalid stored record(s)');
    }

    final classification = classify(maxScore);
    // Phase 9 — structured security logs.
    debugPrint('[Recognition] similarity=${maxScore.toStringAsFixed(3)} '
        'threshold=${_verificationThreshold.toStringAsFixed(2)} '
        'match=${matchedId ?? "none"}');
    debugPrint(
      '[Decision] ${classification == AuthClassification.verified ? "VERIFIED" : "REJECTED"} '
      'trustScore=${(maxScore * 100).round()}%',
    );

    if (classification == AuthClassification.failed) {
      return AuthResult(
        classification: AuthClassification.failed,
        trustScore: maxScore,
        failureReason: 'Face not recognized',
      );
    }

    // 5. Liveness check — only triggered on VERIFIED, and only when enabled.
    //
    // The captured [frame] is fed to the detector as a single-element stream
    // (was previously an empty stream, which could never carry a blink and so
    // always timed out). When landmark data is absent and liveness is disabled
    // at the shell level, the verified match is accepted directly.
    if (_livenessEnabled) {
      final livenessResult =
          await _livenessDetector.detectLiveness(Stream.value(frame));

      if (livenessResult == LivenessResult.failed) {
        return AuthResult(
          classification: AuthClassification.failed,
          trustScore: maxScore,
          matchedEmployeeId: matchedId,
          failureReason: 'Liveness check failed',
        );
      }
    }

    return AuthResult(
      classification: AuthClassification.verified,
      trustScore: maxScore,
      matchedEmployeeId: matchedId,
    );
  }

  // ---------------------------------------------------------------------------
  // Resource management
  // ---------------------------------------------------------------------------

  /// Releases the TFLite interpreter. Call when the engine is no longer needed.
  void dispose() {
    _modelRunner.dispose();
  }
}
