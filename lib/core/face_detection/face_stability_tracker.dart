/// Pure-Dart geometric stability tracking for the NHAI detection pipeline.
///
/// Distinct from the validity-counting `FrameStabilityTracker` in
/// `core/validation/biometric_validation.dart` (which counts consecutive
/// *valid* frames): this tracker measures *motion* — how much the face box and
/// head angles move between consecutive frames — and only counts a frame as
/// "stable" when that motion is below tolerance. Capture should wait for N
/// consecutive stable frames so the embedding is taken from a still subject.
library;

import 'dart:math' as math;

/// One frame's geometric sample: face-box centre, box size, and head angles.
class StabilitySample {
  final double centerX;
  final double centerY;

  /// A scalar size for the box (e.g. its diagonal) used to normalize motion so
  /// the tolerance is resolution/distance independent.
  final double boxSize;

  final double yaw;
  final double pitch;
  final double roll;

  const StabilitySample({
    required this.centerX,
    required this.centerY,
    required this.boxSize,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  /// Builds a sample from a bounding box (pixels) and head angles (degrees).
  factory StabilitySample.fromBox({
    required int left,
    required int top,
    required int width,
    required int height,
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    return StabilitySample(
      centerX: left + width / 2.0,
      centerY: top + height / 2.0,
      boxSize: math.sqrt(width * width + height * height.toDouble()),
      yaw: yaw,
      pitch: pitch,
      roll: roll,
    );
  }
}

/// The per-frame stability reading produced by [FaceStabilityTracker.record].
class StabilityReading {
  /// Whether this frame's motion was within tolerance.
  final bool stable;

  /// Whether enough consecutive stable frames have now accumulated.
  final bool ready;

  /// Normalized centre movement since the previous frame (0 = no motion).
  final double movement;

  /// Absolute angle deltas (degrees) since the previous frame.
  final double yawDelta;
  final double pitchDelta;
  final double rollDelta;

  /// Consecutive stable frames including this one.
  final int stableFrames;

  /// Total frames seen that were classed unstable (cumulative).
  final int unstableFrames;

  const StabilityReading({
    required this.stable,
    required this.ready,
    required this.movement,
    required this.yawDelta,
    required this.pitchDelta,
    required this.rollDelta,
    required this.stableFrames,
    required this.unstableFrames,
  });
}

/// Tracks frame-to-frame motion and requires [requiredConsecutive] stable
/// frames before [StabilityReading.ready] is true. Any frame whose motion
/// exceeds tolerance resets the consecutive counter to zero.
class FaceStabilityTracker {
  /// Stable frames required before capture is allowed.
  final int requiredConsecutive;

  /// Max normalized centre movement for a frame to count as stable.
  /// (Movement is centre displacement divided by box size.)
  final double maxMovement;

  /// Max per-axis angle change (degrees) for a frame to count as stable.
  final double maxYawDelta;
  final double maxPitchDelta;
  final double maxRollDelta;

  StabilitySample? _prev;
  int _stable = 0;
  int _unstable = 0;

  FaceStabilityTracker({
    this.requiredConsecutive = 5,
    this.maxMovement = 0.06,
    this.maxYawDelta = 6.0,
    this.maxPitchDelta = 6.0,
    this.maxRollDelta = 6.0,
  });

  int get stableFrames => _stable;
  int get unstableFrames => _unstable;
  bool get isReady => _stable >= requiredConsecutive;

  /// Feeds one geometric sample and returns the resulting reading.
  ///
  /// The very first sample (no predecessor) is treated as stable-with-zero-
  /// motion: it seeds the baseline and counts as the first stable frame.
  StabilityReading record(StabilitySample s) {
    final prev = _prev;
    _prev = s;

    if (prev == null) {
      _stable = 1;
      return StabilityReading(
        stable: true,
        ready: isReady,
        movement: 0,
        yawDelta: 0,
        pitchDelta: 0,
        rollDelta: 0,
        stableFrames: _stable,
        unstableFrames: _unstable,
      );
    }

    final double dx = s.centerX - prev.centerX;
    final double dy = s.centerY - prev.centerY;
    final double size = s.boxSize <= 0 ? 1 : s.boxSize;
    final double movement = math.sqrt(dx * dx + dy * dy) / size;
    final double yawDelta = (s.yaw - prev.yaw).abs();
    final double pitchDelta = (s.pitch - prev.pitch).abs();
    final double rollDelta = (s.roll - prev.roll).abs();

    final bool stable = movement <= maxMovement &&
        yawDelta <= maxYawDelta &&
        pitchDelta <= maxPitchDelta &&
        rollDelta <= maxRollDelta;

    if (stable) {
      _stable++;
    } else {
      _stable = 0;
      _unstable++;
    }

    return StabilityReading(
      stable: stable,
      ready: isReady,
      movement: movement,
      yawDelta: yawDelta,
      pitchDelta: pitchDelta,
      rollDelta: rollDelta,
      stableFrames: _stable,
      unstableFrames: _unstable,
    );
  }

  /// Clears all state (call when the face is lost or a new capture begins).
  void reset() {
    _prev = null;
    _stable = 0;
    _unstable = 0;
  }
}
