import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/blink_reliability.dart';

void main() {
  const analyzer = BlinkReliabilityAnalyzer();

  group('BlinkReliabilityAnalyzer.detect', () {
    test('normal open→closed→open is detected', () {
      expect(
          analyzer.detect(
              const [0.95, 0.1, 0.95], const [0.95, 0.1, 0.95]),
          isTrue);
    });

    test('eyes that never clearly open are not detected', () {
      expect(analyzer.detect(const [0.2, 0.2, 0.2], const [0.2, 0.2, 0.2]),
          isFalse);
    });

    test('always-open eyes (no blink) are not detected', () {
      expect(analyzer.detect(const [0.95, 0.95, 0.95], const [0.95, 0.95, 0.95]),
          isFalse);
    });

    test('one-eye blink still drops the min and is detected', () {
      expect(
          analyzer.detect(
              const [0.95, 0.1, 0.95], const [0.95, 0.95, 0.95]),
          isTrue);
    });

    test('mid-range occlusion (never confirmed closed) is not detected', () {
      expect(analyzer.detect(const [0.95, 0.5, 0.95], const [0.95, 0.5, 0.95]),
          isFalse);
    });
  });

  group('BlinkReliabilityAnalyzer.run — standard battery', () {
    test('every standard case matches its expected outcome', () {
      final report = analyzer.run(BlinkReliabilityAnalyzer.standardCases());
      expect(report.total, 6);
      expect(report.failures, isEmpty,
          reason: 'detector misbehaved on: '
              '${report.failures.map((f) => f.name).join(", ")}');
      expect(report.reliability, 1.0);
    });

    test('report exposes detected vs expected per case and a CSV', () {
      final report = analyzer.run(BlinkReliabilityAnalyzer.standardCases());
      final normal = report.results.firstWhere((r) => r.name == 'normal');
      expect(normal.detected, isTrue);
      expect(normal.passed, isTrue);
      expect(report.toCsv(), contains('case,detected,expected,passed,note'));
      expect(report.toCsv(), contains('normal'));
    });
  });
}
