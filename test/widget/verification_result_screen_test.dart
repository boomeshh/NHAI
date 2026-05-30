import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/ui/screens/verification_result_screen.dart';

import '../helpers/in_memory_storage.dart';

EmployeeRecord _employeeRecord() {
  return EmployeeRecord(
    employeeId: 'EMP001',
    name: 'Priya Sharma',
    department: 'Operations',
    embedding: FaceEmbedding(List.filled(128, 0.1)),
    enrolledAt: DateTime.utc(2026, 1, 1),
  );
}

Widget _buildApp({
  required InMemoryStorage storage,
  required AuthResult result,
}) {
  return MaterialApp(
    routes: {
      '/home': (_) => const Scaffold(body: Text('HomeScreen')),
      '/authenticate': (_) => const Scaffold(body: Text('AuthenticateScreen')),
    },
    home: VerificationResultScreen(
      storageManager: storage,
      result: result,
    ),
  );
}

Future<void> _pumpResult(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('VerificationResultScreen - verified state', () {
    testWidgets('renders all required verified fields', (tester) async {
      final storage = InMemoryStorage();
      await storage.saveEmployeeRecord(_employeeRecord());

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.verified,
            trustScore: 0.92,
            matchedEmployeeId: 'EMP001',
          ),
        ),
      );
      await _pumpResult(tester);

      expect(find.text('Identity Verified'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('EMP001'), findsOneWidget);
      expect(find.text('Operations'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Offline Active'), findsOneWidget);
    });

    testWidgets('uses the security green accent', (tester) async {
      final storage = InMemoryStorage();
      await storage.saveEmployeeRecord(_employeeRecord());

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.verified,
            trustScore: 0.88,
            matchedEmployeeId: 'EMP001',
          ),
        ),
      );
      await _pumpResult(tester);

      final accent = tester.widget<Container>(
        find.byKey(const Key('verified_accent')),
      );
      final decoration = accent.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, const Color(0xFF2E7D32));
    });
  });

  group('VerificationResultScreen - failed state', () {
    testWidgets('renders failed state, reason, mode, and actions',
        (tester) async {
      final storage = InMemoryStorage();

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.failed,
            trustScore: 0.31,
            failureReason: 'Face not recognized',
          ),
        ),
      );
      await _pumpResult(tester);

      expect(find.text('Authentication Failed'), findsOneWidget);
      expect(find.text('Face not recognized'), findsOneWidget);
      expect(find.text('Offline Active'), findsOneWidget);
      expect(find.byKey(const Key('try_again_button')), findsOneWidget);
      expect(find.byKey(const Key('return_home_button')), findsOneWidget);
    });

    testWidgets('uses the red failed accent', (tester) async {
      final storage = InMemoryStorage();

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.failed,
            trustScore: 0.2,
            failureReason: 'Liveness check failed',
          ),
        ),
      );
      await _pumpResult(tester);

      final accent = tester.widget<Container>(
        find.byKey(const Key('failed_accent')),
      );
      final decoration = accent.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, const Color(0xFFC62828));
    });
  });

  group('VerificationResultScreen - navigation and logging', () {
    testWidgets('logs the authentication attempt exactly once', (tester) async {
      final storage = InMemoryStorage();

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.failed,
            trustScore: 0.42,
            failureReason: 'Face not recognized',
          ),
        ),
      );
      await _pumpResult(tester);

      expect(storage.logAuthAttemptCallCount, 1);
      expect(storage.logs, hasLength(1));
      expect(storage.logs.single.result, AuthClassification.failed);
      expect(storage.logs.single.trustScore, 0.42);
      expect(storage.logs.single.failureReason, 'Face not recognized');
    });

    testWidgets('Try Again button navigates to authentication', (tester) async {
      final storage = InMemoryStorage();

      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.failed,
            trustScore: 0.12,
            failureReason: 'Face not recognized',
          ),
        ),
      );
      await _pumpResult(tester);

      await tester.tap(find.byKey(const Key('try_again_button')));
      await tester.pumpAndSettle();
      expect(find.text('AuthenticateScreen'), findsOneWidget);
    });

    testWidgets('Return Home button navigates home', (tester) async {
      final storage = InMemoryStorage();
      await tester.pumpWidget(
        _buildApp(
          storage: storage,
          result: const AuthResult(
            classification: AuthClassification.failed,
            trustScore: 0.12,
            failureReason: 'Face not recognized',
          ),
        ),
      );
      await _pumpResult(tester);

      await tester.tap(find.byKey(const Key('return_home_button')));
      await tester.pumpAndSettle();
      expect(find.text('HomeScreen'), findsOneWidget);
    });
  });
}
