// Forensic diagnostics for the multi-pose gallery. PURE and side-effect free —
// it computes evidence only and does NOT influence matching, the threshold, or
// alignment (GalleryMatcher is intentionally left unchanged).
import '../../models/employee_record.dart';
import '../../models/face_pose.dart';
import '../../models/face_template.dart';
import 'embedding_math.dart';

/// Per-template verification score, or a skip reason when it can't be scored.
class TemplateScore {
  final FacePose pose;
  final double? score;
  final String? skipReason; // 'lengthMismatch' | 'invalidEmbedding'
  const TemplateScore(this.pose, this.score, this.skipReason);
}

class GalleryAudit {
  /// Scores every template in [record] against the [live] embedding, recording
  /// skip reasons (mirrors GalleryMatcher's skip conditions, read-only).
  static List<TemplateScore> scoreTemplates(
      List<double> live, EmployeeRecord record) {
    final templates = record.templates;
    if (templates == null || templates.isEmpty) {
      return [_score(FacePose.frontal, live, record.embedding.vector)];
    }
    return [for (final t in templates) _score(t.poseLabel, live, t.embedding.vector)];
  }

  static TemplateScore _score(FacePose pose, List<double> live, List<double> v) {
    if (v.length != live.length) {
      return TemplateScore(pose, null, 'lengthMismatch');
    }
    if (!EmbeddingMath.isUsable(v)) {
      return TemplateScore(pose, null, 'invalidEmbedding');
    }
    return TemplateScore(pose, EmbeddingMath.cosine(live, v), null);
  }

  /// Best-scoring pose among [scores], or null if none were scorable.
  static FacePose? bestPose(List<TemplateScore> scores) {
    TemplateScore? best;
    for (final s in scores) {
      if (s.score == null) continue;
      if (best == null || s.score! > best.score!) best = s;
    }
    return best?.pose;
  }

  /// All unordered pairwise cosine similarities between templates, keyed
  /// `FRONTAL_LEFT`, `FRONTAL_RIGHT`, … (used to detect a degenerate gallery).
  static Map<String, double> pairwiseCosines(List<FaceTemplate> templates) {
    final out = <String, double>{};
    for (var i = 0; i < templates.length; i++) {
      for (var j = i + 1; j < templates.length; j++) {
        final key = '${templates[i].poseLabel.label}_${templates[j].poseLabel.label}';
        out[key] = EmbeddingMath.cosine(
            templates[i].embedding.vector, templates[j].embedding.vector);
      }
    }
    return out;
  }

  /// True if any pair exceeds [threshold] (templates nearly identical).
  static bool anyNearIdentical(Map<String, double> pairs,
          {double threshold = 0.95}) =>
      pairs.values.any((v) => v > threshold);

  /// True if any pair is below [threshold] (a template diverges so far it may
  /// be over-warped or capturing a different identity/region).
  static bool anyBelow(Map<String, double> pairs, {double threshold = 0.50}) =>
      pairs.values.any((v) => v < threshold);
}
