import '../camera_frame.dart';

/// Axis-aligned face bounding box in source-image pixel coordinates.
class FaceBox {
  final int left;
  final int top;
  final int width;
  final int height;

  const FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'FaceBox($left,$top,${width}x$height)';
}

/// A single detected face: bounding box, optional eye landmarks, and the
/// quality signals used by the biometric validation gates (eye-open
/// probabilities, head Euler angles, presence of critical landmarks).
class DetectedFace {
  final FaceBox box;
  final List<List<double>>? eyeLandmarks;

  /// ML Kit eye-open probabilities in [0, 1] (null if classification disabled).
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  /// Head Euler angles in degrees (yaw = Y, roll = Z).
  final double? headEulerAngleY;
  final double? headEulerAngleZ;

  /// Presence of the five critical landmarks for occlusion detection.
  final bool hasLeftEye;
  final bool hasRightEye;
  final bool hasNoseBase;
  final bool hasLeftCheek;
  final bool hasRightCheek;

  /// Left/right eye centre positions `[x, y]` in image pixels, for alignment.
  final List<double>? leftEyePosition;
  final List<double>? rightEyePosition;

  const DetectedFace({
    required this.box,
    this.eyeLandmarks,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.hasLeftEye = false,
    this.hasRightEye = false,
    this.hasNoseBase = false,
    this.hasLeftCheek = false,
    this.hasRightCheek = false,
    this.leftEyePosition,
    this.rightEyePosition,
  });
}

/// Abstract face detector.
///
/// Kept behind an interface so the real (ML Kit) detector — which requires a
/// physical Android/iOS platform channel — is never instantiated in unit/widget
/// tests. Tests that need detection inject a fake implementation.
abstract class FaceDetectorInterface {
  /// Detects all faces in [frame]. Implementations read the raw camera bytes
  /// carried by the frame ([CameraFrame.nv21Bytes] + [CameraFrame.rotationDegrees]).
  Future<List<DetectedFace>> detect(CameraFrame frame);

  /// Releases native resources.
  void dispose();
}
