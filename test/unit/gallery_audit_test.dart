import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/core/recognition/gallery_audit.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';

List<double> _vec(double seed) =>
    EmbeddingMath.l2Normalize(List<double>.generate(192, (i) => (i + seed) % 11 - 5.0));

FaceTemplate _tpl(FacePose pose, List<double> v) => FaceTemplate(
      embedding: FaceEmbedding(v),
      poseLabel: pose,
      yaw: 0,
      pitch: 0,
      qualityScore: 1.0,
      createdAt: DateTime.utc(2026, 1, 1),
      pipelineVersion: 3,
    );

EmployeeRecord _rec(List<FaceTemplate>? templates, {List<double>? legacy}) =>
    EmployeeRecord(
      employeeId: 'E',
      name: 'E',
      department: 'D',
      embedding: FaceEmbedding(legacy ?? _vec(1)),
      enrolledAt: DateTime.utc(2026, 1, 1),
      templates: templates,
    );

void main() {
  group('GalleryAudit.scoreTemplates (verification per-template)', () {
    test('scores every template and identifies the best pose', () {
      final live = _vec(3);
      final rec = _rec([
        _tpl(FacePose.frontal, _vec(1)),
        _tpl(FacePose.left, _vec(2)),
        _tpl(FacePose.right, _vec(3)), // == live
        _tpl(FacePose.up, _vec(4)),
        _tpl(FacePose.down, _vec(5)),
      ]);
      final scores = GalleryAudit.scoreTemplates(live, rec);
      expect(scores.length, 5);
      expect(scores.every((s) => s.skipReason == null), isTrue);
      final right = scores.firstWhere((s) => s.pose == FacePose.right);
      expect(right.score, closeTo(1.0, 1e-9));
      expect(GalleryAudit.bestPose(scores), FacePose.right);
    });

    test('legacy single-template record → one score, no skip', () {
      final live = _vec(7);
      final scores = GalleryAudit.scoreTemplates(live, _rec(null, legacy: _vec(7)));
      expect(scores.length, 1);
      expect(scores.first.score, closeTo(1.0, 1e-9));
    });

    test('length mismatch → skipReason=lengthMismatch', () {
      final scores = GalleryAudit.scoreTemplates(
          List<double>.filled(128, 0.1), _rec([_tpl(FacePose.frontal, _vec(1))]));
      expect(scores.single.score, isNull);
      expect(scores.single.skipReason, 'lengthMismatch');
    });

    test('degenerate (zero) embedding → skipReason=invalidEmbedding', () {
      final scores = GalleryAudit.scoreTemplates(
          _vec(1), _rec([_tpl(FacePose.frontal, List<double>.filled(192, 0.0))]));
      expect(scores.single.skipReason, 'invalidEmbedding');
    });
  });

  group('GalleryAudit.pairwiseCosines (enrollment diversity)', () {
    test('distinct poses → all 10 pairs present, none identical', () {
      final templates = [
        _tpl(FacePose.frontal, _vec(1)),
        _tpl(FacePose.left, _vec(2)),
        _tpl(FacePose.right, _vec(3)),
        _tpl(FacePose.up, _vec(4)),
        _tpl(FacePose.down, _vec(5)),
      ];
      final pairs = GalleryAudit.pairwiseCosines(templates);
      expect(pairs.length, 10); // 5 choose 2
      expect(pairs.containsKey('FRONTAL_LEFT'), isTrue);
      expect(GalleryAudit.anyNearIdentical(pairs), isFalse);
    });

    test('anyBelow flags an over-divergent (<0.50) pair', () {
      // base vs near-opposite → cosine well below 0.5.
      final base = _vec(1);
      final opposite = base.map((x) => -x).toList();
      final templates = [
        _tpl(FacePose.frontal, base),
        _tpl(FacePose.left, opposite),
      ];
      final pairs = GalleryAudit.pairwiseCosines(templates);
      expect(GalleryAudit.anyBelow(pairs), isTrue); // -1.0 < 0.50
      // Nothing is below -1.5 (cosine min is -1.0).
      expect(GalleryAudit.anyBelow(pairs, threshold: -1.5), isFalse);
    });

    test('identical templates → cosine ~1.0 → flagged near-identical', () {
      final same = _vec(9);
      final templates = [
        _tpl(FacePose.frontal, same),
        _tpl(FacePose.left, List<double>.from(same)),
        _tpl(FacePose.right, List<double>.from(same)),
      ];
      final pairs = GalleryAudit.pairwiseCosines(templates);
      expect(pairs.values.every((v) => v > 0.99), isTrue);
      expect(GalleryAudit.anyNearIdentical(pairs), isTrue);
    });
  });
}
