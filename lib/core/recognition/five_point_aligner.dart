// 5-point affine face alignment (eyes + nose base + mouth corners).
//
// Solves a least-squares 2-D affine that maps the 5 detected landmarks onto the
// canonical ArcFace template, then inverse-warps the source RGB into the
// normalized model input. Better out-of-plane (yaw/pitch) normalization than
// 2-point eye alignment. Pure / unit-testable; the caller falls back to
// eye-only or square crop when landmarks are unavailable.

/// 2-D affine `o = A·s + t`, with A = [[a, b], [c, d]].
class Affine {
  final double a, b, c, d, tx, ty;
  const Affine(this.a, this.b, this.c, this.d, this.tx, this.ty);

  List<double> apply(List<double> p) =>
      [a * p[0] + b * p[1] + tx, c * p[0] + d * p[1] + ty];

  /// Inverse transform, or null if singular.
  Affine? inverse() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12) return null;
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return Affine(ia, ib, ic, id, -(ia * tx + ib * ty), -(ic * tx + id * ty));
  }
}

class FivePointAligner {
  /// Canonical ArcFace 5-point template at 112×112:
  /// leftEye, rightEye, noseBase, mouthLeft, mouthRight.
  static const List<List<double>> canonical112 = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
  ];

  /// Least-squares affine mapping [src] (5 points) → [dst] (5 points).
  /// Returns null if degenerate.
  static Affine? solve(List<List<double>> src, List<List<double>> dst) {
    if (src.length < 3 || src.length != dst.length) return null;
    // Two independent 3-param fits (x-row and y-row) sharing the design matrix
    // M rows [sx, sy, 1]. Normal equations: (MᵀM) p = Mᵀ d.
    final mtm = List.generate(3, (_) => List<double>.filled(3, 0.0));
    final mtx = List<double>.filled(3, 0.0); // for dst x
    final mty = List<double>.filled(3, 0.0); // for dst y
    for (var i = 0; i < src.length; i++) {
      final r = [src[i][0], src[i][1], 1.0];
      for (var j = 0; j < 3; j++) {
        for (var k = 0; k < 3; k++) {
          mtm[j][k] += r[j] * r[k];
        }
        mtx[j] += r[j] * dst[i][0];
        mty[j] += r[j] * dst[i][1];
      }
    }
    final px = _solve3(mtm, mtx);
    final py = _solve3(mtm, mty);
    if (px == null || py == null) return null;
    // px = [a, b, tx], py = [c, d, ty]
    return Affine(px[0], px[1], py[0], py[1], px[2], py[2]);
  }

  /// Produces the normalized `[outSize][outSize][3]` tensor for the 5 landmarks
  /// [src5] (leftEye, rightEye, noseBase, mouthLeft, mouthRight). Returns null
  /// if the affine is degenerate (caller falls back).
  static List<List<List<double>>>? align(
    List<int> rgb,
    int width,
    int height,
    List<List<double>> src5,
    int outSize,
  ) {
    if (src5.length < 5) return null;
    final scale = outSize / 112.0;
    final dst = canonical112.map((p) => [p[0] * scale, p[1] * scale]).toList();
    final fwd = solve(src5, dst);
    if (fwd == null) return null;
    final inv = fwd.inverse();
    if (inv == null) return null;

    return List.generate(
      outSize,
      (oy) => List.generate(
        outSize,
        (ox) {
          final s = inv.apply([ox.toDouble(), oy.toDouble()]);
          final sx = s[0].round();
          final sy = s[1].round();
          double r = 0, g = 0, b = 0;
          if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
            final p = (sy * width + sx) * 3;
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
  }

  /// Solves a 3×3 system by Gaussian elimination with partial pivoting.
  static List<double>? _solve3(List<List<double>> a, List<double> b) {
    final m = [
      [a[0][0], a[0][1], a[0][2], b[0]],
      [a[1][0], a[1][1], a[1][2], b[1]],
      [a[2][0], a[2][1], a[2][2], b[2]],
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var r = col + 1; r < 3; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-12) return null;
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      for (var r = 0; r < 3; r++) {
        if (r == col) continue;
        final f = m[r][col] / m[col][col];
        for (var k = col; k < 4; k++) {
          m[r][k] -= f * m[col][k];
        }
      }
    }
    return [m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]];
  }
}
