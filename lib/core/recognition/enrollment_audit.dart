// Forensic audit of an enrolled employee's stored gallery (recognition quality).
//
// Reports, per stored pose template: the embedding magnitude (a correctly
// L2-normalized template is ~1.0) and the pairwise cosine between every pair of
// templates (to expose a collapsed gallery — all poses near-identical — or an
// over-warped one). PURE and read-only: it reuses [EmbeddingMath] and
// [GalleryAudit] and does NOT alter the matcher, threshold, or alignment.
import '../../models/face_pose.dart';
import '../../models/face_template.dart';
import 'embedding_math.dart';
import 'gallery_audit.dart';

/// Per-template numeric summary.
class EnrolledTemplateStat {
  final FacePose pose;
  final double magnitude;
  final int length;
  final double qualityScore;
  const EnrolledTemplateStat(
      this.pose, this.magnitude, this.length, this.qualityScore);
}

/// Audit over all stored templates of one employee.
class EnrollmentAuditReport {
  final List<EnrolledTemplateStat> templates;

  /// Pairwise cosines keyed `FRONTAL_LEFT`, … (from [GalleryAudit]).
  final Map<String, double> pairwise;

  const EnrollmentAuditReport(
      {required this.templates, required this.pairwise});

  /// A template pair this close means the gallery has effectively collapsed.
  bool get anyDegenerate => pairwise.values.any((v) => v > 0.95);

  /// A template pair this far apart suggests over-warping / a bad capture.
  bool get anyOverDivergent => pairwise.values.any((v) => v < 0.50);

  /// True when every template is properly unit-normalized (magnitude ≈ 1).
  bool get allUnitNormalized =>
      templates.every((t) => (t.magnitude - 1.0).abs() < 0.02);

  /// Greppable forensic lines.
  String toLog() {
    final b = StringBuffer();
    for (final t in templates) {
      b.writeln('[EnrollmentAudit] pose=${t.pose.label} '
          'magnitude=${t.magnitude.toStringAsFixed(4)} len=${t.length} '
          'quality=${t.qualityScore.toStringAsFixed(1)}');
    }
    pairwise.forEach((k, v) =>
        b.writeln('[EnrollmentAudit] pair $k=${v.toStringAsFixed(3)}'));
    b.write('[EnrollmentAudit] templates=${templates.length} '
        'unitNormalized=$allUnitNormalized '
        'degenerate=$anyDegenerate overDivergent=$anyOverDivergent');
    return b.toString();
  }
}

class EnrollmentAudit {
  const EnrollmentAudit();

  static EnrollmentAuditReport audit(List<FaceTemplate> templates) {
    final stats = [
      for (final t in templates)
        EnrolledTemplateStat(
          t.poseLabel,
          EmbeddingMath.magnitude(t.embedding.vector),
          t.embedding.vector.length,
          t.qualityScore,
        ),
    ];
    return EnrollmentAuditReport(
      templates: stats,
      pairwise: GalleryAudit.pairwiseCosines(templates),
    );
  }
}
