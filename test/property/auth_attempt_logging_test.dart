import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/ui/screens/verification_result_screen.dart';

import '../helpers/in_memory_storage.dart';

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
  group('Property 12: Authentication attempt is always logged', () {
    testWidgets('property: every result logs one matching entry',
        (tester) async {
      final storage = InMemoryStorage();

      for (int i = 0; i < 100; i++) {
        final isVerified = i % 3 == 0;
        final score = (i / 100).clamp(0.0, 1.0).toDouble();
        final employeeId =
            isVerified ? 'EMP${i.toString().padLeft(3, '0')}' : null;
        final failureReason = isVerified ? null : 'Failure $i';
        final result = AuthResult(
          classification: isVerified
              ? AuthClassification.verified
              : AuthClassification.failed,
          trustScore: score,
          matchedEmployeeId: employeeId,
          failureReason: failureReason,
        );

        await tester.pumpWidget(_screen(storage, result));
        await tester.pump();
        await tester.pump();

        expect(storage.logs, hasLength(i + 1));
        final log = storage.logs.last;
        expect(log.result, result.classification);
        expect(log.trustScore, result.trustScore);
        expect(log.employeeId, result.matchedEmployeeId);
        expect(log.failureReason, result.failureReason);
        expect(log.timestamp.isUtc, isTrue);
      }
    });
  });
}
