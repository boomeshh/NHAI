/// Pure-Dart landmark presence audit + alignment-fallback determination.
///
/// The recognition aligner prefers a 5-point affine alignment (both eyes, nose
/// base, both mouth corners). When landmarks are missing it must fall back to
/// 2-point (eyes only) or, in the worst case, a plain square crop. This module
/// reports exactly which landmarks are present and which alignment path the
/// aligner would take — and why — without performing any alignment itself or
/// touching the recognition engine.
library;

/// Which alignment path is available given the present landmarks.
enum AlignmentPath {
  /// All five landmarks present → full 5-point affine alignment.
  fivePoint,

  /// Both eyes present but nose/mouth missing → 2-point eye alignment.
  twoPoint,

  /// Eyes missing → no landmark alignment; plain square crop.
  square,
}

/// Result of auditing one detected face's landmarks.
class LandmarkAuditResult {
  final bool hasLeftEye;
  final bool hasRightEye;
  final bool hasNose;
  final bool hasMouthLeft;
  final bool hasMouthRight;

  /// Names of the landmarks that were missing (empty when all present).
  final List<String> missing;

  /// The alignment path the aligner will use given these landmarks.
  final AlignmentPath path;

  const LandmarkAuditResult({
    required this.hasLeftEye,
    required this.hasRightEye,
    required this.hasNose,
    required this.hasMouthLeft,
    required this.hasMouthRight,
    required this.missing,
    required this.path,
  });

  /// True when all five alignment landmarks are present.
  bool get hasFivePoint => path == AlignmentPath.fivePoint;

  /// True when the aligner must fall back from the preferred 5-point path.
  bool get isFallback => path != AlignmentPath.fivePoint;

  /// Human-readable reason for the fallback (empty when no fallback).
  String get fallbackReason {
    switch (path) {
      case AlignmentPath.fivePoint:
        return '';
      case AlignmentPath.twoPoint:
        return 'missing ${missing.join(",")} → eyes-only 2-point alignment';
      case AlignmentPath.square:
        return 'missing ${missing.join(",")} → no eyes, square-crop fallback';
    }
  }
}

/// Determines landmark presence and the resulting alignment path. Pure.
class LandmarkAuditor {
  const LandmarkAuditor();

  LandmarkAuditResult audit({
    required bool hasLeftEye,
    required bool hasRightEye,
    required bool hasNose,
    required bool hasMouthLeft,
    required bool hasMouthRight,
  }) {
    final missing = <String>[
      if (!hasLeftEye) 'leftEye',
      if (!hasRightEye) 'rightEye',
      if (!hasNose) 'nose',
      if (!hasMouthLeft) 'mouthLeft',
      if (!hasMouthRight) 'mouthRight',
    ];

    final bool eyes = hasLeftEye && hasRightEye;
    final bool all =
        eyes && hasNose && hasMouthLeft && hasMouthRight;

    final AlignmentPath path = all
        ? AlignmentPath.fivePoint
        : eyes
            ? AlignmentPath.twoPoint
            : AlignmentPath.square;

    return LandmarkAuditResult(
      hasLeftEye: hasLeftEye,
      hasRightEye: hasRightEye,
      hasNose: hasNose,
      hasMouthLeft: hasMouthLeft,
      hasMouthRight: hasMouthRight,
      missing: missing,
      path: path,
    );
  }
}
