import 'dart:math' as math;

/// The similarity transform (rotation + uniform scale + translation) that maps
/// source-image pixels into the aligned output, plus diagnostics.
///
/// Forward map:  `ox = a*sx - b*sy + tx`,  `oy = b*sx + a*sy + ty`
/// where `a = s·cosθ`, `b = s·sinθ`.
class FaceTransform {
  final double a;
  final double b;
  final double tx;
  final double ty;

  /// Source eye-line angle in degrees (0 = level).
  final double angleDegrees;

  /// Inter-eye distance in source pixels.
  final double eyeDistance;

  const FaceTransform({
    required this.a,
    required this.b,
    required this.tx,
    required this.ty,
    required this.angleDegrees,
    required this.eyeDistance,
  });

  /// Applies the forward transform to a source point `[x, y]`.
  List<double> forward(List<double> p) =>
      [a * p[0] - b * p[1] + tx, b * p[0] + a * p[1] + ty];
}

/// Result of [FaceAligner.align]: the normalized input tensor plus diagnostics.
class AlignmentResult {
  final List<List<List<double>>> tensor; // [outSize][outSize][3], values in [-1,1]
  final double angleDegrees;
  final double eyeDistance;
  const AlignmentResult(this.tensor, this.angleDegrees, this.eyeDistance);
}

/// Production-grade 2-point face alignment using eye landmarks.
///
/// Computes a similarity transform that places the left/right eyes at fixed
/// canonical positions in a square output, making the crop invariant to head
/// roll (eyes leveled), camera distance (inter-eye distance normalized) and
/// translation (face centered). This removes the pose sensitivity of a plain
/// square crop and keeps embeddings of the same person consistent across
/// moderate angle/position changes.
class FaceAligner {
  /// Canonical eye positions as ratios of the output side length (ArcFace-like:
  /// eyes on the upper third, symmetric about the centre).
  static const double leftEyeXRatio = 0.35;
  static const double rightEyeXRatio = 0.65;
  static const double eyeYRatio = 0.40;

  /// Minimum inter-eye distance (px) for a usable alignment.
  static const double minEyeDistance = 4.0;

  /// Computes the alignment transform for the given eye centres, or null if the
  /// landmarks are degenerate (coincident / too close → unreliable).
  static FaceTransform? computeTransform(
    List<double> leftEye,
    List<double> rightEye,
    int outSize,
  ) {
    final double dxs = rightEye[0] - leftEye[0];
    final double dys = rightEye[1] - leftEye[1];
    final double eyeDistance = math.sqrt(dxs * dxs + dys * dys);
    if (eyeDistance < minEyeDistance) return null;

    final double dLx = leftEyeXRatio * outSize;
    final double dLy = eyeYRatio * outSize;
    final double destDistance = (rightEyeXRatio - leftEyeXRatio) * outSize;

    final double s = destDistance / eyeDistance;
    final double phi = math.atan2(dys, dxs); // source eye-line angle
    final double a = s * math.cos(phi);
    final double b = -s * math.sin(phi); // θ = -phi (level the eyes)
    final double tx = dLx - (a * leftEye[0] - b * leftEye[1]);
    final double ty = dLy - (b * leftEye[0] + a * leftEye[1]);

    return FaceTransform(
      a: a,
      b: b,
      tx: tx,
      ty: ty,
      angleDegrees: phi * 180.0 / math.pi,
      eyeDistance: eyeDistance,
    );
  }

  /// Produces an aligned, normalized `[outSize][outSize][3]` tensor by inverse-
  /// warping the source RGB image. Returns null when landmarks are unavailable
  /// or degenerate, so the caller can fall back to the square crop.
  static AlignmentResult? align(
    List<int> rgb,
    int width,
    int height,
    List<double> leftEye,
    List<double> rightEye,
    int outSize,
  ) {
    final t = computeTransform(leftEye, rightEye, outSize);
    if (t == null) return null;

    final double det = t.a * t.a + t.b * t.b;
    if (det <= 0) return null;
    final double inv = 1.0 / det;

    final tensor = List.generate(
      outSize,
      (oy) => List.generate(
        outSize,
        (ox) {
          // Inverse map output → source.
          final double dx = ox - t.tx;
          final double dy = oy - t.ty;
          final int sx = ((t.a * dx + t.b * dy) * inv).round();
          final int sy = ((-t.b * dx + t.a * dy) * inv).round();

          double r = 0, g = 0, b = 0;
          if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
            final int p = (sy * width + sx) * 3;
            if (p + 2 < rgb.length) {
              r = ((rgb[p] & 0xFF) / 127.5) - 1.0;
              g = ((rgb[p + 1] & 0xFF) / 127.5) - 1.0;
              b = ((rgb[p + 2] & 0xFF) / 127.5) - 1.0;
            }
          }
          return [r, g, b];
        },
      ),
    );

    return AlignmentResult(tensor, t.angleDegrees, t.eyeDistance);
  }
}
