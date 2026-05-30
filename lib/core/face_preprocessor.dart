import 'dart:math' as math;
import 'dart:typed_data';
import 'camera_frame.dart';

/// Pure-Dart image preprocessing for the face-recognition pipeline.
///
/// All methods are static, deterministic and unit-testable (no I/O, no native
/// bindings), covering tasks: YUV420→RGB conversion, YUV420→NV21 (for ML Kit),
/// and crop-to-face + resize-to-112 + normalize.
class FacePreprocessor {
  /// Converts a YUV420 (planar/semi-planar) camera image to packed RGB888.
  ///
  /// Returns a `width*height*3` byte buffer in row-major R,G,B order.
  ///
  /// [yRowStride] is the stride of the Y plane; [uvRowStride]/[uvPixelStride]
  /// describe the chroma planes (pixelStride is 2 for semi-planar NV12/NV21,
  /// 1 for fully planar I420). Values out of range are clamped to [0,255].
  static Uint8List yuv420ToRgb(
    List<int> yPlane,
    List<int> uPlane,
    List<int> vPlane,
    int width,
    int height, {
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final rgb = Uint8List(width * height * 3);
    for (int y = 0; y < height; y++) {
      final int yRow = y * yRowStride;
      final int uvRow = (y >> 1) * uvRowStride;
      for (int x = 0; x < width; x++) {
        final int yIndex = yRow + x;
        final int uvIndex = uvRow + (x >> 1) * uvPixelStride;

        final int yv = (yIndex < yPlane.length) ? yPlane[yIndex] & 0xFF : 0;
        final int uv = (uvIndex < uPlane.length) ? uPlane[uvIndex] & 0xFF : 128;
        final int vv = (uvIndex < vPlane.length) ? vPlane[uvIndex] & 0xFF : 128;

        final double yf = yv.toDouble();
        final double uf = uv - 128.0;
        final double vf = vv - 128.0;

        final int r = (yf + 1.370705 * vf).round();
        final int g = (yf - 0.337633 * uf - 0.698001 * vf).round();
        final int b = (yf + 1.732446 * uf).round();

        final int o = (y * width + x) * 3;
        rgb[o] = _clamp8(r);
        rgb[o + 1] = _clamp8(g);
        rgb[o + 2] = _clamp8(b);
      }
    }
    return rgb;
  }

  /// Converts YUV420 planes to NV21 (Y plane followed by interleaved V,U),
  /// the most broadly-supported input format for the ML Kit face detector.
  static Uint8List yuv420ToNv21(
    List<int> yPlane,
    List<int> uPlane,
    List<int> vPlane,
    int width,
    int height, {
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final out = Uint8List(width * height + 2 * ((width + 1) ~/ 2) * ((height + 1) ~/ 2));
    int o = 0;
    for (int y = 0; y < height; y++) {
      final int row = y * yRowStride;
      for (int x = 0; x < width; x++) {
        final int i = row + x;
        out[o++] = (i < yPlane.length) ? yPlane[i] & 0xFF : 0;
      }
    }
    for (int y = 0; y < height ~/ 2; y++) {
      final int row = y * uvRowStride;
      for (int x = 0; x < width ~/ 2; x++) {
        final int uvIndex = row + x * uvPixelStride;
        out[o++] = (uvIndex < vPlane.length) ? vPlane[uvIndex] & 0xFF : 128; // V
        out[o++] = (uvIndex < uPlane.length) ? uPlane[uvIndex] & 0xFF : 128; // U
      }
    }
    return out;
  }

  /// Converts a single-plane NV21 buffer (Y plane then interleaved V,U) to
  /// packed RGB888. [bytesPerRow] is the Y-plane row stride (≥ width; may
  /// include padding). Returns `width*height*3` bytes.
  static Uint8List nv21ToRgb(
    List<int> nv21,
    int width,
    int height, {
    required int bytesPerRow,
  }) {
    final rgb = Uint8List(width * height * 3);
    final int ySize = bytesPerRow * height;
    for (int y = 0; y < height; y++) {
      final int yRow = y * bytesPerRow;
      final int uvRow = ySize + (y >> 1) * bytesPerRow;
      for (int x = 0; x < width; x++) {
        final int yIndex = yRow + x;
        // NV21 chroma is interleaved V,U at half resolution.
        final int uvIndex = uvRow + (x & ~1);
        final int yv = (yIndex < nv21.length) ? nv21[yIndex] & 0xFF : 0;
        final int vv = (uvIndex < nv21.length) ? nv21[uvIndex] & 0xFF : 128;
        final int uv = (uvIndex + 1 < nv21.length) ? nv21[uvIndex + 1] & 0xFF : 128;

        final double yf = yv.toDouble();
        final double uf = uv - 128.0;
        final double vf = vv - 128.0;
        final int o = (y * width + x) * 3;
        rgb[o] = _clamp8((yf + 1.370705 * vf).round());
        rgb[o + 1] = _clamp8((yf - 0.337633 * uf - 0.698001 * vf).round());
        rgb[o + 2] = _clamp8((yf + 1.732446 * uf).round());
      }
    }
    return rgb;
  }

  /// Expands [box] to a SQUARE region centred on the face, clamped to the image.
  ///
  /// MobileFaceNet expects a square, aspect-preserved crop. Cropping the
  /// non-square ML Kit box and resizing to a square tensor stretches the face
  /// (different horizontal vs vertical scale) and destroys recognition quality.
  /// Using `side = max(width, height)` keeps the face geometry intact and makes
  /// enrollment and verification crops consistent.
  static FaceBoxData toSquare(FaceBoxData box, int imgW, int imgH) {
    int side = math.max(box.width, box.height);
    side = math.max(1, math.min(side, math.min(imgW, imgH)));
    final double cx = box.left + box.width / 2.0;
    final double cy = box.top + box.height / 2.0;
    final int left = (cx - side / 2).round().clamp(0, imgW - side);
    final int top = (cy - side / 2).round().clamp(0, imgH - side);
    return FaceBoxData(left: left, top: top, width: side, height: side);
  }

  /// Crops the [box] region from a packed RGB888 image and resizes it to
  /// [outSize]×[outSize], normalizing each channel to `[-1, 1]` via
  /// `(v/127.5) - 1`. Returns the `[outSize][outSize][3]` tensor MobileFaceNet
  /// expects (one batch slot).
  ///
  /// The box is first made SQUARE (aspect-preserving — see [toSquare]); a
  /// degenerate box falls back to the full image so the call never throws.
  static List<List<List<double>>> cropResizeNormalize(
    List<int> rgb,
    int width,
    int height,
    FaceBoxData box,
    int outSize,
  ) {
    FaceBoxData b = box;
    if (b.width <= 0 || b.height <= 0) {
      b = FaceBoxData(left: 0, top: 0, width: width, height: height);
    }
    // Aspect-preserving square crop (the key recognition-quality fix).
    final sq = toSquare(b, width, height);
    final int left = sq.left;
    final int top = sq.top;
    final int side = sq.width;

    return List.generate(
      outSize,
      (oy) => List.generate(
        outSize,
        (ox) {
          final int srcX = (left + (ox * side / outSize)).floor().clamp(0, width - 1);
          final int srcY = (top + (oy * side / outSize)).floor().clamp(0, height - 1);
          final int p = (srcY * width + srcX) * 3;
          double r = 0, g = 0, b = 0;
          if (p + 2 < rgb.length) {
            r = ((rgb[p] & 0xFF) / 127.5) - 1.0;
            g = ((rgb[p + 1] & 0xFF) / 127.5) - 1.0;
            b = ((rgb[p + 2] & 0xFF) / 127.5) - 1.0;
          }
          return [r, g, b];
        },
      ),
    );
  }

  static int _clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
}
