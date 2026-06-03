import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/face_quality.dart';
import 'package:nhai_auth/core/face_detection/face_stability_tracker.dart';
import 'package:nhai_auth/core/face_detection/landmark_audit.dart';
import 'package:nhai_auth/core/validation/biometric_validation.dart';

/// End-to-end detection pipeline harness: runs the four hardening modules
/// (quality, stability, landmark audit, blink) together the way the validation
/// screen drives them, and reports the converged state. Pure — no camera.
class _Pipeline {
  final analyzer = const FaceQualityAnalyzer();
  final auditor = const LandmarkAuditor();
  final stability = FaceStabilityTracker(requiredConsecutive: 5);
  final blink = BlinkLivenessTracker();

  FaceQualityScore? lastQuality;
  LandmarkAuditResult? lastAudit;
  StabilityReading? lastStability;

  void frame({
    bool faceDetected = true,
    double brightness = 140,
    double sharpness = 60,
    int boxLeft = 140,
    int boxTop = 190,
    int boxWidth = 200,
    int boxHeight = 260,
    double yaw = 0,
    double pitch = 0,
    double roll = 0,
    double leftEyeOpen = 0.95,
    double rightEyeOpen = 0.95,
    bool hasLeftEye = true,
    bool hasRightEye = true,
    bool hasNose = true,
    bool hasMouthLeft = true,
    bool hasMouthRight = true,
  }) {
    lastQuality = analyzer.analyze(QualityInput(
      faceDetected: faceDetected,
      brightness: brightness,
      sharpness: sharpness,
      boxWidth: boxWidth,
      boxHeight: boxHeight,
      boxLeft: boxLeft,
      boxTop: boxTop,
      frameWidth: 480,
      frameHeight: 640,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
      hasLeftEye: hasLeftEye,
      hasRightEye: hasRightEye,
    ));
    lastAudit = auditor.audit(
      hasLeftEye: hasLeftEye,
      hasRightEye: hasRightEye,
      hasNose: hasNose,
      hasMouthLeft: hasMouthLeft,
      hasMouthRight: hasMouthRight,
    );
    if (faceDetected) {
      lastStability = stability.record(StabilitySample.fromBox(
        left: boxLeft,
        top: boxTop,
        width: boxWidth,
        height: boxHeight,
        yaw: yaw,
        pitch: pitch,
        roll: roll,
      ));
      blink.record(math.min(leftEyeOpen, rightEyeOpen));
    } else {
      stability.reset();
    }
  }

  bool get captureReady =>
      (lastQuality?.accepted ?? false) &&
      stability.isReady &&
      blink.blinkDetected;
}

void main() {
  group('Face detection pipeline — happy path', () {
    test('still subject with a natural blink converges to capture-ready', () {
      final p = _Pipeline();
      // Two stable open frames…
      p.frame();
      p.frame();
      // …a blink (closed then open; landmarks still present)…
      p.frame(leftEyeOpen: 0.05, rightEyeOpen: 0.05);
      p.frame();
      // …then more stable frames to satisfy the 5-frame stability window.
      p.frame();
      p.frame();

      expect(p.lastQuality!.accepted, isTrue);
      expect(p.lastAudit!.path, AlignmentPath.fivePoint);
      expect(p.stability.isReady, isTrue);
      expect(p.blink.blinkDetected, isTrue);
      expect(p.captureReady, isTrue);
    });
  });

  group('Face detection pipeline — rejection paths', () {
    test('persistent darkness never reaches capture-ready', () {
      final p = _Pipeline();
      for (var i = 0; i < 8; i++) {
        p.frame(brightness: 25);
      }
      expect(p.lastQuality!.rejection, QualityRejection.tooDark);
      expect(p.captureReady, isFalse);
    });

    test('a moving subject never stabilises', () {
      final p = _Pipeline();
      for (var i = 0; i < 8; i++) {
        // Shift the box far each frame → every transition is unstable.
        p.frame(boxLeft: 60 + (i.isEven ? 0 : 160));
      }
      expect(p.stability.isReady, isFalse);
      expect(p.stability.unstableFrames, greaterThan(0));
      expect(p.captureReady, isFalse);
    });

    test('missing nose/mouth degrades to 2-point alignment fallback', () {
      final p = _Pipeline();
      p.frame(hasNose: false, hasMouthLeft: false, hasMouthRight: false);
      expect(p.lastAudit!.path, AlignmentPath.twoPoint);
      expect(p.lastAudit!.isFallback, isTrue);
    });

    test('losing the face resets stability progress', () {
      final p = _Pipeline();
      p.frame();
      p.frame();
      expect(p.stability.stableFrames, 2);
      p.frame(faceDetected: false); // face lost
      expect(p.stability.stableFrames, 0);
    });

    test('side face (extreme yaw) is rejected on quality', () {
      final p = _Pipeline();
      p.frame(yaw: 35);
      expect(p.lastQuality!.rejection, QualityRejection.extremePose);
      expect(p.captureReady, isFalse);
    });
  });
}
