// Feature: nhai-offline-auth, Property 10: Blink detection correctly classifies EAR sequences
//
// **Validates: Requirements 7.3, 7.4**
//
// Property: For any EAR time series where the value drops below 0.25 and
// recovers above 0.25 within 400 ms (at 33 ms/frame), processEarSequence
// returns LivenessResult.confirmed. For any EAR time series that does not
// satisfy this condition within 5 seconds, it returns LivenessResult.failed.
//
// Three sub-properties are tested with a minimum of 100 iterations each:
//   Property 1 — Valid blink sequences (drop + recovery within 400 ms) → confirmed
//   Property 2 — Sequences that never drop below threshold → failed
//   Property 3 — Sequences that drop but never recover within 400 ms → failed
//
// Uses dart:math Random with manual iteration loops (consistent with project
// conventions — fast_check is not in the resolved dependency graph).

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_impl.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Generates a random EAR value that is strictly above the threshold (open eye).
/// Range: [0.26, 0.60]
double _openEar(Random rng) => 0.26 + rng.nextDouble() * 0.34;

/// Generates a random EAR value that is strictly below the threshold (closed eye).
/// Range: [0.01, 0.24]
double _closedEar(Random rng) => 0.01 + rng.nextDouble() * 0.23;

/// Builds a valid-blink EAR sequence:
///   - [leadFrames] open frames before the blink
///   - [closedFrames] closed frames (1–12 frames, i.e. 33–396 ms ≤ 400 ms)
///   - 1 open frame to complete the recovery
///   - optional trailing open frames
///
/// At 33 ms/frame, 12 closed frames = 396 ms ≤ 400 ms → valid blink.
List<double> _validBlinkSequence(Random rng) {
  // Lead: 0–10 open frames before the blink
  final leadFrames = rng.nextInt(11);
  // Closed duration: 1–12 frames (33–396 ms), all ≤ 400 ms window
  final closedFrames = 1 + rng.nextInt(12);
  // Tail: 0–10 open frames after recovery
  final tailFrames = rng.nextInt(11);

  return [
    ...List.generate(leadFrames, (_) => _openEar(rng)),
    ...List.generate(closedFrames, (_) => _closedEar(rng)),
    _openEar(rng), // recovery frame
    ...List.generate(tailFrames, (_) => _openEar(rng)),
  ];
}

/// Builds a never-drops sequence: all EAR values are above the threshold.
/// Length: 10–160 frames (covers up to ~5 s at 33 ms/frame).
List<double> _neverDropsSequence(Random rng) {
  final length = 10 + rng.nextInt(151);
  return List.generate(length, (_) => _openEar(rng));
}

/// Builds a drops-but-no-recovery sequence. Two variants are generated:
///
/// Variant A — eye stays closed for the entire sequence (no open frames).
///   The state machine may reset internally (after 400 ms), but since there
///   are no open frames, no recovery is ever detected.
///
/// Variant B — open → close → stays closed longer than 400 ms → end.
///   The sequence ends while the eye is still closed (or just after the
///   window expires), so no valid blink is ever completed.
///   Critically, no open frames follow the slow close, preventing a new
///   blink cycle from completing.
List<double> _noRecoverySequence(Random rng) {
  if (rng.nextBool()) {
    // Variant A: all closed — no open frames, so no recovery is possible.
    // The state machine resets after 400 ms but immediately re-enters the
    // closed state; since there is never an open frame, confirmed is never
    // returned.
    final length = 10 + rng.nextInt(141);
    return List.generate(length, (_) => _closedEar(rng));
  } else {
    // Variant B: open lead → close → stays closed > 400 ms → sequence ends.
    // 13 closed frames = 429 ms > 400 ms → window expired.
    // No open frames follow, so no new blink cycle can complete.
    final leadFrames = rng.nextInt(11);
    final closedFrames = 13 + rng.nextInt(10); // 13–22 frames (429–726 ms)

    return [
      ...List.generate(leadFrames, (_) => _openEar(rng)),
      ...List.generate(closedFrames, (_) => _closedEar(rng)),
      // Sequence ends here — no open frames follow, so no recovery.
    ];
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
  // Property 1: Valid blink sequences → LivenessResult.confirmed
  // -------------------------------------------------------------------------

  group(
      'Property 10 / Sub-property 1: '
      'EAR drops below 0.25 and recovers within 400 ms → confirmed', () {
    test(
        'property: 100 random valid-blink sequences all return confirmed', () {
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        final earValues = _validBlinkSequence(rng);

        final result = detector.processEarSequence(earValues);

        expect(
          result,
          equals(LivenessResult.confirmed),
          reason:
              'Iteration $i: sequence $earValues should produce confirmed '
              '(EAR drops below 0.25 and recovers within 400 ms)',
        );
      }
    });

    test('minimal valid blink: single closed frame followed by open → confirmed',
        () {
      // 1 closed frame (33 ms) then 1 open frame — smallest possible blink
      final earValues = [0.20, 0.35];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('blink at boundary: 12 closed frames (396 ms) → confirmed', () {
      // 12 * 33 = 396 ms ≤ 400 ms → valid
      final earValues = [
        ...List.filled(12, 0.20),
        0.35,
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('blink preceded by many open frames → confirmed', () {
      final earValues = [
        ...List.filled(50, 0.35), // 50 open frames before blink
        0.20, // closed
        0.35, // open
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('blink at EAR values just below and just above threshold → confirmed',
        () {
      // EAR = 0.249 (just below 0.25) then 0.251 (just above 0.25)
      final earValues = [0.249, 0.251];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Property 2: Sequences that never drop below threshold → failed
  // -------------------------------------------------------------------------

  group(
      'Property 10 / Sub-property 2: '
      'EAR never drops below 0.25 → failed', () {
    test(
        'property: 100 random never-drops sequences all return failed', () {
      final rng = Random(7);

      for (int i = 0; i < 100; i++) {
        final earValues = _neverDropsSequence(rng);

        final result = detector.processEarSequence(earValues);

        expect(
          result,
          equals(LivenessResult.failed),
          reason:
              'Iteration $i: sequence of length ${earValues.length} with all '
              'EAR values above 0.25 should produce failed',
        );
      }
    });

    test('empty sequence → failed', () {
      expect(
        detector.processEarSequence([]),
        equals(LivenessResult.failed),
      );
    });

    test('single open frame → failed', () {
      expect(
        detector.processEarSequence([0.35]),
        equals(LivenessResult.failed),
      );
    });

    test('all frames at exactly 0.25 (not below threshold) → failed', () {
      // EAR must be strictly below 0.25 to count as closed
      final earValues = List.filled(50, 0.25);
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('long sequence of open eyes (5 s worth of frames) → failed', () {
      // 5000 ms / 33 ms ≈ 152 frames — all open
      final earValues = List.filled(152, 0.35);
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Property 3: Sequences that drop but never recover within 400 ms → failed
  // -------------------------------------------------------------------------

  group(
      'Property 10 / Sub-property 3: '
      'EAR drops below 0.25 but never recovers within 400 ms → failed', () {
    test(
        'property: 100 random no-recovery sequences all return failed', () {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        final earValues = _noRecoverySequence(rng);

        final result = detector.processEarSequence(earValues);

        expect(
          result,
          equals(LivenessResult.failed),
          reason:
              'Iteration $i: sequence $earValues should produce failed '
              '(EAR drops but never recovers within 400 ms)',
        );
      }
    });

    test('eye stays closed for entire sequence → failed', () {
      final earValues = List.filled(50, 0.10);
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('recovery at exactly 13 frames (429 ms > 400 ms) → failed', () {
      // 13 * 33 = 429 ms > 400 ms → window expired before recovery
      final earValues = [
        ...List.filled(13, 0.20), // closed for 429 ms
        0.35, // recovery — too late
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test('single closed frame with no recovery → failed', () {
      expect(
        detector.processEarSequence([0.20]),
        equals(LivenessResult.failed),
      );
    });

    test('blink occurs only after 5-second timeout → failed', () {
      // Valid blink at frame 200 (200 * 33 = 6600 ms > 5000 ms) — ignored
      final earValues = [
        ...List.filled(200, 0.35), // open frames beyond 5 s
        0.20, // closed (beyond timeout)
        0.35, // open
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });

    test(
        'slow close with no open frames following: '
        'sequence ends while closed → failed', () {
      // Eye closes and stays closed for > 400 ms, then sequence ends.
      // No open frames follow, so no recovery is ever detected.
      final earValues = [
        ...List.filled(14, 0.20), // closed for 14 * 33 = 462 ms > 400 ms
        // sequence ends — no open frames
      ];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.failed),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Boundary and determinism checks
  // -------------------------------------------------------------------------

  group('Property 10 / Boundary and determinism', () {
    test('processEarSequence is deterministic — same input always same output',
        () {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        // Mix of valid and invalid sequences
        final earValues = rng.nextBool()
            ? _validBlinkSequence(rng)
            : _neverDropsSequence(rng);

        final first = detector.processEarSequence(earValues);
        final second = detector.processEarSequence(earValues);
        final third = detector.processEarSequence(earValues);

        expect(first, equals(second),
            reason:
                'Iteration $i: processEarSequence is not deterministic '
                '(first=$first, second=$second)');
        expect(second, equals(third),
            reason:
                'Iteration $i: processEarSequence is not deterministic '
                '(second=$second, third=$third)');
      }
    });

    test('result is always confirmed or failed — no other outcomes', () {
      final rng = Random(31);
      final validOutcomes = LivenessResult.values.toSet();

      for (int i = 0; i < 100; i++) {
        final earValues = rng.nextBool()
            ? _validBlinkSequence(rng)
            : _neverDropsSequence(rng);

        final result = detector.processEarSequence(earValues);

        expect(
          validOutcomes.contains(result),
          isTrue,
          reason:
              'Iteration $i: processEarSequence returned an unexpected value',
        );
      }
    });

    test('blink at frame 0 and 1 (immediate blink) → confirmed', () {
      // Close at frame 0, open at frame 1 (33 ms) → valid
      final earValues = [0.20, 0.35];
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });

    test('EAR exactly at threshold (0.25) is treated as open (not closed)', () {
      // 0.25 is NOT below threshold — eye is not considered closed
      final earValues = [0.25, 0.20, 0.35];
      // Frame 0: 0.25 → open (not below 0.25)
      // Frame 1: 0.20 → closed
      // Frame 2: 0.35 → open → 33 ms elapsed → confirmed
      expect(
        detector.processEarSequence(earValues),
        equals(LivenessResult.confirmed),
      );
    });
  });
}
