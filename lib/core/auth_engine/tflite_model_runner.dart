import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../camera_frame.dart';
import 'embedding_error.dart';
import 'model_runner_interface.dart';

/// Asset path for the MobileFaceNet TFLite model.
const String kMobileFaceNetAssetPath = 'assets/models/mobilefacenet.tflite';

/// Input dimensions expected by MobileFaceNet (112 × 112 RGB).
const int kInputSize = 112;

/// Number of output dimensions produced by MobileFaceNet.
const int kEmbeddingDim = 128;

/// Production [ModelRunnerInterface] backed by a TFLite [Interpreter].
///
/// This class is intentionally kept in its own file so that test code can
/// import [ModelRunnerInterface] (and provide a stub) without ever compiling
/// the `tflite_flutter` native bindings.
class TfliteModelRunner implements ModelRunnerInterface {
  Interpreter? _interpreter;

  /// Loads the MobileFaceNet model from the Flutter asset bundle (lazy, cached).
  Future<Interpreter> _loadInterpreter() async {
    if (_interpreter != null) return _interpreter!;
    try {
      final modelData = await rootBundle.load(kMobileFaceNetAssetPath);
      final bytes = modelData.buffer
          .asUint8List(modelData.offsetInBytes, modelData.lengthInBytes);
      _interpreter = Interpreter.fromBuffer(bytes);
      return _interpreter!;
    } catch (e) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Failed to load MobileFaceNet model from $kMobileFaceNetAssetPath: $e',
      );
    }
  }

  /// Runs inference on [frame] and returns the raw 128-float output vector.
  @override
  Future<List<double>> runEmbedding(CameraFrame frame) async {
    final interpreter = await _loadInterpreter();
    final input = _preprocessFrame(frame);
    final output =
        List.generate(1, (_) => List<double>.filled(kEmbeddingDim, 0.0));

    try {
      interpreter.run(input, output);
    } catch (e) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'TFLite run failed: $e',
      );
    }

    final vector = output[0];
    if (vector.length != kEmbeddingDim) {
      throw EmbeddingError(
        EmbeddingErrorCode.modelInferenceFailed,
        'Model returned ${vector.length} values; expected $kEmbeddingDim',
      );
    }
    return vector;
  }

  /// Pre-processes a [CameraFrame] into the [1, 112, 112, 3] float32 tensor
  /// expected by MobileFaceNet.
  ///
  /// Performs nearest-neighbour resize to [kInputSize × kInputSize] and
  /// normalises pixel values to [-1, 1].
  List<List<List<List<double>>>> _preprocessFrame(CameraFrame frame) {
    final int srcW = frame.width;
    final int srcH = frame.height;
    final bytes = frame.bytes;

    return List.generate(
      1,
      (_) => List.generate(
        kInputSize,
        (y) => List.generate(
          kInputSize,
          (x) {
            final srcX =
                (x * srcW / kInputSize).floor().clamp(0, srcW - 1);
            final srcY =
                (y * srcH / kInputSize).floor().clamp(0, srcH - 1);
            final pixelIndex = (srcY * srcW + srcX) * 3;

            double r = 0.0, g = 0.0, b = 0.0;
            if (pixelIndex + 2 < bytes.length) {
              r = (bytes[pixelIndex] / 127.5) - 1.0;
              g = (bytes[pixelIndex + 1] / 127.5) - 1.0;
              b = (bytes[pixelIndex + 2] / 127.5) - 1.0;
            }
            return [r, g, b];
          },
        ),
      ),
    );
  }

  /// Releases the underlying interpreter.
  @override
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
