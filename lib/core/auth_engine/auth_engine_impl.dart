import 'dart:math' as math;
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
  static const double _verificationThreshold = 0.75;

  final StorageManagerInterface _storage;
  final LivenessDetectorInterface _livenessDetector;

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
  })  : _storage = storage,
        _livenessDetector = livenessDetector,
        _modelRunner = modelRunner ?? const _UnloadedModelRunner();

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
    if (frame.sharpnessScore < 10.0) {
      throw const EmbeddingError(
          EmbeddingErrorCode.lowQualityFrame, 'Frame quality too low');
    }
    try {
      return await runInference(frame);
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
    // 1. Extract live embedding.
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

    // 2. Fetch all stored records — no network calls.
    final List<EmployeeRecord> records = await _storage.getAllEmployeeRecords();

    // 3. Compute cosine similarity against each stored embedding.
    double maxScore = 0.0;
    String? matchedId;
    for (final record in records) {
      final score =
          cosineSimilarity(liveEmbedding.vector, record.embedding.vector);
      if (score > maxScore) {
        maxScore = score;
        matchedId = record.employeeId;
      }
    }

    // 4. Classify.
    final classification = classify(maxScore);

    if (classification == AuthClassification.failed) {
      return AuthResult(
        classification: AuthClassification.failed,
        trustScore: maxScore,
        failureReason: 'Face not recognized',
      );
    }

    // 5. Liveness check — only triggered on VERIFIED.
    final livenessResult =
        await _livenessDetector.detectLiveness(const Stream.empty());

    if (livenessResult == LivenessResult.failed) {
      return AuthResult(
        classification: AuthClassification.failed,
        trustScore: maxScore,
        matchedEmployeeId: matchedId,
        failureReason: 'Liveness check failed',
      );
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
