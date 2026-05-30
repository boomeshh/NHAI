// Unit tests for LivenessDetectorImpl
// Tests known EAR sequences (valid blink, too slow, never drops, recovers too
// late) and the 5-second timeout.
// Requirements: 7.3, 7.4

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_impl.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [CameraFrame] carrying the given eye landmarks.
CameraFrame frameWithLandmarks(List<List<double>> landmarks) => CameraFrame(
      bytes: const [1, 2, 3],
      width: 224,
      height: 224,
      sharpnessScore: 50.0,
      landmarks: landmarks,
    );

/// Builds a [CameraFrame] with no landmark data (face not detected).
CameraFrame frameWithoutLandmarks() => const CameraFrame(
      bytes: [1, 2, 3],
      width: 224,
      height: 224,
      sharpnessScore: 50.0,
    );

/// Constructs six eye landmark points that produce the given [ear] value.
///
/// Uses a simple geometry:
///   p1 = (0, 0), p4 = (1, 0)  → horizontal distance = 1.0
///   p2 and p6 are vertically separated by [ear] (v1 = ear)
///   p3 and p5 are vertically separated by [ear] (v2 = ear)
///
/// EAR = (v1 + v2) / (2 * horizontal) = (ear + ear) / (2 * 1.0) = ear
List<List<double>> landmarksForEar(double ear) {
  final v = ear; // each vertical distance = ear
  return [
    [0.0, 0.0],    // p1
    [0.25, v / 2], // p2
    [0.75, v / 2], // p3
    [1.0, 0.0],    // p4
    [0.75, -v / 2], // p5
    [0.25, -v / 2], // p6
  ];
}

/// Emits a stream of frames with the given EAR values.
Stream<CameraFrame> earStream(List<double> earValues) async* {
  for (final ear in earValues) {
    yield frameWithLandmarks(landmarksForEar(ear));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late LivenessDetectorImpl detector;

  setUp(() {
    detector = LivenessDetectorImpl();
  });

  // -------------------------------------------------------------------------
  // computeEar — unit tests
  // -------------------------------------------------------------------------

  group('computeEar', () {
    test('returns correct EAR for known geometry', () {
      const targetEar = 0.30;
      final landmarks = landmarksForEar(targetEar);
      final result = detector.computeEar(landmarks);
      expect(result, closeTo(targetEar, 1e-9));
    });

    test('returns 0.0 when horizontal distance is zero (degenerate frame)', () {
      final landmarks = [
        [0.0, 0.0], // p1
        [0.5, 0.3], // p2
        [0.5, 0.3], // p3
        [0.0, 0.0], // p4 == p1
        [0.5, -0.3], // p5
        [0.5, -0.3], // p6
      ];
      expect(detector.computeEar(landmarks), equals(0.0));
    });

    test('returns 0.0 for fully closed eye (vertical distances = 0)', () {
      final landmarks = [
        [0.0, 0.0],
        [0.25, 0.0],
        [0.75, 0.0],
        [1.0, 0.0],
        [0.75, 0.0],
        [0.25, 0.0],
      ];
      expect(detector.computeEar(landmarks), closeTo(0.0, 1e-9));
    });

    test('EAR is symmetric — swapping upper and lower landmarks gives same result', () {
      final landmarks = landmarksForEar(0.28);
      // Swap p2↔p6 and p3↔p5 (upper ↔ lower)
      final swapped = [
        landmarks[0], // p1
        landmarks[5], // p6 in place of p2
        landmarks[4], // p5 in place of p3
        landmarks[3], // p4
        landmarks[2], // p3 in place of p5
        landmarks[1], // p2 in place of p6
      ];
      expect(
        detector.computeEar(swapped),
        closeTo(detector.computeEar(landmarks), 1e-9),
      );
    });
  });

  // -------------------------------------------------------------------------
  // processEarSequence — unit tests
  // -------------------------------------------------------------------------

  group('processEarSequence', () {
    test('confirms blink: EAR drops below 0.25 then recovers within 400 ms', () {
      // At 33 ms/frame: frames 0–2 open (0.35), frame 3 closed (0.20),
      // frame 4 open (0.35) → elapsed since close = 33 ms ≤ 400 ms → confirmed
      final earValues = [0.35, 0.35, 0.35, 0.20, 0.35];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('fails when EAR never drops below threshold', () {
      final earValues = List.filled(200, 0.35);
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('fails when EAR drops but never recovers within timeout', () {
      final earValues = List.filled(200, 0.10);
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('fails when recovery takes longer than 400 ms (too slow)', () {
      // At 33 ms/frame: close at frame 0, reopen at frame 13
      // elapsed = 13 * 33 = 429 ms > 400 ms → not a valid blink
      final earValues = [
        0.20, // frame 0: closed
        ...List.filled(12, 0.20), // frames 1–12: still closed
        0.35, // frame 13: reopens at 429 ms → too late
        ...List.filled(100, 0.35),
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('confirms blink exactly at 400 ms boundary', () {
      // At 33 ms/frame: close at frame 0, reopen at frame 12
      // elapsed = 12 * 33 = 396 ms ≤ 400 ms → valid blink
      final earValues = [
        0.20, // frame 0: closed
        ...List.filled(11, 0.20), // frames 1–11: still closed
        0.35, // frame 12: reopens at 396 ms → valid
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('ignores frames beyond the 5-second timeout', () {
      // Valid blink occurs at frame 200 (200 * 33 ms = 6600 ms > 5000 ms)
      // → should be ignored → failed
      final earValues = [
        ...List.filled(200, 0.35), // 0–199: open (beyond 5 s)
        0.20, // frame 200: closed (beyond timeout)
        0.35, // frame 201: open
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('confirms blink just before 5-second timeout', () {
      // At 33 ms/frame: 5000 ms / 33 ms ≈ 151 frames
      // Blink at frame 148 (close) and 149 (open) → within timeout
      final earValues = [
        ...List.filled(148, 0.35), // open
        0.20, // frame 148: closed
        0.35, // frame 149: open → 33 ms elapsed → confirmed
        ...List.filled(10, 0.35),
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('resets state after eye stays closed too long and detects next blink', () {
      // First "blink" is too slow (eye stays closed > 400 ms), then a valid
      // blink follows.
      final earValues = [
        0.20, // frame 0: closed
        ...List.filled(13, 0.20), // frames 1–13: still closed (> 400 ms)
        0.35, // frame 14: open (reset triggered at frame 13)
        0.20, // frame 15: closed again
        0.35, // frame 16: open → 33 ms → confirmed
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('empty EAR sequence returns failed', () {
      expect(
        detector.processEarSequence([]),
        equals(LivenessResult.failed),
      );
    });

    test('single frame below threshold returns failed (no recovery)', () {
      expect(
        detector.processEarSequence([0.20]),
        equals(LivenessResult.failed),
      );
    });
  });

  // -------------------------------------------------------------------------
  // detectLiveness — integration tests using Stream<CameraFrame>
  // -------------------------------------------------------------------------

  group('detectLiveness', () {
    test('returns confirmed when stream contains a valid blink', () async {
      final frames = earStream([0.35, 0.35, 0.20, 0.35]);
      final result = await detector.detectLiveness(frames);
      expect(result, equals(LivenessResult.confirmed));
    });

    test('returns failed when stream has no blink (all open)', () async {
      final frames = earStream(List.filled(10, 0.35));
      final result = await detector.detectLiveness(frames);
      expect(result, equals(LivenessResult.failed));
    });

    test('returns failed when stream has no blink (all closed)', () async {
      final frames = earStream(List.filled(10, 0.10));
      final result = await detector.detectLiveness(frames);
      expect(result, equals(LivenessResult.failed));
    });

    test('skips frames without landmark data', () async {
      final controller = StreamController<CameraFrame>();
      final future = detector.detectLiveness(controller.stream);

      controller.add(frameWithoutLandmarks()); // skipped
      controller.add(frameWithLandmarks(landmarksForEar(0.35))); // open
      controller.add(frameWithoutLandmarks()); // skipped
      controller.add(frameWithLandmarks(landmarksForEar(0.20))); // closed
      controller.add(frameWithLandmarks(landmarksForEar(0.35))); // open
      await controller.close();

      expect(await future, equals(LivenessResult.confirmed));
    });

    test('returns failed when stream is empty', () async {
      final frames = const Stream<CameraFrame>.empty();
      final result = await detector.detectLiveness(frames);
      expect(result, equals(LivenessResult.failed));
    });

    test('returns confirmed early without consuming entire stream', () async {
      final earValues = [
        0.35, 0.35, 0.20, 0.35, // blink at frames 2–3
        ...List.filled(1000, 0.35), // many more frames
      ];
      final result = await detector.detectLiveness(earStream(earValues));
      expect(result, equals(LivenessResult.confirmed));
    });

    test('5-second timeout: stream that never ends resolves with failed',
        () async {
      Stream<CameraFrame> infiniteOpenEyes() async* {
        while (true) {
          yield frameWithLandmarks(landmarksForEar(0.35));
          await Future.delayed(Duration.zero);
        }
      }

      final result = await detector
          .detectLiveness(infiniteOpenEyes())
          .timeout(const Duration(seconds: 10));

      expect(result, equals(LivenessResult.failed));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
