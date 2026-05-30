import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/face_aligner.dart';

const int outSize = 112;
final double dLx = FaceAligner.leftEyeXRatio * outSize; // 39.2
final double dRx = FaceAligner.rightEyeXRatio * outSize; // 72.8
final double dY = FaceAligner.eyeYRatio * outSize; // 44.8

/// Rotates [p] by [deg] around [center].
List<double> _rotate(List<double> p, List<double> center, double deg) {
  final r = deg * math.pi / 180;
  final dx = p[0] - center[0];
  final dy = p[1] - center[1];
  return [
    center[0] + dx * math.cos(r) - dy * math.sin(r),
    center[1] + dx * math.sin(r) + dy * math.cos(r),
  ];
}

/// Asserts the transform maps the eyes onto the canonical output positions.
void _expectCanonical(FaceTransform t, List<double> left, List<double> right) {
  final fl = t.forward(left);
  final fr = t.forward(right);
  expect(fl[0], closeTo(dLx, 1e-6));
  expect(fl[1], closeTo(dY, 1e-6));
  expect(fr[0], closeTo(dRx, 1e-6));
  expect(fr[1], closeTo(dY, 1e-6));
}

void main() {
  group('FaceAligner — eyes map to canonical positions regardless of pose', () {
    test('frontal (level eyes) → angle ≈ 0, mapped to canonical', () {
      final left = [40.0, 50.0];
      final right = [80.0, 50.0];
      final t = FaceAligner.computeTransform(left, right, outSize)!;
      expect(t.angleDegrees, closeTo(0.0, 1e-6));
      expect(t.eyeDistance, closeTo(40.0, 1e-6));
      _expectCanonical(t, left, right);
    });

    test('10° tilt → mapped to the SAME canonical positions', () {
      final center = [60.0, 50.0];
      final left = _rotate([40.0, 50.0], center, 10);
      final right = _rotate([80.0, 50.0], center, 10);
      final t = FaceAligner.computeTransform(left, right, outSize)!;
      expect(t.angleDegrees.abs(), closeTo(10.0, 1e-3));
      _expectCanonical(t, left, right); // alignment cancels the tilt
    });

    test('20° tilt → mapped to the SAME canonical positions', () {
      final center = [60.0, 50.0];
      final left = _rotate([40.0, 50.0], center, 20);
      final right = _rotate([80.0, 50.0], center, 20);
      final t = FaceAligner.computeTransform(left, right, outSize)!;
      expect(t.angleDegrees.abs(), closeTo(20.0, 1e-3));
      _expectCanonical(t, left, right);
    });

    test('different camera height (face shifted down) → still canonical', () {
      final left = [40.0, 120.0];
      final right = [80.0, 120.0];
      final t = FaceAligner.computeTransform(left, right, outSize)!;
      _expectCanonical(t, left, right); // translation normalizes position
    });

    test('different camera distance (closer/farther) → scale normalized', () {
      // Eyes twice as far apart (closer camera) and half as far (farther).
      final near = FaceAligner.computeTransform([20.0, 50.0], [100.0, 50.0], outSize)!;
      final far = FaceAligner.computeTransform([50.0, 50.0], [70.0, 50.0], outSize)!;
      // Both normalize the inter-eye distance to the same canonical span.
      _expectCanonical(near, [20.0, 50.0], [100.0, 50.0]);
      _expectCanonical(far, [50.0, 50.0], [70.0, 50.0]);
      expect(near.eyeDistance, closeTo(80.0, 1e-6));
      expect(far.eyeDistance, closeTo(20.0, 1e-6));
    });
  });

  group('FaceAligner — fallback / robustness', () {
    test('missing landmarks (coincident eyes) → null (caller falls back)', () {
      expect(
          FaceAligner.computeTransform([50.0, 50.0], [50.0, 50.0], outSize),
          isNull);
      expect(
          FaceAligner.align(
              List<int>.filled(112 * 112 * 3, 128), 112, 112,
              [50.0, 50.0], [51.0, 50.0], outSize),
          isNull); // distance < minEyeDistance
    });

    test('align produces a 112×112×3 tensor in [-1,1]', () {
      final rgb = List<int>.generate(200 * 200 * 3, (i) => i % 256);
      final res =
          FaceAligner.align(rgb, 200, 200, [70.0, 90.0], [120.0, 90.0], outSize);
      expect(res, isNotNull);
      expect(res!.tensor.length, outSize);
      expect(res.tensor[0].length, outSize);
      expect(res.tensor[0][0].length, 3);
      for (final row in res.tensor) {
        for (final px in row) {
          for (final c in px) {
            expect(c, inInclusiveRange(-1.0, 1.0));
          }
        }
      }
    });

    test('pose invariance end-to-end: frontal vs 20° tilt sample the same '
        'aligned geometry', () {
      // A synthetic image with a bright marker exactly between the eyes; after
      // alignment the marker must land at the same output pixel for both poses.
      const w = 200, h = 200;
      List<int> imgWithMarker(List<double> mid) {
        final img = List<int>.filled(w * h * 3, 0);
        final mx = mid[0].round(), my = mid[1].round();
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final p = ((my + dy) * w + (mx + dx)) * 3;
            if (p >= 0 && p + 2 < img.length) {
              img[p] = 255; img[p + 1] = 255; img[p + 2] = 255;
            }
          }
        }
        return img;
      }

      final center = [100.0, 100.0];
      // Frontal
      final fl = [80.0, 100.0], fr = [120.0, 100.0];
      final fImg = imgWithMarker([100.0, 100.0]);
      final fRes = FaceAligner.align(fImg, w, h, fl, fr, outSize)!;
      // 20° tilt (eyes + marker rotated together)
      final tl = _rotate(fl, center, 20), tr = _rotate(fr, center, 20);
      final tMid = _rotate([100.0, 100.0], center, 20);
      final tImg = imgWithMarker(tMid);
      final tRes = FaceAligner.align(tImg, w, h, tl, tr, outSize)!;

      // The brightest output pixel should be at (or near) the same location.
      List<int> brightest(List<List<List<double>>> t) {
        double best = -10; int bx = 0, by = 0;
        for (int y = 0; y < outSize; y++) {
          for (int x = 0; x < outSize; x++) {
            final v = t[y][x][0];
            if (v > best) { best = v; bx = x; by = y; }
          }
        }
        return [bx, by];
      }
      final fb = brightest(fRes.tensor);
      final tb = brightest(tRes.tensor);
      expect((fb[0] - tb[0]).abs(), lessThanOrEqualTo(2));
      expect((fb[1] - tb[1]).abs(), lessThanOrEqualTo(2));
    });
  });
}
