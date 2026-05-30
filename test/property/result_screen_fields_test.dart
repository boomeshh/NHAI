import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/ui/screens/verification_result_screen.dart';

import '../helpers/in_memory_storage.dart';

EmployeeRecord _recordFor(int i) {
  return EmployeeRecord(
    employeeId: 'EMP${i.toString().padLeft(3, '0')}',
    name: 'Employee $i',
    department: 'Department ${i % 7}',
    embedding: FaceEmbedding(List.filled(128, i / 100.0)),
    enrolledAt: DateTime.utc(2026, 1, 1, 0, i % 60),
  );
}

Widget _screen(InMemoryStorage storage, AuthResult result) {
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

void main() {
  group('Property 11: Result screen displays required fields', () {
    testWidgets('property: verified and failed AuthResult cases are complete',
        (tester) async {
      final storage = InMemoryStorage();

      for (int i = 0; i < 100; i++) {
        final isVerified = i.isEven;
        final score = ((i % 101) / 100).clamp(0.0, 1.0).toDouble();

        if (isVerified) {
          final record = _recordFor(i);
          await storage.saveEmployeeRecord(record);
          await tester.pumpWidget(
            _screen(
              storage,
              AuthResult(
                classification: AuthClassification.verified,
                trustScore: score,
                matchedEmployeeId: record.employeeId,
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text('Identity Verified'), findsOneWidget);
          expect(find.text(record.name), findsOneWidget);
          expect(find.text(record.employeeId), findsOneWidget);
          expect(find.text(record.department), findsOneWidget);
          expect(find.text('${(score * 100).round()}%'), findsOneWidget);
          expect(find.text('Confirmed'), findsOneWidget);
          expect(find.text('Offline Active'), findsOneWidget);
        } else {
          final reason = 'Failure reason $i';
          await tester.pumpWidget(
            _screen(
              storage,
              AuthResult(
                classification: AuthClassification.failed,
                trustScore: score,
                failureReason: reason,
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text('Authentication Failed'), findsOneWidget);
          expect(find.text(reason), findsOneWidget);
          expect(find.text('Offline Active'), findsOneWidget);
        }

        expect(find.byKey(const Key('try_again_button')), findsOneWidget);
        expect(find.byKey(const Key('return_home_button')), findsOneWidget);
      }
    });
  });
}
