/// Pure-Dart face-quality analysis for the NHAI detection pipeline.
///
/// Converts raw per-frame signals (brightness, sharpness, face geometry, head
/// pose, eye visibility) into a single 0–100 [FaceQualityScore] plus a hard
/// accept/reject decision with an explicit [QualityRejection] reason.
///
/// This layer is intentionally free of any I/O, native binding, or dependency
/// on the recognition engine. It only *measures* the frame — it never touches
/// MobileFaceNet, the gallery matcher, or the verification threshold.
library;

import 'dart:math' as math;

/// Per-metric numeric inputs for one frame.
///
/// All fields are raw measurements; the analyzer is responsible for scoring and
/// gating. [brightness] is mean luma in 0–255. [sharpness] is a Laplacian
/// variance (unbounded, ≥0). Pose angles are degrees.
class QualityInput {
  final bool faceDetected;

  /// Mean luminance of the frame (or face region), 0–255.
  final double brightness;

  /// Laplacian-variance sharpness (≥0; higher = sharper).
  final double sharpness;

  /// Face bounding box, in source-image pixels.
  final int boxWidth;
  final int boxHeight;
  final int boxLeft;
  final int boxTop;

  /// Source frame dimensions, in pixels.
  final int frameWidth;
  final int frameHeight;

  /// Head Euler angles (degrees): yaw = left/right, pitch = up/down, roll = tilt.
  final double yaw;
  final double pitch;
  final double roll;

  /// ML Kit eye-open probabilities in [0, 1].
  final double leftEyeOpen;
  final double rightEyeOpen;

  /// Whether the two eye landmarks were resolved (eye visibility).
  final bool hasLeftEye;
  final bool hasRightEye;

  const QualityInput({
    required this.faceDetected,
    required this.brightness,
    required this.sharpness,
    required this.boxWidth,
    required this.boxHeight,
    required this.boxLeft,
    required this.boxTop,
    required this.frameWidth,
    required this.frameHeight,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.hasLeftEye,
    required this.hasRightEye,
  });
}

/// Why a frame was rejected (or [none] if accepted).
enum QualityRejection {
  none,
  noFace,
  tooDark,
  tooBright,
  tooBlurry,
  faceTooSmall,
  faceOffCenter,
  extremePose,
  eyesNotVisible,
}

extension QualityRejectionMessage on QualityRejection {
  /// Operator-facing message (never technical jargon).
  String get message {
    switch (this) {
      case QualityRejection.none:
        return 'Hold still…';
      case QualityRejection.noFace:
        return 'Position your face within the guide';
      case QualityRejection.tooDark:
        return 'Move to a brighter area';
      case QualityRejection.tooBright:
        return 'Reduce glare / strong backlight';
      case QualityRejection.tooBlurry:
        return 'Hold the device steady';
      case QualityRejection.faceTooSmall:
        return 'Move closer to the camera';
      case QualityRejection.faceOffCenter:
        return 'Center your face in the guide';
      case QualityRejection.extremePose:
        return 'Look directly at the camera';
      case QualityRejection.eyesNotVisible:
        return 'Make sure both eyes are visible';
    }
  }
}

/// Tunable accept/reject thresholds and scoring band-edges.
///
/// Exposed as an injectable value object so tests can pin behaviour and the
/// device-validation screen can display the active limits. Defaults are chosen
/// for a front-facing attendance kiosk at arm's length.
class QualityThresholds {
  // Brightness (mean luma, 0–255).
  final double darkRejectBelow; // hard reject
  final double brightRejectAbove; // hard reject
  final double brightnessIdealLow; // full-score band
  final double brightnessIdealHigh;

  // Sharpness (Laplacian variance).
  final double sharpnessRejectBelow; // hard reject (blurry)
  final double sharpnessGood; // value that scores 100

  // Face coverage = boxArea / frameArea.
  final double coverageRejectBelow; // hard reject (too small)
  final double coverageIdealLow; // full-score band
  final double coverageIdealHigh;

  // Centering: normalized distance of box centre from frame centre.
  final double centerOffsetRejectAbove; // hard reject (off guide)

  // Pose: max(|yaw|,|pitch|,|roll|) in degrees.
  final double extremePoseRejectAbove; // hard reject
  final double poseGoodBelow; // value at/below which pose scores 100

  // Eye-open probability contributing to the eye sub-score.
  final double eyeOpenGood;

  const QualityThresholds({
    this.darkRejectBelow = 50,
    this.brightRejectAbove = 225,
    this.brightnessIdealLow = 100,
    this.brightnessIdealHigh = 190,
    this.sharpnessRejectBelow = 10,
    this.sharpnessGood = 80,
    this.coverageRejectBelow = 0.05,
    this.coverageIdealLow = 0.10,
    this.coverageIdealHigh = 0.60,
    this.centerOffsetRejectAbove = 0.28,
    this.extremePoseRejectAbove = 25,
    this.poseGoodBelow = 8,
    this.eyeOpenGood = 0.70,
  });

  static const QualityThresholds standard = QualityThresholds();

  /// Preset for guided multi-pose enrollment, where the subject *intentionally*
  /// turns off-frontal (left/right/up/down). The pose hard-gate is widened so
  /// deliberate turns are not rejected, while brightness / sharpness / size /
  /// centering / eye-visibility gates stay intact to keep template quality high.
  static const QualityThresholds enrollment =
      QualityThresholds(extremePoseRejectAbove: 45, poseGoodBelow: 12);
}

/// The result of analysing one frame: an overall 0–100 score, the per-metric
/// breakdown, and the hard accept/reject decision with its reason.
class FaceQualityScore {
  /// Overall quality, 0 (unusable) – 100 (ideal).
  final double score;

  /// Hard accept/reject (independent of [score] — gates are pass/fail).
  final bool accepted;
  final QualityRejection rejection;

  // Derived geometry (exposed for the validation screen / logs).
  final double faceCoverage; // boxArea / frameArea, 0–1
  final double centerOffset; // normalized distance from centre, 0–~0.7
  final bool faceCentered;

  // Per-metric sub-scores (each 0–100).
  final double brightnessScore;
  final double sharpnessScore;
  final double sizeScore;
  final double centeringScore;
  final double poseScore;
  final double eyeScore;

  const FaceQualityScore({
    required this.score,
    required this.accepted,
    required this.rejection,
    required this.faceCoverage,
    required this.centerOffset,
    required this.faceCentered,
    required this.brightnessScore,
    required this.sharpnessScore,
    required this.sizeScore,
    required this.centeringScore,
    required this.poseScore,
    required this.eyeScore,
  });

  /// Reason text suitable for the operator (empty when accepted).
  String get reasonMessage => accepted ? '' : rejection.message;
}

/// Computes a [FaceQualityScore] from a [QualityInput].
///
/// Scoring weights (sum 100%): sharpness 25, pose 20, brightness 15, size 15,
/// eyes 15, centering 10. Hard gates are evaluated independently of the score
/// so a frame can score moderately yet still be rejected for a single fatal
/// defect (e.g. blur), which is the behaviour an attendance kiosk needs.
class FaceQualityAnalyzer {
  final QualityThresholds t;

  const FaceQualityAnalyzer({this.t = QualityThresholds.standard});

  FaceQualityScore analyze(QualityInput i) {
    // ── Geometry ─────────────────────────────────────────────────────────────
    final int frameArea =
        (i.frameWidth * i.frameHeight).clamp(1, 1 << 30).toInt();
    final double coverage = (i.boxWidth * i.boxHeight) / frameArea;
    final double cx = i.boxLeft + i.boxWidth / 2.0;
    final double cy = i.boxTop + i.boxHeight / 2.0;
    final double fcx = i.frameWidth / 2.0;
    final double fcy = i.frameHeight / 2.0;
    // Normalize centre offset by the frame's half-diagonal so it is resolution
    // independent (0 = dead centre, ~1 = corner).
    final double halfDiag =
        math.sqrt(fcx * fcx + fcy * fcy).clamp(1, double.infinity);
    final double centerOffset =
        math.sqrt((cx - fcx) * (cx - fcx) + (cy - fcy) * (cy - fcy)) / halfDiag;

    // ── Sub-scores ───────────────────────────────────────────────────────────
    final double brightnessScore = _bandScore(
      i.brightness,
      hardLow: t.darkRejectBelow,
      idealLow: t.brightnessIdealLow,
      idealHigh: t.brightnessIdealHigh,
      hardHigh: t.brightRejectAbove,
    );
    final double sharpnessScore =
        (i.sharpness / t.sharpnessGood * 100).clamp(0, 100).toDouble();
    final double sizeScore = _bandScore(
      coverage,
      hardLow: 0,
      idealLow: t.coverageIdealLow,
      idealHigh: t.coverageIdealHigh,
      hardHigh: 1.0,
    );
    final double centeringScore =
        (100 - (centerOffset / t.centerOffsetRejectAbove) * 100)
            .clamp(0, 100)
            .toDouble();
    final double maxAngle =
        math.max(i.yaw.abs(), math.max(i.pitch.abs(), i.roll.abs()));
    final double poseScore = maxAngle <= t.poseGoodBelow
        ? 100
        : (100 -
                (maxAngle - t.poseGoodBelow) /
                    (t.extremePoseRejectAbove - t.poseGoodBelow) *
                    100)
            .clamp(0, 100)
            .toDouble();
    final double minEye = math.min(i.leftEyeOpen, i.rightEyeOpen);
    final bool eyesVisible = i.hasLeftEye && i.hasRightEye;
    final double eyeScore = !eyesVisible
        ? 0
        : (minEye / t.eyeOpenGood * 100).clamp(0, 100).toDouble();

    final double overall = i.faceDetected
        ? (sharpnessScore * 0.25 +
                poseScore * 0.20 +
                brightnessScore * 0.15 +
                sizeScore * 0.15 +
                eyeScore * 0.15 +
                centeringScore * 0.10)
            .clamp(0, 100)
            .toDouble()
        : 0;

    // ── Hard gates (ordered; first failure wins) ──────────────────────────────
    final QualityRejection rejection = _gate(i, coverage, centerOffset, maxAngle);

    return FaceQualityScore(
      score: overall,
      accepted: rejection == QualityRejection.none,
      rejection: rejection,
      faceCoverage: coverage,
      centerOffset: centerOffset,
      faceCentered: centerOffset <= t.centerOffsetRejectAbove,
      brightnessScore: brightnessScore,
      sharpnessScore: sharpnessScore,
      sizeScore: sizeScore,
      centeringScore: centeringScore,
      poseScore: poseScore,
      eyeScore: eyeScore,
    );
  }

  QualityRejection _gate(
      QualityInput i, double coverage, double centerOffset, double maxAngle) {
    if (!i.faceDetected) return QualityRejection.noFace;
    if (i.brightness < t.darkRejectBelow) return QualityRejection.tooDark;
    if (i.brightness > t.brightRejectAbove) return QualityRejection.tooBright;
    if (i.sharpness < t.sharpnessRejectBelow) return QualityRejection.tooBlurry;
    if (coverage < t.coverageRejectBelow) return QualityRejection.faceTooSmall;
    if (centerOffset > t.centerOffsetRejectAbove) {
      return QualityRejection.faceOffCenter;
    }
    if (maxAngle > t.extremePoseRejectAbove) return QualityRejection.extremePose;
    if (!i.hasLeftEye || !i.hasRightEye) {
      return QualityRejection.eyesNotVisible;
    }
    return QualityRejection.none;
  }

  /// Trapezoidal band score: 100 inside [idealLow, idealHigh], decaying
  /// linearly to 0 at [hardLow] / [hardHigh].
  static double _bandScore(
    double v, {
    required double hardLow,
    required double idealLow,
    required double idealHigh,
    required double hardHigh,
  }) {
    if (v >= idealLow && v <= idealHigh) return 100;
    if (v <= hardLow || v >= hardHigh) return 0;
    if (v < idealLow) {
      return ((v - hardLow) / (idealLow - hardLow) * 100).clamp(0, 100).toDouble();
    }
    return ((hardHigh - v) / (hardHigh - idealHigh) * 100)
        .clamp(0, 100)
        .toDouble();
  }

  // ── Pure measurement helpers (reused by screens/tests) ──────────────────────

  /// Mean luminance (0–255) of a Y-plane / luma byte buffer, sampled on a grid
  /// for speed. Returns 0 for an empty buffer.
  static double brightnessFromLuma(List<int> luma,
      {int sampleStride = 97}) {
    if (luma.isEmpty) return 0;
    final int stride = sampleStride.clamp(1, luma.length);
    double sum = 0;
    int n = 0;
    for (int idx = 0; idx < luma.length; idx += stride) {
      sum += luma[idx] & 0xFF;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Laplacian-variance sharpness over a Y-plane buffer, sampled on a grid.
  /// Mirrors the camera screens' on-device computation so the validation screen
  /// and tests share one definition. Returns 0 for degenerate input.
  static double laplacianVariance(List<int> luma, int width, int height,
      {int sampleGrid = 64}) {
    if (luma.isEmpty || width < 3 || height < 3) return 0;
    if (luma.length < width * height) return 0;
    final int stepX = (width / sampleGrid).ceil().clamp(1, width);
    final int stepY = (height / sampleGrid).ceil().clamp(1, height);
    final List<double> responses = [];
    for (int y = 1; y < height - 1; y += stepY) {
      for (int x = 1; x < width - 1; x += stepX) {
        final int c = y * width + x;
        final double lap = ((luma[c - width] & 0xFF) +
                (luma[c + width] & 0xFF) +
                (luma[c - 1] & 0xFF) +
                (luma[c + 1] & 0xFF) -
                4 * (luma[c] & 0xFF))
            .toDouble();
        responses.add(lap);
      }
    }
    if (responses.isEmpty) return 0;
    final double mean = responses.reduce((a, b) => a + b) / responses.length;
    final double variance =
        responses.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            responses.length;
    return variance;
  }
}
