// TEMPORARY Recognition Validation core (read-only). Aggregates 10 genuine
// verification attempts and attributes a low success rate to the single most
// likely subsystem. Uses only existing read-only APIs — it does NOT modify the
// matcher, threshold, gallery, alignment, or any other subsystem.
import 'dart:math' as math;

import '../../models/face_pose.dart';

enum Subsystem { none, model, alignment, enrollmentGallery, preprocessing }

class AttemptResult {
  final int attempt;
  final FacePose? bestPose;
  final double similarity;
  final bool pass;
  const AttemptResult(this.attempt, this.bestPose, this.similarity, this.pass);
}

class ValidationReport {
  final List<AttemptResult> attempts;
  final double avgSimilarity;
  final double minSimilarity;
  final double maxSimilarity;
  final double stdDevSimilarity;
  final double successRate;
  final double threshold;

  /// Enrollment pairwise template cosines (from [GalleryAudit.pairwiseCosines]).
  final Map<String, double> galleryPairs;

  const ValidationReport({
    required this.attempts,
    required this.avgSimilarity,
    required this.minSimilarity,
    required this.maxSimilarity,
    required this.stdDevSimilarity,
    required this.successRate,
    required this.threshold,
    required this.galleryPairs,
  });

  bool get _galleryDegenerate => galleryPairs.values.any((v) => v > 0.95);
  bool get _galleryOverDivergent => galleryPairs.values.any((v) => v < 0.50);
  bool get _frontalDominant =>
      attempts.isNotEmpty &&
      attempts.where((a) => a.bestPose == FacePose.frontal).length >=
          attempts.length / 2;

  /// Single most-likely subsystem responsible when avg < 0.80.
  Subsystem get culprit {
    if (avgSimilarity >= 0.80) return Subsystem.none;
    if (galleryPairs.isNotEmpty && _galleryDegenerate) {
      return Subsystem.enrollmentGallery; // templates collapsed → gallery useless
    }
    if (galleryPairs.isNotEmpty && _galleryOverDivergent) {
      return Subsystem.alignment; // a turned template over-warped (>… divergence)
    }
    // Preprocessing is identical on enrol & verify (verified previously), so a
    // low score with frontal as the best pose points at the embedder itself.
    if (_frontalDominant) return Subsystem.model;
    // Non-frontal best pose dominating with low scores → alignment/pose geometry.
    return Subsystem.alignment;
  }

  String get verdict {
    switch (culprit) {
      case Subsystem.none:
        return 'PASS: average ${_p(avgSimilarity)} ≥ 0.80 — recognition healthy.';
      case Subsystem.enrollmentGallery:
        return 'ENROLLMENT GALLERY: templates are near-identical (a pair >0.95) '
            '— the multi-pose gallery adds nothing; matching degenerates to one '
            'template.';
      case Subsystem.model:
        return 'MODEL: avg ${_p(avgSimilarity)} with FRONTAL as best pose. '
            'Enrolment and verification use identical preprocessing for frontal, '
            'so a same-person score this low implicates the 192-D embedder.';
      case Subsystem.alignment:
        return 'ALIGNMENT: similarity is low and either a template diverges <0.50 '
            'or non-frontal poses dominate — the affine alignment is degrading '
            'turned-pose geometry.';
      case Subsystem.preprocessing:
        return 'PREPROCESSING: input pipeline mismatch.';
    }
  }

  static String _p(double v) => v.toStringAsFixed(3);

  /// CSV / text report.
  String toCsv() {
    final b = StringBuffer('attempt,bestPose,similarity,result\n');
    for (final a in attempts) {
      b.writeln('${a.attempt},${a.bestPose?.label ?? "none"},'
          '${a.similarity.toStringAsFixed(4)},${a.pass ? "PASS" : "FAIL"}');
    }
    b.writeln();
    b.writeln('metric,value');
    b.writeln('averageSimilarity,${avgSimilarity.toStringAsFixed(4)}');
    b.writeln('minSimilarity,${minSimilarity.toStringAsFixed(4)}');
    b.writeln('maxSimilarity,${maxSimilarity.toStringAsFixed(4)}');
    b.writeln('stdDevSimilarity,${stdDevSimilarity.toStringAsFixed(4)}');
    b.writeln('successRate,${(successRate * 100).toStringAsFixed(0)}%');
    b.writeln('threshold,$threshold');
    galleryPairs.forEach((k, v) =>
        b.writeln('gallery_${k.toLowerCase()},${v.toStringAsFixed(4)}'));
    b.writeln('culprit,${culprit.name}');
    return b.toString();
  }
}

class RecognitionValidator {
  final double threshold;
  const RecognitionValidator(this.threshold);

  /// Builds the report from the per-attempt (bestPose, similarity) results and
  /// the enrollment gallery pairs. Pure — no I/O, no matcher access.
  ValidationReport analyze(
    List<({FacePose? bestPose, double similarity})> raw, {
    Map<String, double> galleryPairs = const {},
  }) {
    final attempts = <AttemptResult>[];
    var mn = raw.isEmpty ? 0.0 : raw.first.similarity;
    var mx = raw.isEmpty ? 0.0 : raw.first.similarity;
    var sum = 0.0, pass = 0;
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i].similarity;
      final p = s >= threshold;
      attempts.add(AttemptResult(i + 1, raw[i].bestPose, s, p));
      if (s < mn) mn = s;
      if (s > mx) mx = s;
      sum += s;
      if (p) pass++;
    }
    final n = raw.isEmpty ? 1 : raw.length;
    final avg = sum / n;
    // Population standard deviation of the per-attempt similarities.
    var sumSqDiff = 0.0;
    for (final a in attempts) {
      final d = a.similarity - avg;
      sumSqDiff += d * d;
    }
    final std = raw.isEmpty ? 0.0 : math.sqrt(sumSqDiff / raw.length);
    return ValidationReport(
      attempts: attempts,
      avgSimilarity: avg,
      minSimilarity: raw.isEmpty ? 0.0 : mn,
      maxSimilarity: raw.isEmpty ? 0.0 : mx,
      stdDevSimilarity: std,
      successRate: raw.isEmpty ? 0.0 : pass / raw.length,
      threshold: threshold,
      galleryPairs: galleryPairs,
    );
  }
}
