import 'package:flutter/foundation.dart' show debugPrint;
import 'recognition_debug.dart';

// Aggregated genuine-match statistics for one experiment (one alignment mode).
class VerifyStats {
  final int count;
  final double avg;
  final double min;
  final double max;
  final double successRate; // fraction of verifications with score >= threshold

  const VerifyStats({
    required this.count,
    required this.avg,
    required this.min,
    required this.max,
    required this.successRate,
  });

  factory VerifyStats.from(List<double> scores, double threshold) {
    if (scores.isEmpty) {
      return const VerifyStats(count: 0, avg: 0, min: 0, max: 0, successRate: 0);
    }
    var mn = scores.first, mx = scores.first, sum = 0.0, pass = 0;
    for (final s in scores) {
      if (s < mn) mn = s;
      if (s > mx) mx = s;
      sum += s;
      if (s >= threshold) pass++;
    }
    return VerifyStats(
      count: scores.length,
      avg: sum / scores.length,
      min: mn,
      max: mx,
      successRate: pass / scores.length,
    );
  }
}

class ExperimentRow {
  final AlignmentMode mode;
  final VerifyStats stats;
  const ExperimentRow(this.mode, this.stats);

  String get label => switch (mode) {
        AlignmentMode.twoPoint => 'A: 2-point',
        AlignmentMode.square => 'B: square',
        AlignmentMode.fivePoint => 'C: 5-point',
        AlignmentMode.auto => 'auto',
      };
}

typedef EnrollFn = Future<void> Function();
typedef VerifyFn = Future<double> Function(); // returns genuine-match trust score

/// Controlled A/B/C preprocessing experiment. For each alignment mode it does a
/// fresh enroll of the same employee, runs N verifications, and aggregates the
/// scores. ONLY the preprocessing path varies — [freshEnroll]/[verifyOnce] use
/// the unchanged engine, matcher, gallery, blink and averaging.
class RecognitionExperiment {
  final EnrollFn freshEnroll;
  final VerifyFn verifyOnce;
  final double threshold;

  RecognitionExperiment({
    required this.freshEnroll,
    required this.verifyOnce,
    required this.threshold,
  });

  Future<VerifyStats> runMode(AlignmentMode mode, {int verifications = 10}) async {
    RecognitionDebugMode.forcedAlignment = mode;
    try {
      await freshEnroll();
      final scores = <double>[];
      for (var i = 0; i < verifications; i++) {
        scores.add(await verifyOnce());
      }
      final stats = VerifyStats.from(scores, threshold);
      debugPrint('[RecognitionDebug] mode=${mode.name} '
          'avg=${stats.avg.toStringAsFixed(3)} min=${stats.min.toStringAsFixed(3)} '
          'max=${stats.max.toStringAsFixed(3)} '
          'success=${(stats.successRate * 100).round()}%');
      return stats;
    } finally {
      RecognitionDebugMode.reset();
    }
  }

  Future<List<ExperimentRow>> runAll({
    List<AlignmentMode> modes = const [
      AlignmentMode.twoPoint, // Experiment A
      AlignmentMode.square, // Experiment B
      AlignmentMode.fivePoint, // Experiment C
    ],
    int verifications = 10,
  }) async {
    final rows = <ExperimentRow>[];
    for (final m in modes) {
      rows.add(ExperimentRow(m, await runMode(m, verifications: verifications)));
    }
    debugPrint(formatTable(rows, threshold));
    return rows;
  }

  /// Mode with the highest average genuine similarity.
  static AlignmentMode bestMode(List<ExperimentRow> rows) =>
      rows.reduce((a, b) => a.stats.avg >= b.stats.avg ? a : b).mode;

  static String formatTable(List<ExperimentRow> rows, double threshold) {
    final b = StringBuffer('\n[RecognitionDebug] RESULTS (threshold=$threshold)\n');
    b.writeln('Mode        | Avg   | Min   | Max   | Success');
    b.writeln('------------|-------|-------|-------|--------');
    for (final r in rows) {
      b.writeln('${r.label.padRight(11)} | '
          '${r.stats.avg.toStringAsFixed(3)} | '
          '${r.stats.min.toStringAsFixed(3)} | '
          '${r.stats.max.toStringAsFixed(3)} | '
          '${(r.stats.successRate * 100).round()}%');
    }
    if (rows.isNotEmpty) {
      b.writeln('BEST: ${bestMode(rows).name} (highest avg genuine similarity)');
    }
    return b.toString();
  }
}
