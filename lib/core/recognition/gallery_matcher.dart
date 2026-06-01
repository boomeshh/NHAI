import '../../models/employee_record.dart';
import '../../models/face_pose.dart';
import 'embedding_math.dart';

// Result of matching a live embedding against one employee's gallery.
class GalleryMatch {
  final double score;
  final FacePose? bestPose; // null for legacy single-template records
  final int templateCount;
  const GalleryMatch(this.score, this.bestPose, this.templateCount);

  static const GalleryMatch none = GalleryMatch(0.0, null, 0);
}

// Gallery (max-similarity-across-templates) matcher with backward compatibility
// for legacy single-template records. Threshold is applied by the caller — this
// only computes the best similarity. Does NOT lower any threshold.
class GalleryMatcher {
  /// Matches [live] against [record]: max cosine over the pose gallery, or the
  /// single legacy embedding when no gallery exists (Phase 4 backward compat).
  static GalleryMatch matchEmployee(List<double> live, EmployeeRecord record) {
    final templates = record.templates;

    // Legacy single-template path.
    if (templates == null || templates.isEmpty) {
      final stored = record.embedding.vector;
      if (stored.length != live.length || !EmbeddingMath.isUsable(stored)) {
        return GalleryMatch.none;
      }
      return GalleryMatch(EmbeddingMath.cosine(live, stored), null, 1);
    }

    // Multi-pose gallery: take the best-matching pose.
    double best = -2.0;
    FacePose? bestPose;
    int valid = 0;
    for (final t in templates) {
      final v = t.embedding.vector;
      if (v.length != live.length || !EmbeddingMath.isUsable(v)) continue;
      valid++;
      final s = EmbeddingMath.cosine(live, v);
      if (s > best) {
        best = s;
        bestPose = t.poseLabel;
      }
    }
    if (valid == 0) return GalleryMatch.none;
    return GalleryMatch(best, bestPose, valid);
  }
}
