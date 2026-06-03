import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/enrollment_audit.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';

List<double> _unit(List<double> v) {
  final mag = math.sqrt(v.fold<double>(0, (a, x) => a + x * x));
  return mag == 0 ? v : v.map((x) => x / mag).toList();
}

FaceTemplate _t(FacePose pose, List<double> vec, {double quality = 80}) =>
    FaceTemplate(
      embedding: FaceEmbedding(vec),
      poseLabel: pose,
      yaw: 0,
      pitch: 0,
      qualityScore: quality,
      createdAt: DateTime.utc(2024, 1, 1),
      pipelineVersion: 3,
    );

void main() {
  group('EnrollmentAudit.audit', () {
    test('reports magnitude, length and pairwise for each template', () {
      final report = EnrollmentAudit.audit([
        _t(FacePose.frontal, _unit([1, 0, 0, 0])),
        _t(FacePose.left, _unit([0.8, 0.6, 0, 0])),
        _t(FacePose.right, _unit([0.8, 0, 0.6, 0])),
      ]);
      expect(report.templates, hasLength(3));
      expect(report.templates.first.magnitude, closeTo(1.0, 1e-9));
      expect(report.templates.first.length, 4);
      expect(report.pairwise, hasLength(3)); // C(3,2)
      expect(report.allUnitNormalized, isTrue);
    });

    test('flags a collapsed (near-identical) gallery', () {
      final v = _unit([1, 0.01, 0, 0]);
      final report = EnrollmentAudit.audit([
        _t(FacePose.frontal, v),
        _t(FacePose.left, v),
      ]);
      expect(report.anyDegenerate, isTrue);
    });

    test('flags an over-divergent template', () {
      final report = EnrollmentAudit.audit([
        _t(FacePose.frontal, _unit([1, 0, 0, 0])),
        _t(FacePose.left, _unit([0, 1, 0, 0])), // orthogonal → cos 0 < 0.5
      ]);
      expect(report.anyOverDivergent, isTrue);
    });

    test('detects non-unit-normalized templates (legacy embeddings)', () {
      final report = EnrollmentAudit.audit([
        _t(FacePose.frontal, [3, 4, 0, 0]), // magnitude 5
      ]);
      expect(report.templates.first.magnitude, closeTo(5.0, 1e-9));
      expect(report.allUnitNormalized, isFalse);
    });

    test('toLog emits per-template and pair lines', () {
      final report = EnrollmentAudit.audit([
        _t(FacePose.frontal, _unit([1, 0, 0, 0])),
        _t(FacePose.left, _unit([0.8, 0.6, 0, 0])),
      ]);
      final log = report.toLog();
      expect(log, contains('[EnrollmentAudit] pose=FRONTAL'));
      expect(log, contains('magnitude='));
      expect(log, contains('[EnrollmentAudit] pair FRONTAL_LEFT='));
      expect(log, contains('unitNormalized=true'));
    });

    test('empty gallery → no templates, no pairs', () {
      final report = EnrollmentAudit.audit(const []);
      expect(report.templates, isEmpty);
      expect(report.pairwise, isEmpty);
      expect(report.allUnitNormalized, isTrue); // vacuously
    });
  });
}
