import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../camera_frame.dart';
import '../face_preprocessor.dart';
import '../recognition/face_aligner.dart';
import 'embedding_error.dart';
import 'model_runner_interface.dart';

/// Asset path for the MobileFaceNet TFLite model.
const String kMobileFaceNetAssetPath = 'assets/models/mobilefacenet.tflite';

/// Default input side length expected by MobileFaceNet (112 × 112 RGB).
const int kInputSize = 112;

/// Preferred embedding dimension. The runner adapts to the model's actual
/// output dimension at load time; this is only a fallback for buffer sizing.
const int kEmbeddingDim = 128;

/// Production [ModelRunnerInterface] backed by a TFLite [Interpreter].
///
/// The runner reads the model's **actual** input and output shapes at load time
/// and adapts to them, so it works with both a standard 128-D / batch-1
/// MobileFaceNet and the batch-2 / 192-D variant currently bundled. The face
/// region (when provided via [CameraFrame.rgbBytes] + [CameraFrame.faceBox]) is
/// cropped and resized to the model's input size before inference.
class TfliteModelRunner implements ModelRunnerInterface {
  Interpreter? _interpreter;

  // Cached model geometry, read from the interpreter at load time.
  int _batch = 1;
  int _inputSize = kInputSize;
  int _channels = 3;
  int _embeddingDim = kEmbeddingDim;

  /// The model's output embedding dimension (valid after the first load).
  int get embeddingDim => _embeddingDim;

  Future<Interpreter> _loadInterpreter() async {
    if (_interpreter != null) return _interpreter!;

    // 1. Asset availability.
    final ByteData modelData;
    try {
      modelData = await rootBundle.load(kMobileFaceNetAssetPath);
    } catch (e) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Model file missing: $kMobileFaceNetAssetPath\n'
        'The MobileFaceNet TFLite model is not bundled. Add the file and '
        'declare it under flutter > assets in pubspec.yaml. (error: $e)',
      );
    }
    final int sizeBytes = modelData.lengthInBytes;
    if (sizeBytes <= 0) {
      throw const EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Model file is empty (0 bytes): $kMobileFaceNetAssetPath',
      );
    }

    // 2. Interpreter init + read real I/O geometry.
    try {
      final bytes = modelData.buffer
          .asUint8List(modelData.offsetInBytes, modelData.lengthInBytes);
      final interpreter = Interpreter.fromBuffer(bytes);

      final inShape = interpreter.getInputTensor(0).shape; // [b, h, w, c]
      final outShape = interpreter.getOutputTensor(0).shape; // [b, dim]
      _batch = inShape.isNotEmpty ? inShape[0] : 1;
      _inputSize = inShape.length >= 3 ? inShape[1] : kInputSize;
      _channels = inShape.length >= 4 ? inShape[3] : 3;
      _embeddingDim = outShape.isNotEmpty ? outShape.last : kEmbeddingDim;

      _interpreter = interpreter;
      // LOG: Model loaded successfully + dimensions.
      debugPrint(
        '[TfliteModelRunner] Model loaded successfully '
        '($sizeBytes bytes) input=$inShape output=$outShape '
        '→ batch=$_batch inputSize=$_inputSize channels=$_channels '
        'embeddingDim=$_embeddingDim',
      );
      return interpreter;
    } catch (e) {
      if (e is EmbeddingError) rethrow;
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Failed to initialize MobileFaceNet interpreter from '
        '$kMobileFaceNetAssetPath ($sizeBytes bytes): $e',
      );
    }
  }

  @override
  Future<List<double>> runEmbedding(CameraFrame frame) async {
    final interpreter = await _loadInterpreter();

    // Build one normalized [inputSize][inputSize][3] tensor from the face crop.
    final crop = _buildCrop(frame);

    // Replicate the crop across every batch slot the model requires (the bundled
    // model has a fixed batch of 2); the embedding is read from slot 0.
    final input = List.generate(_batch, (_) => crop);
    final output =
        List.generate(_batch, (_) => List<double>.filled(_embeddingDim, 0.0));

    try {
      interpreter.run(input, output);
    } catch (e) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'TFLite run failed (input batch=$_batch size=$_inputSize): $e',
      );
    }

    final vector = output[0];
    if (vector.length != _embeddingDim) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Model returned ${vector.length} values; expected $_embeddingDim',
      );
    }
    // LOG: Embedding generated + length.
    debugPrint(
      '[TfliteModelRunner] Embedding generated: length=${vector.length}',
    );
    return vector;
  }

  /// Produces the normalized `[inputSize][inputSize][3]` input tensor.
  ///
  /// Preferred path: similarity-transform **face alignment** from the eye
  /// landmarks (pose/scale/translation invariant). Falls back to the square
  /// crop when eye landmarks are unavailable or degenerate, then to whole-frame
  /// RGB when no detection data is attached at all.
  List<List<List<double>>> _buildCrop(CameraFrame frame) {
    final List<int> rgb = frame.rgbBytes ?? frame.bytes;

    // 1. Aligned crop (eye landmarks present).
    final leftEye = frame.leftEye;
    final rightEye = frame.rightEye;
    if (frame.rgbBytes != null && leftEye != null && rightEye != null) {
      final aligned = FaceAligner.align(
        rgb, frame.width, frame.height, leftEye, rightEye, _inputSize);
      if (aligned != null) {
        debugPrint('[Alignment] angle=${aligned.angleDegrees.toStringAsFixed(2)}');
        debugPrint('[Alignment] eyeDistance=${aligned.eyeDistance.toStringAsFixed(2)}');
        debugPrint('[Alignment] success=true');
        return aligned.tensor;
      }
    }

    // 2. Square-crop fallback (Phase 8 — preserve the existing pipeline).
    debugPrint('[Alignment] success=false (fallback: square crop)');
    final FaceBoxData box = frame.faceBox ??
        FaceBoxData(left: 0, top: 0, width: frame.width, height: frame.height);
    return FacePreprocessor.cropResizeNormalize(
      rgb,
      frame.width,
      frame.height,
      box,
      _inputSize,
    );
  }

  @override
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
