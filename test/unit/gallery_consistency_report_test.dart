import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/gallery_consistency_report.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';

List<double> _unit(List<double> v) {
  final m = math.sqrt(v.fold<double>(0, (a, x) => a + x * x));
  return m == 0 ? v : v.map((x) => x / m).toList();
}

FaceTemplate _t(FacePose pose, List<double> vec) => FaceTemplate(
      embedding: FaceEmbedding(_unit(vec)),
      poseLabel: pose,
      yaw: 0,
      pitch: 0,
      qualityScore: 80,
      createdAt: DateTime.utc(2026, 1, 1),
      pipelineVersion: 3,
    );

void main() {
  group('GalleryConsistencyAnalyzer', () {
    test('FRONTAL outlier → not strongest, flagged suspicious', () {
      // left/right/up/down cluster tightly around axis-0; FRONTAL points away.
      final r = GalleryConsistencyAnalyzer.analyze([
        _t(FacePose.frontal, [0, 1, 0, 0]), // orthogonal to the cluster
        _t(FacePose.left, [1, 0.1, 0, 0]),
        _t(FacePose.right, [1, -0.1, 0, 0]),
        _t(FacePose.up, [1, 0, 0.1, 0]),
        _t(FacePose.down, [1, 0, -0.1, 0]),
      ]);
      expect(r.frontalNotStrongest, isTrue);
      expect(r.frontalSuspicious, isTrue);
      expect(r.strongest!.pose, isNot(FacePose.frontal));
      expect(r.weakest!.pose, FacePose.frontal);
    });

    test('healthy gallery with FRONTAL central → frontal strongest', () {
      final r = GalleryConsistencyAnalyzer.analyze([
        _t(FacePose.frontal, [1, 0, 0, 0]),
        _t(FacePose.left, [0.9, 0.4, 0, 0]),
        _t(FacePose.right, [0.9, -0.4, 0, 0]),
        _t(FacePose.up, [0.9, 0, 0.4, 0]),
        _t(FacePose.down, [0.9, 0, -0.4, 0]),
      ]);
      expect(r.frontalIsStrongest, isTrue);
      expect(r.frontalNotStrongest, isFalse);
    });

    test('centrality is mean cosine to the other templates', () {
      final r = GalleryConsistencyAnalyzer.analyze([
        _t(FacePose.frontal, [1, 0, 0, 0]),
        _t(FacePose.left, [1, 0, 0, 0]), // identical → centrality 1.0
      ]);
      for (final c in r.centralities) {
        expect(c.centrality, closeTo(1.0, 1e-9));
      }
    });

    test('toLog reports per-pose centrality + summary flags', () {
      final r = GalleryConsistencyAnalyzer.analyze([
        _t(FacePose.frontal, [0, 1, 0, 0]),
        _t(FacePose.left, [1, 0.1, 0, 0]),
        _t(FacePose.right, [1, -0.1, 0, 0]),
      ]);
      final log = r.toLog();
      expect(log, contains('[GalleryConsistency] pose=FRONTAL centrality='));
      expect(log, contains('frontalNotStrongest=true'));
    });

    test('single template → no suspicion, it is trivially strongest', () {
      final r =
          GalleryConsistencyAnalyzer.analyze([_t(FacePose.frontal, [1, 0, 0, 0])]);
      expect(r.suspicious, isEmpty);
      expect(r.strongest!.pose, FacePose.frontal);
    });
  });
}
