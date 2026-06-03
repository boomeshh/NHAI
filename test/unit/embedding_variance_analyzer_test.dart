import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/embedding_variance_analyzer.dart';

/// A unit vector of length [n] pointing mostly along axis 0 with a small
/// perturbation [noise] on axis 1 — lets tests dial frame-to-frame agreement.
List<double> _vec(int n, {double noise = 0.0}) {
  final v = List<double>.filled(n, 0.0);
  v[0] = 1.0;
  if (n > 1) v[1] = noise;
  final mag = math.sqrt(v.fold<double>(0, (a, x) => a + x * x));
  return v.map((x) => x / mag).toList();
}

void main() {
  const analyzer = EmbeddingVarianceAnalyzer();

  group('EmbeddingVarianceAnalyzer.analyze', () {
    test('identical embeddings → pairwise 1.0, min=avg=max=1', () {
      final e = _vec(128);
      final r = analyzer.analyze([e, e, e]);
      expect(r.count, 3);
      expect(r.pairs.length, 3); // C(3,2)
      expect(r.min, closeTo(1.0, 1e-9));
      expect(r.avg, closeTo(1.0, 1e-9));
      expect(r.max, closeTo(1.0, 1e-9));
      expect(r.pairs.containsKey('frame1_frame2'), isTrue);
    });

    test('noisy frames lower the pairwise similarity', () {
      final r = analyzer.analyze([
        _vec(128, noise: 0.0),
        _vec(128, noise: 0.6),
        _vec(128, noise: 1.2),
      ]);
      expect(r.avg, lessThan(1.0));
      expect(r.min, lessThan(r.max));
    });

    test('single embedding → no pairs, zeros', () {
      final r = analyzer.analyze([_vec(128)]);
      expect(r.pairs, isEmpty);
      expect(r.avg, 0);
      expect(r.count, 1);
    });

    test('toLog emits the [EmbeddingVariance] line with avg', () {
      final r = analyzer.analyze([_vec(128), _vec(128)]);
      expect(r.toLog(), startsWith('[EmbeddingVariance]'));
      expect(r.toLog(), contains('frame1_frame2='));
      expect(r.toLog(), contains('avg='));
    });
  });

  group('bestGalleryCosine', () {
    test('returns the max cosine across templates', () {
      final live = _vec(4);
      final templates = [
        [0.0, 1.0, 0.0, 0.0], // orthogonal → 0
        _vec(4), // identical → 1
      ];
      expect(bestGalleryCosine(live, templates), closeTo(1.0, 1e-9));
    });

    test('skips length-mismatched templates', () {
      final live = _vec(4);
      expect(bestGalleryCosine(live, [
        [1.0, 0.0], // wrong length → skipped
      ]), 0);
    });
  });

  group('VarianceAttribution.attribute', () {
    Map<String, double> healthyPairs() => const {
          'FRONTAL_LEFT': 0.82,
          'FRONTAL_RIGHT': 0.80,
          'LEFT_RIGHT': 0.71,
        };

    test('healthy averaged match → none', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.98,
        enrollPairs: healthyPairs(),
        perFrameMatchAvg: 0.90,
        averagedMatch: 0.91,
      );
      expect(v.source, VarianceSource.none);
    });

    test('averaging dropping below per-frame avg → averaging', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.99,
        enrollPairs: healthyPairs(),
        perFrameMatchAvg: 0.84,
        averagedMatch: 0.70, // big drop
      );
      expect(v.source, VarianceSource.averaging);
    });

    test('unstable live frames → model', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.80, // < 0.90
        enrollPairs: healthyPairs(),
        perFrameMatchAvg: 0.79,
        averagedMatch: 0.79,
      );
      expect(v.source, VarianceSource.model);
    });

    test('collapsed gallery → enrollment', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.98,
        enrollPairs: const {'FRONTAL_LEFT': 0.985},
        perFrameMatchAvg: 0.80,
        averagedMatch: 0.80,
      );
      expect(v.source, VarianceSource.enrollment);
    });

    test('over-divergent template → enrollment', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.98,
        enrollPairs: const {'FRONTAL_LEFT': 0.40},
        perFrameMatchAvg: 0.80,
        averagedMatch: 0.80,
      );
      expect(v.source, VarianceSource.enrollment);
    });

    test('stable live + healthy gallery + faithful averaging but low match → model', () {
      final v = VarianceAttribution.attribute(
        liveIntraAvg: 0.97,
        enrollPairs: healthyPairs(),
        perFrameMatchAvg: 0.80,
        averagedMatch: 0.80, // the documented 0.68–0.83 regime
      );
      expect(v.source, VarianceSource.model);
      expect(v.explanation, contains('discriminative'));
    });
  });
}
