class CameraFrame {
  final List<int> bytes;
  final int width;
  final int height;
  final double sharpnessScore;

  /// Optional eye landmark coordinates for liveness detection.
  ///
  /// When populated (e.g., by a MediaPipe Face Mesh platform channel), this
  /// field holds exactly 6 two-element `[x, y]` lists corresponding to the
  /// six eye landmark points (p1–p6) used to compute the Eye Aspect Ratio.
  ///
  /// Frames without landmark data (e.g., no face detected) leave this `null`.
  final List<List<double>>? landmarks;

  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sharpnessScore,
    this.landmarks,
  });
}
