import 'dart:math' as math;

/// Pure-Dart embedding utilities: L2 normalization, multi-frame averaging,
/// numeric diagnostics and validity checks (Phases 3, 4, 7). No I/O.
class EmbeddingMath {
  /// Smallest magnitude considered a non-degenerate embedding.
  static const double minMagnitude = 1e-6;

  static double magnitude(List<double> v) {
    double s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    return math.sqrt(s);
  }

  static double mean(List<double> v) {
    if (v.isEmpty) return 0.0;
    double s = 0.0;
    for (final x in v) {
      s += x;
    }
    return s / v.length;
  }

  static double std(List<double> v) {
    if (v.length < 2) return 0.0;
    final m = mean(v);
    double s = 0.0;
    for (final x in v) {
      final d = x - m;
      s += d * d;
    }
    return math.sqrt(s / v.length);
  }

  /// True when [v] has [expectedLength] dimensions, all finite, and a
  /// non-degenerate magnitude (rejects near-zero / NaN / Inf / truncated).
  static bool isValid(List<double> v, {int expectedLength = 128}) {
    if (v.length != expectedLength) return false;
    double sumSq = 0.0;
    for (final x in v) {
      if (x.isNaN || x.isInfinite) return false;
      sumSq += x * x;
    }
    return math.sqrt(sumSq) > minMagnitude;
  }

  /// Cosine similarity between two equal-length vectors (0 if degenerate).
  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    return denom == 0 ? 0.0 : dot / denom;
  }

  /// Length-agnostic usability check: non-empty, all finite, non-degenerate
  /// magnitude. Used at runtime where the embedding dimension is model-defined.
  static bool isUsable(List<double> v) {
    if (v.isEmpty) return false;
    double sumSq = 0.0;
    for (final x in v) {
      if (x.isNaN || x.isInfinite) return false;
      sumSq += x * x;
    }
    return math.sqrt(sumSq) > minMagnitude;
  }

  /// Returns [v] scaled to unit L2 norm (unchanged if degenerate).
  static List<double> l2Normalize(List<double> v) {
    final mag = magnitude(v);
    if (mag <= minMagnitude) return List<double>.from(v);
    return v.map((x) => x / mag).toList();
  }

  /// Averages a list of embeddings robustly: L2-normalize each, take the
  /// element-wise mean, then L2-normalize the result. Reduces per-frame noise
  /// (Phase 7) without letting a large-magnitude frame dominate.
  ///
  /// [embeddings] must be non-empty and equal length.
  static List<double> averageNormalized(List<List<double>> embeddings) {
    if (embeddings.isEmpty) {
      throw ArgumentError('averageNormalized requires at least one embedding');
    }
    final dim = embeddings.first.length;
    final acc = List<double>.filled(dim, 0.0);
    for (final e in embeddings) {
      final n = l2Normalize(e);
      for (int i = 0; i < dim; i++) {
        acc[i] += n[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      acc[i] /= embeddings.length;
    }
    return l2Normalize(acc);
  }

  /// One-line diagnostic string (Phase 3 logging).
  static String diagnostics(List<double> v) =>
      'len=${v.length} magnitude=${magnitude(v).toStringAsFixed(4)} '
      'mean=${mean(v).toStringAsFixed(4)} std=${std(v).toStringAsFixed(4)}';
}
