import '../../models/face_pose.dart';

// Classifies head pose from ML Kit Euler angles and gates multi-pose
// enrollment. yaw = headEulerAngleY (left/right), pitch = headEulerAngleX
// (up/down). Pure and deterministic.
//
// Sign convention (verify once on-device and flip if mirrored): yaw < 0 → the
// head is turned LEFT, yaw > 0 → RIGHT; pitch > 0 → UP, pitch < 0 → DOWN.
class PoseClassifier {
  /// Frontal tolerance — both angles within this (degrees).
  static const double frontalTolerance = 10.0;

  /// Yaw magnitude at/above which a turn (left/right) is accepted.
  static const double yawTurn = 15.0;

  /// Pitch magnitude at/above which a tilt (up/down) is accepted.
  static const double pitchTurn = 12.0;

  /// Cross-axis slack: a left/right pose may have some pitch and vice-versa.
  static const double crossAxisSlack = 18.0;

  /// Guided enrollment order.
  static const List<FacePose> enrollmentSequence = [
    FacePose.frontal,
    FacePose.left,
    FacePose.right,
    FacePose.up,
    FacePose.down,
  ];

  /// True if (yaw, pitch) satisfies the target [pose]'s window.
  static bool matches(FacePose pose, double yaw, double pitch) {
    switch (pose) {
      case FacePose.frontal:
        return yaw.abs() < frontalTolerance && pitch.abs() < frontalTolerance;
      case FacePose.left:
        return yaw <= -yawTurn && pitch.abs() <= crossAxisSlack;
      case FacePose.right:
        return yaw >= yawTurn && pitch.abs() <= crossAxisSlack;
      case FacePose.up:
        return pitch >= pitchTurn && yaw.abs() <= crossAxisSlack;
      case FacePose.down:
        return pitch <= -pitchTurn && yaw.abs() <= crossAxisSlack;
    }
  }

  /// Best-matching pose for the given angles, or null if none.
  static FacePose? classify(double yaw, double pitch) {
    for (final p in enrollmentSequence) {
      if (matches(p, yaw, pitch)) return p;
    }
    return null;
  }
}
