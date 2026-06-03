import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/face_quality.dart';

/// A well-lit, sharp, centred, frontal face with both eyes open and visible.
/// Frame 480×640; box 200×260 centred → coverage ≈0.17, centre offset 0.
QualityInput _good({
  bool faceDetected = true,
  double brightness = 140,
  double sharpness = 60,
  int boxWidth = 200,
  int boxHeight = 260,
  int? boxLeft,
  int? boxTop,
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
  double leftEyeOpen = 0.95,
  double rightEyeOpen = 0.95,
  bool hasLeftEye = true,
  bool hasRightEye = true,
  int frameWidth = 480,
  int frameHeight = 640,
}) =>
    QualityInput(
      faceDetected: faceDetected,
      brightness: brightness,
      sharpness: sharpness,
      boxWidth: boxWidth,
      boxHeight: boxHeight,
      boxLeft: boxLeft ?? (frameWidth - boxWidth) ~/ 2,
      boxTop: boxTop ?? (frameHeight - boxHeight) ~/ 2,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
      hasLeftEye: hasLeftEye,
      hasRightEye: hasRightEye,
    );

void main() {
  const a = FaceQualityAnalyzer();

  group('FaceQualityAnalyzer — acceptance', () {
    test('ideal frame is accepted with a high score', () {
      final r = a.analyze(_good());
      expect(r.accepted, isTrue);
      expect(r.rejection, QualityRejection.none);
      expect(r.score, greaterThan(85));
      expect(r.faceCentered, isTrue);
      expect(r.faceCoverage, closeTo(0.169, 0.02));
    });
  });

  group('FaceQualityAnalyzer — hard rejections', () {
    test('no face → noFace, score 0', () {
      final r = a.analyze(_good(faceDetected: false));
      expect(r.accepted, isFalse);
      expect(r.rejection, QualityRejection.noFace);
      expect(r.score, 0);
    });

    test('too dark → tooDark', () {
      final r = a.analyze(_good(brightness: 30));
      expect(r.rejection, QualityRejection.tooDark);
      expect(r.accepted, isFalse);
    });

    test('too bright → tooBright', () {
      final r = a.analyze(_good(brightness: 240));
      expect(r.rejection, QualityRejection.tooBright);
    });

    test('too blurry → tooBlurry', () {
      final r = a.analyze(_good(sharpness: 4));
      expect(r.rejection, QualityRejection.tooBlurry);
      expect(r.sharpnessScore, lessThan(10));
    });

    test('face too small → faceTooSmall', () {
      final r = a.analyze(_good(boxWidth: 30, boxHeight: 30));
      expect(r.rejection, QualityRejection.faceTooSmall);
    });

    test('face off-center → faceOffCenter', () {
      // Big-enough box jammed into the top-left corner.
      final r = a.analyze(_good(boxLeft: 0, boxTop: 0));
      expect(r.rejection, QualityRejection.faceOffCenter);
      expect(r.faceCentered, isFalse);
    });

    test('extreme yaw → extremePose', () {
      final r = a.analyze(_good(yaw: 40));
      expect(r.rejection, QualityRejection.extremePose);
    });

    test('extreme roll (tilt) → extremePose', () {
      final r = a.analyze(_good(roll: 35));
      expect(r.rejection, QualityRejection.extremePose);
    });

    test('missing an eye landmark → eyesNotVisible', () {
      final r = a.analyze(_good(hasLeftEye: false));
      expect(r.rejection, QualityRejection.eyesNotVisible);
      expect(r.eyeScore, 0);
    });
  });

  group('FaceQualityAnalyzer — scoring behaviour', () {
    test('borderline brightness scores below ideal but may still pass', () {
      final r = a.analyze(_good(brightness: 75));
      expect(r.brightnessScore, lessThan(100));
      expect(r.brightnessScore, greaterThan(0));
    });

    test('side pose lowers pose sub-score', () {
      final frontal = a.analyze(_good()).poseScore;
      final side = a.analyze(_good(yaw: 18)).poseScore;
      expect(side, lessThan(frontal));
    });

    test('every rejection reason has an operator message', () {
      for (final reason in QualityRejection.values) {
        expect(reason.message, isNotEmpty);
      }
    });
  });

  group('FaceQualityAnalyzer — pure measurement helpers', () {
    test('brightnessFromLuma averages the buffer', () {
      expect(FaceQualityAnalyzer.brightnessFromLuma(List.filled(1000, 120)),
          closeTo(120, 0.001));
      expect(FaceQualityAnalyzer.brightnessFromLuma(const []), 0);
    });

    test('laplacianVariance is ~0 for a flat image, higher for an edge', () {
      const w = 64, h = 64;
      final flat = List.filled(w * h, 128);
      expect(FaceQualityAnalyzer.laplacianVariance(flat, w, h), lessThan(1));

      final edged = List<int>.generate(
          w * h, (i) => (i % w) < w ~/ 2 ? 20 : 220);
      expect(FaceQualityAnalyzer.laplacianVariance(edged, w, h),
          greaterThan(FaceQualityAnalyzer.laplacianVariance(flat, w, h)));
    });
  });
}
