// Discrete head poses captured during multi-pose enrollment.
enum FacePose { frontal, left, right, up, down }

extension FacePoseX on FacePose {
  /// Upper-case label used in logs and storage (FRONTAL, LEFT, …).
  String get label => name.toUpperCase();

  static FacePose fromLabel(String label) {
    for (final p in FacePose.values) {
      if (p.label == label || p.name == label) return p;
    }
    return FacePose.frontal;
  }
}
