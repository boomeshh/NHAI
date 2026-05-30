import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/ui/screens/local_logs_screen.dart';

import '../helpers/in_memory_storage.dart';

AuthLogEntry _entry({
  required String id,
  required DateTime timestamp,
  required AuthClassification result,
  required double trustScore,
  String? employeeId,
  String? failureReason,
}) {
  return AuthLogEntry(
    id: id,
    timestamp: timestamp,
    result: result,
    trustScore: trustScore,
    employeeId: employeeId,
    failureReason: failureReason,
  );
}

Widget _buildApp(InMemoryStorage storage) {
  return MaterialApp(
    home: LocalLogsScreen(storageManager: storage),
  );
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('LocalLogsScreen', () {
    testWidgets('fetches logs with limit 100 and renders entries',
        (tester) async {
      final storage = InMemoryStorage();
      await storage.logAuthAttempt(
        _entry(
          id: '1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          result: AuthClassification.verified,
          trustScore: 0.91,
          employeeId: 'EMP001',
        ),
      );

      await tester.pumpWidget(_buildApp(storage));
      await _pumpLoaded(tester);

      expect(storage.getAuthLogsCallCount, 1);
      expect(storage.lastRequestedLimit, 100);
      expect(find.byKey(const Key('auth_logs_list')), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('Employee ID: EMP001'), findsOneWidget);
    });

    testWidgets('displays entries in reverse chronological order',
        (tester) async {
      final storage = InMemoryStorage();
      await storage.logAuthAttempt(
        _entry(
          id: 'old',
          timestamp: DateTime.utc(2026, 1, 1, 9),
          result: AuthClassification.failed,
          trustScore: 0.21,
          failureReason: 'Old failure',
        ),
      );
      await storage.logAuthAttempt(
        _entry(
          id: 'new',
          timestamp: DateTime.utc(2026, 1, 1, 11),
          result: AuthClassification.verified,
          trustScore: 0.94,
          employeeId: 'EMP002',
        ),
      );
      await storage.logAuthAttempt(
        _entry(
          id: 'middle',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          result: AuthClassification.failed,
          trustScore: 0.35,
          failureReason: 'Middle failure',
        ),
      );

      await tester.pumpWidget(_buildApp(storage));
      await _pumpLoaded(tester);

      final newest = find.text(DateTime.utc(2026, 1, 1, 11).toIso8601String());
      final middle = find.text(DateTime.utc(2026, 1, 1, 10).toIso8601String());
      final oldest = find.text(DateTime.utc(2026, 1, 1, 9).toIso8601String());

      expect(
          tester.getTopLeft(newest).dy, lessThan(tester.getTopLeft(middle).dy));
      expect(
          tester.getTopLeft(middle).dy, lessThan(tester.getTopLeft(oldest).dy));
    });

    testWidgets('renders up to 100 entries', (tester) async {
      final storage = InMemoryStorage();
      for (int i = 0; i < 120; i++) {
        await storage.logAuthAttempt(
          _entry(
            id: 'log-$i',
            timestamp: DateTime.utc(2026, 1, 1, 0, i),
            result: i.isEven
                ? AuthClassification.verified
                : AuthClassification.failed,
            trustScore: i / 120,
            employeeId: i.isEven ? 'EMP$i' : null,
            failureReason: i.isEven ? null : 'No match',
          ),
        );
      }

      await tester.pumpWidget(_buildApp(storage));
      await _pumpLoaded(tester);

      expect(find.byKey(const Key('auth_log_entry_0')), findsOneWidget);
      expect(find.byKey(const Key('auth_log_entry_99')), findsOneWidget);
      expect(find.byKey(const Key('auth_log_entry_100')), findsNothing);
    });

    testWidgets('shows empty state when no logs exist', (tester) async {
      final storage = InMemoryStorage();

      await tester.pumpWidget(_buildApp(storage));
      await _pumpLoaded(tester);

      expect(find.byKey(const Key('logs_empty_state')), findsOneWidget);
      expect(find.text('No authentication logs yet.'), findsOneWidget);
    });
  });
}
