import '../../models/face_embedding.dart';
import '../../models/auth_result.dart';
import '../camera_frame.dart';

abstract class AuthEngineInterface {
  Future<FaceEmbedding> extractEmbedding(CameraFrame frame);
  Future<AuthResult> authenticate(CameraFrame frame);
}
