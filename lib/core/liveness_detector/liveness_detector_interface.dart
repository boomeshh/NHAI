import '../camera_frame.dart';

enum LivenessResult { confirmed, failed }

abstract class LivenessDetectorInterface {
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> frameStream);
}
