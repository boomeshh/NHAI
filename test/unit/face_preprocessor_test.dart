import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/face_preprocessor.dart';

void main() {
  group('FacePreprocessor.yuv420ToRgb', () {
    test('produces width*height*3 RGB bytes', () {
      const w = 4, h = 4;
      final y = List<int>.filled(w * h, 128);
      final u = List<int>.filled((w ~/ 2) * (h ~/ 2), 128);
      final v = List<int>.filled((w ~/ 2) * (h ~/ 2), 128);
      final rgb = FacePreprocessor.yuv420ToRgb(
        y, u, v, w, h,
        yRowStride: w, uvRowStride: w ~/ 2, uvPixelStride: 1,
      );
      expect(rgb.length, equals(w * h * 3));
    });

    test('neutral chroma (128) → grayscale (R≈G≈B≈Y)', () {
      const w = 2, h = 2;
      final y = [100, 100, 100, 100];
      final u = [128];
      final v = [128];
      final rgb = FacePreprocessor.yuv420ToRgb(
        y, u, v, w, h,
        yRowStride: w, uvRowStride: w ~/ 2, uvPixelStride: 1,
      );
      // With U=V=128 the conversion collapses to R=G=B=Y.
      for (int i = 0; i < rgb.length; i += 3) {
        expect(rgb[i], equals(100));
        expect(rgb[i + 1], equals(100));
        expect(rgb[i + 2], equals(100));
      }
    });

    test('clamps out-of-range channel values to [0,255]', () {
      const w = 2, h = 2;
      final y = [255, 255, 255, 255];
      final u = [255]; // pushes B high
      final v = [255]; // pushes R high
      final rgb = FacePreprocessor.yuv420ToRgb(
        y, u, v, w, h,
        yRowStride: w, uvRowStride: w ~/ 2, uvPixelStride: 1,
      );
      for (final b in rgb) {
        expect(b, inInclusiveRange(0, 255));
      }
    });
  });

  group('FacePreprocessor.cropResizeNormalize', () {
    test('outputs [112][112][3] normalized to [-1,1]', () {
      const w = 64, h = 64;
      final rgb = List<int>.generate(w * h * 3, (i) => i % 256);
      final out = FacePreprocessor.cropResizeNormalize(
        rgb, w, h, const FaceBoxData(left: 8, top: 8, width: 32, height: 32), 112,
      );
      expect(out.length, equals(112));
      expect(out[0].length, equals(112));
      expect(out[0][0].length, equals(3));
      for (final row in out) {
        for (final px in row) {
          for (final c in px) {
            expect(c, inInclusiveRange(-1.0, 1.0));
          }
        }
      }
    });

    test('degenerate box falls back to full image (no throw)', () {
      const w = 8, h = 8;
      final rgb = List<int>.filled(w * h * 3, 128);
      final out = FacePreprocessor.cropResizeNormalize(
        rgb, w, h, const FaceBoxData(left: 0, top: 0, width: 0, height: 0), 112,
      );
      expect(out.length, equals(112));
      // 128 → (128/127.5)-1 ≈ 0.0039
      expect(out[0][0][0], closeTo(0.0039, 1e-3));
    });

    test('box clamps to image bounds when oversized', () {
      const w = 16, h = 16;
      final rgb = List<int>.filled(w * h * 3, 200);
      final out = FacePreprocessor.cropResizeNormalize(
        rgb, w, h, const FaceBoxData(left: 10, top: 10, width: 100, height: 100), 112,
      );
      expect(out.length, equals(112));
      expect(out[111][111].length, equals(3));
    });
  });
}
