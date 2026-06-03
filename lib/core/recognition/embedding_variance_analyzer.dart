// Forensic analysis of intra-attempt embedding stability (recognition quality).
//
// For a SINGLE authentication attempt the camera collects N (≈5) frames of the
// SAME face at the SAME instant. A healthy embedder maps these near-identical
// inputs to near-identical vectors, so their pairwise cosine should be ~0.97+.
// If it isn't, the embedder (or its per-frame preprocessing) is unstable — the
// variance originates BEFORE averaging and BEFORE the gallery comparison.
//
// PURE and read-only: computes evidence only. Does NOT touch the matcher,
// threshold, averaging, alignment, or detection.
import '../../models/face_pose.dart';
import 'embedding_math.dart';

/// Pairwise-variance report over the live embeddings of one attempt.
class EmbeddingVarianceReport {
  /// Pairwise cosines keyed `frame1_frame2`, `frame1_frame3`, …
  final Map<String, double> pairs;
  final double min;
  final double avg;
  final double max;

  /// Number of live embeddings analysed.
  final int count;

  const EmbeddingVarianceReport({
    required this.pairs,
    required this.min,
    required this.avg,
    required this.max,
    required this.count,
  });

  /// Greppable forensic line(s) matching the requested format.
  String toLog() {
    final b = StringBuffer('[EmbeddingVariance] ');
    pairs.forEach((k, v) => b.write('$k=${v.toStringAsFixed(2)} '));
    b.write('min=${min.toStringAsFixed(2)} '
        'avg=${avg.toStringAsFixed(2)} max=${max.toStringAsFixed(2)} '
        'count=$count');
    return b.toString();
  }
}

/// Computes pairwise cosine similarity between the live frame embeddings of one
/// authentication attempt and summarises min/avg/max.
class EmbeddingVarianceAnalyzer {
  const EmbeddingVarianceAnalyzer();

  EmbeddingVarianceReport analyze(List<List<double>> embeddings) {
    final pairs = <String, double>{};
    final values = <double>[];
    for (var i = 0; i < embeddings.length; i++) {
      for (var j = i + 1; j < embeddings.length; j++) {
        final c = EmbeddingMath.cosine(embeddings[i], embeddings[j]);
        pairs['frame${i + 1}_frame${j + 1}'] = c;
        values.add(c);
      }
    }
    if (values.isEmpty) {
      return EmbeddingVarianceReport(
          pairs: pairs, min: 0, avg: 0, max: 0, count: embeddings.length);
    }
    var mn = values.first, mx = values.first, sum = 0.0;
    for (final v in values) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
      sum += v;
    }
    return EmbeddingVarianceReport(
      pairs: pairs,
      min: mn,
      avg: sum / values.length,
      max: mx,
      count: embeddings.length,
    );
  }
}

/// Where recognition variance originates, per the evidence.
enum VarianceSource { none, model, enrollment, averaging }

/// Verdict from cross-referencing the three measurable quantities.
class VarianceVerdict {
  final VarianceSource source;
  final String explanation;
  const VarianceVerdict(this.source, this.explanation);
}

/// Attributes low genuine-match similarity to the single most likely source by
/// cross-referencing:
///
/// * [liveIntraAvg]    — avg pairwise cosine among the live frames of an attempt
///                       (embedder stability for identical input).
/// * [enrollPairs]     — pairwise cosines between stored pose templates.
/// * [perFrameMatchAvg]— avg cosine of each live frame vs the best gallery
///                       template (match BEFORE averaging).
/// * [averagedMatch]   — the engine's reported similarity for the averaged
///                       embedding (match AFTER averaging).
///
/// Pure decision logic; uses only diagnostic comparison constants — it does NOT
/// read or alter the verification threshold or the matcher.
class VarianceAttribution {
  /// Live frames below this pairwise avg ⇒ the embedder is unstable.
  static const double liveStableMin = 0.90;

  /// Averaging that drops the match this far below the per-frame average ⇒ the
  /// averaging step is degrading the embedding.
  static const double averagingDropTolerance = 0.03;

  /// Template pair above this ⇒ gallery collapsed (templates near-identical).
  static const double galleryDegenerate = 0.95;

  /// Template pair below this ⇒ a template is over-warped / divergent.
  static const double galleryDivergent = 0.50;

  /// A healthy averaged genuine match needs no attribution.
  static const double healthyMatch = 0.85;

  static VarianceVerdict attribute({
    required double liveIntraAvg,
    required Map<String, double> enrollPairs,
    required double perFrameMatchAvg,
    required double averagedMatch,
  }) {
    if (averagedMatch >= healthyMatch) {
      return VarianceVerdict(VarianceSource.none,
          'Averaged genuine match ${_p(averagedMatch)} ≥ $healthyMatch — recognition healthy.');
    }
    // 1) Averaging must not lose ground versus the raw per-frame matches.
    if (perFrameMatchAvg - averagedMatch > averagingDropTolerance) {
      return VarianceVerdict(
          VarianceSource.averaging,
          'AVERAGING: per-frame match avg ${_p(perFrameMatchAvg)} but averaged '
          '${_p(averagedMatch)} (drop > $averagingDropTolerance) — the averaging '
          'step is degrading the live template.');
    }
    // 2) Unstable embedder: identical inputs → divergent vectors.
    if (liveIntraAvg < liveStableMin) {
      return VarianceVerdict(
          VarianceSource.model,
          'MODEL: live frames of one attempt only agree at ${_p(liveIntraAvg)} '
          '(< $liveStableMin). The embedder maps near-identical inputs to '
          'divergent vectors — instability originates in the model.');
    }
    // 3) Live frames are stable → look at the enrolled gallery.
    if (enrollPairs.isNotEmpty) {
      if (enrollPairs.values.any((v) => v > galleryDegenerate)) {
        return const VarianceVerdict(
            VarianceSource.enrollment,
            'ENROLLMENT: a template pair > $galleryDegenerate — stored poses are '
            'near-identical, so the gallery cannot represent pose variation.');
      }
      if (enrollPairs.values.any((v) => v < galleryDivergent)) {
        return const VarianceVerdict(
            VarianceSource.enrollment,
            'ENROLLMENT: a template pair < $galleryDivergent — a stored template '
            'is over-warped or captured a different region/identity.');
      }
    }
    // 4) Live stable + gallery healthy + averaging fine, yet match is low ⇒ the
    //    embedder lacks discriminative power / there is an enrol-vs-verify gap.
    return VarianceVerdict(
        VarianceSource.model,
        'MODEL: live frames are stable (${_p(liveIntraAvg)}), the gallery is '
        'healthy and averaging is faithful, yet the genuine match is only '
        '${_p(averagedMatch)} — the embedder lacks discriminative power '
        '(enrol-vs-verify representational gap).');
  }

  static String _p(double v) => v.toStringAsFixed(3);
}

/// Convenience: the best gallery cosine for a single live embedding, used to
/// compute the per-frame match average that feeds [VarianceAttribution]. Pure
/// read-only — mirrors the matcher's max-over-templates without altering it.
double bestGalleryCosine(List<double> live, List<List<double>> templates) {
  double best = 0;
  for (final t in templates) {
    if (t.length != live.length || !EmbeddingMath.isUsable(t)) continue;
    final c = EmbeddingMath.cosine(live, t);
    if (c > best) best = c;
  }
  return best;
}

/// Helper kept here (rather than the screen) so it is unit-testable: maps a
/// per-pose score list to the dominant pose, ignoring nulls.
FacePose? dominantPose(Map<FacePose, double> scores) {
  FacePose? best;
  double bestVal = -1;
  scores.forEach((p, v) {
    if (v > bestVal) {
      bestVal = v;
      best = p;
    }
  });
  return best;
}
