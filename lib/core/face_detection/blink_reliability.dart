/// Pure-Dart blink-detector reliability harness.
///
/// Exercises the production [BlinkLivenessTracker] (the same Open→Closed→Open
/// state machine wired into the authentication gate) against a battery of
/// scripted eye-open-probability sequences and reports, per case, whether the
/// detector's verdict matched the expected outcome. Produces an aggregate
/// reliability figure for the Phase-8 report.
///
/// This module only *evaluates* the existing detector — it does not change the
/// detector, its thresholds, or the liveness logic.
library;

import 'dart:math' as math;

import '../validation/biometric_validation.dart';

/// One scripted blink scenario. [leftSeq]/[rightSeq] are per-frame eye-open
/// probabilities (0–1). The tracker is driven with the per-frame minimum of
/// the two eyes (matching how the gate feeds `minEyeOpen`).
class BlinkCase {
  final String name;
  final List<double> leftSeq;
  final List<double> rightSeq;

  /// Whether a correct detector SHOULD report a blink for this sequence.
  final bool expectedDetected;

  /// Short description of what the case simulates.
  final String note;

  const BlinkCase({
    required this.name,
    required this.leftSeq,
    required this.rightSeq,
    required this.expectedDetected,
    required this.note,
  });
}

/// Outcome of running one [BlinkCase].
class BlinkCaseResult {
  final String name;
  final bool detected;
  final bool expectedDetected;
  final String note;

  BlinkCaseResult({
    required this.name,
    required this.detected,
    required this.expectedDetected,
    required this.note,
  });

  /// The detector behaved as expected for this case.
  bool get passed => detected == expectedDetected;
}

/// Aggregate report over a battery of [BlinkCase]s.
class BlinkReliabilityReport {
  final List<BlinkCaseResult> results;

  BlinkReliabilityReport(this.results);

  int get total => results.length;
  int get correct => results.where((r) => r.passed).length;

  /// Fraction of cases where the detector matched the expected outcome (0–1).
  double get reliability => total == 0 ? 0 : correct / total;

  /// Cases the detector got wrong (false accept or false reject).
  List<BlinkCaseResult> get failures =>
      results.where((r) => !r.passed).toList();

  String toCsv() {
    final b = StringBuffer('case,detected,expected,passed,note\n');
    for (final r in results) {
      b.writeln(
          '${r.name},${r.detected},${r.expectedDetected},${r.passed},"${r.note}"');
    }
    return b.toString();
  }
}

/// Runs blink cases through a fresh [BlinkLivenessTracker] each time.
class BlinkReliabilityAnalyzer {
  const BlinkReliabilityAnalyzer();

  /// Drives a fresh tracker with min(left,right) per frame and returns whether
  /// a blink was detected across the whole sequence.
  bool detect(List<double> leftSeq, List<double> rightSeq) {
    final tracker = BlinkLivenessTracker();
    final int n = math.max(leftSeq.length, rightSeq.length);
    for (int i = 0; i < n; i++) {
      final double l = i < leftSeq.length ? leftSeq[i] : leftSeq.last;
      final double r = i < rightSeq.length ? rightSeq[i] : rightSeq.last;
      tracker.record(math.min(l, r));
      if (tracker.blinkDetected) return true;
    }
    return tracker.blinkDetected;
  }

  BlinkReliabilityReport run(List<BlinkCase> cases) {
    final results = <BlinkCaseResult>[];
    for (final c in cases) {
      final detected = detect(c.leftSeq, c.rightSeq);
      results.add(BlinkCaseResult(
        name: c.name,
        detected: detected,
        expectedDetected: c.expectedDetected,
        note: c.note,
      ));
    }
    return BlinkReliabilityReport(results);
  }

  /// The standard NHAI blink battery: normal / slow / fast / one-eye blinks
  /// (must detect) plus eyes-hidden / partially-covered (must reject).
  static List<BlinkCase> standardCases() => const [
        BlinkCase(
          name: 'normal',
          leftSeq: [0.95, 0.92, 0.10, 0.08, 0.93, 0.96],
          rightSeq: [0.95, 0.92, 0.10, 0.08, 0.93, 0.96],
          expectedDetected: true,
          note: 'open→closed→open at ~30fps',
        ),
        BlinkCase(
          name: 'slow',
          leftSeq: [0.95, 0.9, 0.1, 0.1, 0.1, 0.1, 0.1, 0.92, 0.95],
          rightSeq: [0.95, 0.9, 0.1, 0.1, 0.1, 0.1, 0.1, 0.92, 0.95],
          expectedDetected: true,
          note: 'eyes held closed longer then reopen',
        ),
        BlinkCase(
          name: 'fast',
          leftSeq: [0.95, 0.08, 0.95],
          rightSeq: [0.95, 0.08, 0.95],
          expectedDetected: true,
          note: 'single-frame closure',
        ),
        BlinkCase(
          name: 'one-eye',
          leftSeq: [0.95, 0.08, 0.95],
          rightSeq: [0.95, 0.95, 0.95],
          expectedDetected: true,
          note: 'left eye blinks, right stays open (min drops)',
        ),
        BlinkCase(
          name: 'eyes-hidden',
          leftSeq: [0.2, 0.2, 0.2, 0.2, 0.2],
          rightSeq: [0.2, 0.2, 0.2, 0.2, 0.2],
          expectedDetected: false,
          note: 'eyes never clearly open — no valid baseline',
        ),
        BlinkCase(
          name: 'partially-covered',
          leftSeq: [0.95, 0.55, 0.5, 0.55, 0.95],
          rightSeq: [0.95, 0.55, 0.5, 0.55, 0.95],
          expectedDetected: false,
          note: 'occlusion keeps prob mid-range — never confirmed closed',
        ),
      ];
}
