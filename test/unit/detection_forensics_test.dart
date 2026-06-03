import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/detection_forensics.dart';
import 'package:nhai_auth/core/face_detection/face_stability_tracker.dart';
import 'package:nhai_auth/core/face_detection/landmark_audit.dart';

void main() {
  group('DetectionForensics string builders', () {
    test('[Detection] includes count, box, rotation and frame size', () {
      final s = DetectionForensics.detection(
        faces: 1,
        confidence: 0.91,
        boxLeft: 10,
        boxTop: 20,
        boxWidth: 100,
        boxHeight: 120,
        rotation: 270,
        frameWidth: 480,
        frameHeight: 640,
      );
      expect(s, startsWith('[Detection]'));
      expect(s, contains('faces=1'));
      expect(s, contains('box=100x120@(10,20)'));
      expect(s, contains('rotation=270'));
      expect(s, contains('frameSize=480x640'));
    });

    test('[Landmarks] renders points and nulls', () {
      final s = DetectionForensics.landmarks(
        leftEye: const [12.0, 34.0],
        rightEye: null,
      );
      expect(s, startsWith('[Landmarks]'));
      expect(s, contains('leftEye=(12.0,34.0)'));
      expect(s, contains('rightEye=null'));
    });

    test('[Pose] renders yaw/pitch/roll', () {
      final s = DetectionForensics.pose(yaw: -3.2, pitch: 5.0, roll: 1.1);
      expect(s, '[Pose] yaw=-3.2 pitch=5.0 roll=1.1');
    });

    test('[Blink] renders probabilities and flag', () {
      final s = DetectionForensics.blink(
          leftEyeOpen: 0.8, rightEyeOpen: 0.2, blinkDetected: true);
      expect(s, contains('leftEyeOpen=0.80'));
      expect(s, contains('blinkDetected=true'));
    });

    test('[Quality] and [Decision] explain accept/reject', () {
      final q = DetectionForensics.quality(
          brightness: 140, sharpness: 60, faceCoverage: 0.17, faceCentered: true, score: 88);
      expect(q, contains('brightness=140.0'));
      expect(q, contains('faceCentered=true'));
      final d = DetectionForensics.decision(accepted: false, reason: 'tooDark');
      expect(d, '[Decision] accepted=false reason=tooDark');
    });

    test('[Stability] renders deltas and counters', () {
      const r = StabilityReading(
        stable: false,
        ready: false,
        movement: 0.123,
        yawDelta: 7.0,
        pitchDelta: 2.0,
        rollDelta: 1.0,
        stableFrames: 0,
        unstableFrames: 3,
      );
      final s = DetectionForensics.stability(r);
      expect(s, contains('stable=false'));
      expect(s, contains('movement=0.123'));
      expect(s, contains('yawDelta=7.0'));
      expect(s, contains('unstableFrames=3'));
    });

    test('[LandmarkAudit] and [AlignmentFallback] reflect the audit', () {
      const auditor = LandmarkAuditor();
      final a = auditor.audit(
          hasLeftEye: true,
          hasRightEye: true,
          hasNose: false,
          hasMouthLeft: false,
          hasMouthRight: false);
      final audit = DetectionForensics.landmarkAudit(a);
      expect(audit, contains('nose=false'));
      expect(audit, contains('path=twoPoint'));
      final fb = DetectionForensics.alignmentFallback(a);
      expect(fb, startsWith('[AlignmentFallback] reason='));
      expect(fb, contains('2-point'));
    });
  });
}
