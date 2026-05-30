import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/face_detection/face_detector_interface.dart';
import 'package:nhai_auth/core/face_detection/mlkit_face_detector.dart';
import 'package:nhai_auth/core/face_preprocessor.dart';

/// A fake detector that returns a configurable face list and records the frame
/// it was called with (so tests can assert rotation / front-camera handling).
class _FakeDetector implements FaceDetectorInterface {
  final List<DetectedFace> result;
  CameraFrame? lastFrame;
  _FakeDetector(this.result);

  @override
  Future<List<DetectedFace>> detect(CameraFrame frame) async {
    lastFrame = frame;
    // Mimic MlKit's null-guard: an "invalid image" (no nv21) yields no faces.
    if (frame.nv21Bytes == null) return const [];
    return result;
  }

  @override
  void dispose() {}
}

CameraFrame _frame({
  List<int>? nv21,
  int rotation = 0,
  int w = 8,
  int h = 8,
}) =>
    CameraFrame(
      bytes: const [1, 2, 3],
      width: w,
      height: h,
      sharpnessScore: 50.0,
      nv21Bytes: nv21,
      rotationDegrees: rotation,
    );

void main() {
  group('mlkitRotationFromDegrees (rotated frame handling)', () {
    test('maps 0/90/180/270 to the right enum', () {
      expect(mlkitRotationFromDegrees(0), InputImageRotation.rotation0deg);
      expect(mlkitRotationFromDegrees(90), InputImageRotation.rotation90deg);
      expect(mlkitRotationFromDegrees(180), InputImageRotation.rotation180deg);
      expect(mlkitRotationFromDegrees(270), InputImageRotation.rotation270deg);
    });

    test('wraps values ≥360', () {
      expect(mlkitRotationFromDegrees(360), InputImageRotation.rotation0deg);
      expect(mlkitRotationFromDegrees(450), InputImageRotation.rotation90deg);
    });
  });

  group('FacePreprocessor.nv21ToRgb', () {
    test('produces width*height*3 bytes', () {
      const w = 4, h = 4;
      final nv21 = List<int>.filled(w * h + (w * h ~/ 2), 128);
      final rgb = FacePreprocessor.nv21ToRgb(nv21, w, h, bytesPerRow: w);
      expect(rgb.length, equals(w * h * 3));
    });

    test('neutral chroma → grayscale (R=G=B=Y)', () {
      const w = 2, h = 2;
      // Y plane = 100, chroma (V,U) = 128,128.
      final nv21 = [100, 100, 100, 100, 128, 128];
      final rgb = FacePreprocessor.nv21ToRgb(nv21, w, h, bytesPerRow: w);
      for (int i = 0; i < rgb.length; i += 3) {
        expect(rgb[i], equals(100));
        expect(rgb[i + 1], equals(100));
        expect(rgb[i + 2], equals(100));
      }
    });

    test('invalid image (empty buffer) does not throw, returns zeros', () {
      final rgb = FacePreprocessor.nv21ToRgb(const [], 4, 4, bytesPerRow: 4);
      expect(rgb.length, equals(4 * 4 * 3));
      expect(rgb.every((b) => b == 0), isTrue);
    });
  });

  group('FaceDetectorInterface contract', () {
    test('face detected → returns the configured face with its box', () async {
      final det = _FakeDetector([
        const DetectedFace(
          box: FaceBox(left: 10, top: 20, width: 30, height: 40),
        ),
      ]);
      final faces = await det.detect(_frame(nv21: List<int>.filled(96, 128)));
      expect(faces, hasLength(1));
      expect(faces.first.box.left, 10);
      expect(faces.first.box.width, 30);
    });

    test('no face → empty list', () async {
      final det = _FakeDetector(const []);
      final faces = await det.detect(_frame(nv21: List<int>.filled(96, 128)));
      expect(faces, isEmpty);
    });

    test('front-camera rotated frame is passed through unchanged', () async {
      final det = _FakeDetector(const []);
      await det.detect(_frame(nv21: List<int>.filled(96, 128), rotation: 270));
      expect(det.lastFrame!.rotationDegrees, 270);
    });

    test('invalid image (null nv21) → no faces', () async {
      final det = _FakeDetector([
        const DetectedFace(box: FaceBox(left: 0, top: 0, width: 1, height: 1)),
      ]);
      final faces = await det.detect(_frame(nv21: null));
      expect(faces, isEmpty);
    });
  });
}
