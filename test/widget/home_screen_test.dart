import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhai_auth/ui/screens/home_screen.dart';
import 'package:nhai_auth/ui/widgets/status_badge.dart';

/// Widget tests for HomeScreen.
///
/// Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
void main() {
  /// Helper: wrap [HomeScreen] in a [MaterialApp] with stub routes so that
  /// navigation calls do not throw.
  Widget buildTestApp() {
    return MaterialApp(
      initialRoute: '/home',
      routes: {
        '/home': (_) => const HomeScreen(),
        '/enroll': (_) => const Scaffold(body: Text('EnrollScreen')),
        '/authenticate': (_) => const Scaffold(body: Text('AuthenticateScreen')),
        '/logs': (_) => const Scaffold(body: Text('LogsScreen')),
      },
    );
  }

  // ── Button presence (Req 2.1) ──────────────────────────────────────────────

  group('HomeScreen — button presence (Req 2.1)', () {
    testWidgets('"Enroll Employee" button is visible', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      expect(find.byKey(const Key('enroll_employee_button')), findsOneWidget);
      expect(find.text('Enroll Employee'), findsOneWidget);
    });

    testWidgets('"Authenticate Employee" button is visible', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      expect(
        find.byKey(const Key('authenticate_employee_button')),
        findsOneWidget,
      );
      expect(find.text('Authenticate Employee'), findsOneWidget);
    });
  });

  // ── Offline badge visibility (Req 2.3) ────────────────────────────────────

  group('HomeScreen — offline badge (Req 2.3)', () {
    testWidgets('StatusBadge with "Offline Mode Active" text is visible',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // The StatusBadge widget itself must be present.
      expect(find.byType(StatusBadge), findsOneWidget);

      // The label text must be visible.
      expect(find.text('Offline Mode Active'), findsOneWidget);
    });
  });

  // ── Touch target sizes (Req 2.2) ──────────────────────────────────────────

  group('HomeScreen — touch target sizes (Req 2.2)', () {
    testWidgets(
        '"Enroll Employee" button has a rendered size of at least 48×48 dp',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      final enrollFinder = find.byKey(const Key('enroll_employee_button'));
      expect(enrollFinder, findsOneWidget);

      final size = tester.getSize(enrollFinder);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: 'Enroll button width must be ≥ 48 dp');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: 'Enroll button height must be ≥ 48 dp');
    });

    testWidgets(
        '"Authenticate Employee" button has a rendered size of at least 48×48 dp',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      final authFinder =
          find.byKey(const Key('authenticate_employee_button'));
      expect(authFinder, findsOneWidget);

      final size = tester.getSize(authFinder);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: 'Authenticate button width must be ≥ 48 dp');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: 'Authenticate button height must be ≥ 48 dp');
    });
  });

  // ── Navigation (Req 2.1, 2.4) ─────────────────────────────────────────────

  group('HomeScreen — navigation (Req 2.1, 2.4)', () {
    testWidgets('tapping "View Logs" button navigates to /logs', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.tap(find.byKey(const Key('view_logs_button')));
      await tester.pumpAndSettle();

      expect(find.text('LogsScreen'), findsOneWidget);
    });

    testWidgets('tapping "Enroll Employee" navigates to /enroll',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.tap(find.byKey(const Key('enroll_employee_button')));
      await tester.pumpAndSettle();

      expect(find.text('EnrollScreen'), findsOneWidget);
    });

    testWidgets('tapping "Authenticate Employee" navigates to /authenticate',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.tap(find.byKey(const Key('authenticate_employee_button')));
      await tester.pumpAndSettle();

      expect(find.text('AuthenticateScreen'), findsOneWidget);
    });
  });
}
