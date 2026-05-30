/// Data-driven threshold calibration (Phase 5). Given measured genuine and
/// impostor similarity scores, computes distribution statistics and recommends
/// a threshold from the data — never a guessed/hardcoded value.
class ThresholdStats {
  final double minGenuine;
  final double maxGenuine;
  final double avgGenuine;
  final double minImpostor;
  final double maxImpostor;
  final double avgImpostor;

  /// Recommended decision threshold derived from the data.
  final double recommendedThreshold;

  /// True when genuine and impostor distributions do not overlap.
  final bool separable;

  /// Human-readable explanation of how [recommendedThreshold] was chosen.
  final String reasoning;

  const ThresholdStats({
    required this.minGenuine,
    required this.maxGenuine,
    required this.avgGenuine,
    required this.minImpostor,
    required this.maxImpostor,
    required this.avgImpostor,
    required this.recommendedThreshold,
    required this.separable,
    required this.reasoning,
  });
}

class ThresholdCalibrator {
  /// Never recommend a threshold below this (security floor), even if the data
  /// would allow it — protects against an unrepresentative impostor sample.
  static const double securityFloor = 0.80;

  static ThresholdStats calibrate(
    List<double> genuine,
    List<double> impostor,
  ) {
    if (genuine.isEmpty || impostor.isEmpty) {
      throw ArgumentError('Both genuine and impostor scores are required');
    }
    final gMin = genuine.reduce((a, b) => a < b ? a : b);
    final gMax = genuine.reduce((a, b) => a > b ? a : b);
    final gAvg = genuine.reduce((a, b) => a + b) / genuine.length;
    final iMin = impostor.reduce((a, b) => a < b ? a : b);
    final iMax = impostor.reduce((a, b) => a > b ? a : b);
    final iAvg = impostor.reduce((a, b) => a + b) / impostor.length;

    final bool separable = iMax < gMin;
    double recommended;
    String reasoning;

    if (separable) {
      // Distributions don't overlap → midpoint maximizes the margin.
      recommended = (iMax + gMin) / 2.0;
      reasoning =
          'Separable: maxImpostor=$iMax < minGenuine=$gMin → midpoint ${recommended.toStringAsFixed(3)}.';
    } else {
      // Overlap → choose the threshold that maximizes balanced accuracy
      // (Youden's J) across candidate cut-points.
      recommended = _youdenThreshold(genuine, impostor);
      reasoning =
          'Overlapping distributions (maxImpostor=$iMax ≥ minGenuine=$gMin) → '
          'Youden-J optimal cut-point ${recommended.toStringAsFixed(3)}.';
    }

    if (recommended < securityFloor) {
      reasoning +=
          ' Raised to security floor ${securityFloor.toStringAsFixed(2)}.';
      recommended = securityFloor;
    }
    return ThresholdStats(
      minGenuine: gMin,
      maxGenuine: gMax,
      avgGenuine: gAvg,
      minImpostor: iMin,
      maxImpostor: iMax,
      avgImpostor: iAvg,
      recommendedThreshold: recommended,
      separable: separable,
      reasoning: reasoning,
    );
  }

  static double _youdenThreshold(
      List<double> genuine, List<double> impostor) {
    final candidates = <double>{...genuine, ...impostor}.toList()..sort();
    double best = candidates.first;
    double bestJ = -2.0;
    for (final t in candidates) {
      final tpr = genuine.where((s) => s >= t).length / genuine.length;
      final fpr = impostor.where((s) => s >= t).length / impostor.length;
      final j = tpr - fpr;
      if (j > bestJ) {
        bestJ = j;
        best = t;
      }
    }
    return best;
  }
}
