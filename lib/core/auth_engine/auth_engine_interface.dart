import '../../models/face_embedding.dart';
import '../../models/auth_result.dart';
import '../camera_frame.dart';

abstract class AuthEngineInterface {
  Future<FaceEmbedding> extractEmbedding(CameraFrame frame);
  Future<AuthResult> authenticate(CameraFrame frame);

  /// Authenticate using several stable frames, averaging their embeddings for a
  /// more robust match (Phase 7). Default delegates to single-frame
  /// [authenticate]; [AuthEngineImpl] overrides with real averaging.
  Future<AuthResult> authenticateAveraged(List<CameraFrame> frames) =>
      authenticate(frames.last);
}
