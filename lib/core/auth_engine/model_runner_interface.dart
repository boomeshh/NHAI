import '../camera_frame.dart';

/// Abstract interface for running ML model inference.
///
/// Separating this from [AuthEngineImpl] allows tests to provide a stub
/// implementation without pulling in the native TFLite binaries.
abstract class ModelRunnerInterface {
  /// Runs inference on [frame] and returns a 128-float embedding vector.
  Future<List<double>> runEmbedding(CameraFrame frame);

  /// Releases any native resources held by this runner.
  void dispose();
}
