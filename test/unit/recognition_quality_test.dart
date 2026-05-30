import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/face_preprocessor.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/core/recognition/threshold_calibrator.dart';

void main() {
  group('EmbeddingMath — validity (Phases 3, 4)', () {
    test('valid 128-d vector is usable', () {
      final v = List<double>.generate(128, (i) => (i % 7) - 3.0);
      expect(EmbeddingMath.isUsable(v), isTrue);
      expect(EmbeddingMath.isValid(v, expectedLength: 128), isTrue);
    });

    test('empty embedding is rejected', () {
      expect(EmbeddingMath.isUsable(const []), isFalse);
      expect(EmbeddingMath.isValid(const [], expectedLength: 128), isFalse);
    });

    test('near-zero (degenerate) embedding is rejected', () {
      final z = List<double>.filled(128, 0.0);
      expect(EmbeddingMath.isUsable(z), isFalse);
    });

    test('corrupted (NaN/Inf) embedding is rejected', () {
      final v = List<double>.filled(128, 0.5)..[10] = double.nan;
      expect(EmbeddingMath.isUsable(v), isFalse);
      final w = List<double>.filled(128, 0.5)..[10] = double.infinity;
      expect(EmbeddingMath.isUsable(w), isFalse);
    });

    test('truncated embedding fails fixed-length validation', () {
      final v = List<double>.filled(64, 0.5);
      expect(EmbeddingMath.isValid(v, expectedLength: 128), isFalse);
    });
  });

  group('EmbeddingMath — normalization & averaging (Phase 7)', () {
    test('l2Normalize yields unit magnitude', () {
      final v = List<double>.generate(128, (i) => i.toDouble() + 1);
      final n = EmbeddingMath.l2Normalize(v);
      expect(EmbeddingMath.magnitude(n), closeTo(1.0, 1e-9));
    });

    test('averageNormalized of identical vectors equals the normalized vector',
        () {
      final v = List<double>.generate(128, (i) => (i - 64).toDouble());
      final avg = EmbeddingMath.averageNormalized([v, v, v]);
      final n = EmbeddingMath.l2Normalize(v);
      for (int i = 0; i < 128; i++) {
        expect(avg[i], closeTo(n[i], 1e-9));
      }
    });

    test('averaging reduces noise: averaged is closer to truth than a noisy '
        'single frame', () {
      final rng = Random(1);
      final truth = EmbeddingMath.l2Normalize(
          List<double>.generate(128, (_) => rng.nextDouble() * 2 - 1));
      List<double> noisy() => List<double>.generate(
          128, (i) => truth[i] + (rng.nextDouble() * 2 - 1) * 0.3);
      final frames = List.generate(5, (_) => noisy());
      final avg = EmbeddingMath.averageNormalized(frames);

      double cos(List<double> a, List<double> b) {
        double d = 0, na = 0, nb = 0;
        for (int i = 0; i < a.length; i++) {
          d += a[i] * b[i];
          na += a[i] * a[i];
          nb += b[i] * b[i];
        }
        return d / (sqrt(na) * sqrt(nb));
      }

      final single = cos(EmbeddingMath.l2Normalize(frames.first), truth);
      final averaged = cos(avg, truth);
      expect(averaged, greaterThan(single));
    });
  });

  group('FacePreprocessor — square crop fixes aspect distortion (Phase 6)', () {
    test('toSquare turns a 3:4 box into a centred square within bounds', () {
      final sq = FacePreprocessor.toSquare(
          const FaceBoxData(left: 30, top: 10, width: 60, height: 80), 200, 200);
      expect(sq.width, equals(sq.height)); // square
      expect(sq.width, equals(80)); // side = max(60,80)
      // centred on the original box centre (60, 50)
      expect(sq.left + sq.width / 2, closeTo(60, 1));
      expect(sq.top + sq.height / 2, closeTo(50, 1));
    });

    test('square crop stays inside the image when the box hugs an edge', () {
      final sq = FacePreprocessor.toSquare(
          const FaceBoxData(left: 190, top: 0, width: 30, height: 40), 200, 200);
      expect(sq.left + sq.width, lessThanOrEqualTo(200));
      expect(sq.top, greaterThanOrEqualTo(0));
      expect(sq.width, equals(sq.height));
    });

    test('cropResizeNormalize returns 112×112×3 in [-1,1]', () {
      final rgb = List<int>.generate(200 * 200 * 3, (i) => i % 256);
      final out = FacePreprocessor.cropResizeNormalize(
          rgb, 200, 200,
          const FaceBoxData(left: 40, top: 20, width: 60, height: 90), 112);
      expect(out.length, 112);
      expect(out[0].length, 112);
      expect(out[0][0].length, 3);
      for (final row in out) {
        for (final px in row) {
          for (final c in px) {
            expect(c, inInclusiveRange(-1.0, 1.0));
          }
        }
      }
    });
  });

  group('ThresholdCalibrator — data-driven (Phase 5)', () {
    test('separable distributions → midpoint threshold', () {
      final genuine = [0.88, 0.90, 0.93, 0.95];
      final impostor = [0.40, 0.55, 0.60, 0.70];
      final s = ThresholdCalibrator.calibrate(genuine, impostor);
      expect(s.separable, isTrue);
      expect(s.minGenuine, 0.88);
      expect(s.maxImpostor, 0.70);
      // midpoint (0.70+0.88)/2 = 0.79 → raised to security floor 0.80
      expect(s.recommendedThreshold, greaterThanOrEqualTo(0.80));
    });

    test('overlapping distributions → Youden-J cut, never below floor', () {
      final genuine = [0.78, 0.83, 0.86, 0.90];
      final impostor = [0.50, 0.70, 0.79, 0.82];
      final s = ThresholdCalibrator.calibrate(genuine, impostor);
      expect(s.separable, isFalse);
      expect(s.recommendedThreshold, greaterThanOrEqualTo(0.80));
      expect(s.avgGenuine, greaterThan(s.avgImpostor));
    });

    test('empty input throws', () {
      expect(() => ThresholdCalibrator.calibrate([], [0.5]),
          throwsArgumentError);
    });
  });
}
