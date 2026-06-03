import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/face_stability_tracker.dart';

StabilitySample _s({
  double cx = 240,
  double cy = 320,
  double size = 283, // ~ diagonal of a 200x200 box
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
}) =>
    StabilitySample(
      centerX: cx,
      centerY: cy,
      boxSize: size,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
    );

void main() {
  group('FaceStabilityTracker', () {
    test('first sample is stable and seeds the baseline', () {
      final t = FaceStabilityTracker(requiredConsecutive: 3);
      final r = t.record(_s());
      expect(r.stable, isTrue);
      expect(r.movement, 0);
      expect(r.stableFrames, 1);
      expect(r.ready, isFalse);
    });

    test('N consecutive still frames reach ready', () {
      final t = FaceStabilityTracker(requiredConsecutive: 3);
      t.record(_s());
      t.record(_s(cx: 242)); // 2px move ≪ tolerance
      final r = t.record(_s(cx: 241));
      expect(r.stable, isTrue);
      expect(r.stableFrames, 3);
      expect(r.ready, isTrue);
      expect(t.isReady, isTrue);
    });

    test('a large positional jump is unstable and resets the counter', () {
      final t = FaceStabilityTracker(requiredConsecutive: 3);
      t.record(_s());
      t.record(_s(cx: 241));
      final jump = t.record(_s(cx: 360)); // 119px ≫ 0.06*283≈17px
      expect(jump.stable, isFalse);
      expect(jump.movement, greaterThan(t.maxMovement));
      expect(t.stableFrames, 0);
      expect(t.unstableFrames, 1);
      expect(jump.ready, isFalse);
    });

    test('a large yaw swing is unstable even when the box is still', () {
      final t = FaceStabilityTracker(requiredConsecutive: 3);
      t.record(_s(yaw: 0));
      final r = t.record(_s(yaw: 20)); // 20° ≫ 6° tolerance
      expect(r.stable, isFalse);
      expect(r.yawDelta, closeTo(20, 0.001));
    });

    test('pitch and roll deltas are tracked and gated', () {
      final t = FaceStabilityTracker(requiredConsecutive: 2);
      t.record(_s());
      final r = t.record(_s(pitch: 15, roll: 10));
      expect(r.stable, isFalse);
      expect(r.pitchDelta, closeTo(15, 0.001));
      expect(r.rollDelta, closeTo(10, 0.001));
    });

    test('reset clears all counters', () {
      final t = FaceStabilityTracker(requiredConsecutive: 2);
      t.record(_s());
      t.record(_s());
      expect(t.isReady, isTrue);
      t.reset();
      expect(t.stableFrames, 0);
      expect(t.unstableFrames, 0);
      expect(t.isReady, isFalse);
    });

    test('fromBox computes centre and diagonal', () {
      final s = StabilitySample.fromBox(
          left: 100, top: 100, width: 200, height: 200,
          yaw: 1, pitch: 2, roll: 3);
      expect(s.centerX, 200);
      expect(s.centerY, 200);
      expect(s.boxSize, closeTo(282.84, 0.1));
    });
  });
}
