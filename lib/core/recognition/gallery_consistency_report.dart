// Gallery consistency / centrality report (diagnostics only).
//
// Computes how CENTRAL each enrolled template is within the gallery — its mean
// cosine to the other templates. The most-central template (the medoid) is the
// "strongest": a weak embedder tends to match ANY probe to the most generic /
// central template, so when the medoid is a turned pose and FRONTAL is an
// outlier, a near-frontal probe can rank the turned template above FRONTAL.
//
// Surfaces: the strongest template, suspicious (divergent) templates, and a
// flag when FRONTAL is NOT the strongest. PURE and read-only — it never touches
// the matcher, threshold, recognition engine, model, or enrollment decision.
library;

import '../../models/face_pose.dart';
import '../../models/face_template.dart';
import 'embedding_math.dart';
import 'gallery_audit.dart';

/// One template's centrality = mean cosine similarity to every other template.
class TemplateCentrality {
  final FacePose pose;
  final double centrality;
  const TemplateCentrality(this.pose, this.centrality);
}

class GalleryConsistencyReport {
  final List<TemplateCentrality> centralities;
  final Map<String, double> pairwise;

  /// A template more than this far below the strongest is "suspicious".
  static const double divergenceGap = 0.10;

  /// Absolute floor below which a template is suspicious regardless of the gap.
  static const double centralityFloor = 0.55;

  const GalleryConsistencyReport(this.centralities, this.pairwise);

  bool get _hasGallery => centralities.length >= 2;

  TemplateCentrality? get strongest {
    if (centralities.isEmpty) return null;
    return centralities
        .reduce((a, b) => a.centrality >= b.centrality ? a : b);
  }

  TemplateCentrality? get weakest {
    if (centralities.isEmpty) return null;
    return centralities
        .reduce((a, b) => a.centrality <= b.centrality ? a : b);
  }

  /// Templates that diverge from the gallery centroid (likely off-pose,
  /// over-warped, or low-quality captures).
  List<FacePose> get suspicious {
    if (!_hasGallery) return const [];
    final top = strongest!.centrality;
    return centralities
        .where((c) =>
            top - c.centrality > divergenceGap ||
            c.centrality < centralityFloor)
        .map((c) => c.pose)
        .toList();
  }

  bool get frontalPresent =>
      centralities.any((c) => c.pose == FacePose.frontal);

  bool get frontalIsStrongest =>
      frontalPresent && strongest?.pose == FacePose.frontal;

  /// Task-4 flag: FRONTAL is enrolled but is NOT the most central template.
  bool get frontalNotStrongest => frontalPresent && !frontalIsStrongest;

  bool get frontalSuspicious => suspicious.contains(FacePose.frontal);

  String toLog() {
    final b = StringBuffer();
    for (final c in centralities) {
      b.writeln('[GalleryConsistency] pose=${c.pose.label} '
          'centrality=${c.centrality.toStringAsFixed(3)}'
          '${suspicious.contains(c.pose) ? " FLAG=suspicious" : ""}');
    }
    b.write('[GalleryConsistency] strongest=${strongest?.pose.label ?? "n/a"} '
        'weakest=${weakest?.pose.label ?? "n/a"} '
        'suspicious=${suspicious.map((p) => p.label).toList()} '
        'frontalNotStrongest=$frontalNotStrongest '
        'frontalSuspicious=$frontalSuspicious');
    return b.toString();
  }
}

class GalleryConsistencyAnalyzer {
  const GalleryConsistencyAnalyzer();

  static GalleryConsistencyReport analyze(List<FaceTemplate> templates) {
    final n = templates.length;
    final centralities = <TemplateCentrality>[];
    for (var i = 0; i < n; i++) {
      double sum = 0;
      var count = 0;
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        sum += EmbeddingMath.cosine(
            templates[i].embedding.vector, templates[j].embedding.vector);
        count++;
      }
      centralities.add(TemplateCentrality(
        templates[i].poseLabel,
        count == 0 ? 1.0 : sum / count,
      ));
    }
    return GalleryConsistencyReport(
        centralities, GalleryAudit.pairwiseCosines(templates));
  }
}
