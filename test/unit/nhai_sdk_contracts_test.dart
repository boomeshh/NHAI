import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/sdk/nhai_sdk_contracts.dart';

void main() {
  group('SdkResult', () {
    test('success/failure envelopes + JSON round-trip', () {
      final ok = SdkResult.success({'employeeId': 'E1'}, message: 'done');
      expect(ok.ok, isTrue);
      expect(ok.code, SdkCodes.ok);
      final round = SdkResult.fromJson(ok.toJson());
      expect(round.ok, isTrue);
      expect(round.data['employeeId'], 'E1');
      expect(round.message, 'done');

      final fail = SdkResult.failure(SdkCodes.notVerified, 'nope',
          data: {'verified': false});
      expect(fail.ok, isFalse);
      expect(fail.toJson()['code'], 'NOT_VERIFIED');
      expect(fail.toJson()['data'], {'verified': false});
    });
  });

  group('asArgs', () {
    test('null → empty, map → map, other → throws', () {
      expect(asArgs(null), isEmpty);
      expect(asArgs({'a': 1}), {'a': 1});
      expect(() => asArgs('bad'), throwsA(isA<SdkArgumentError>()));
    });
  });

  group('EnrollRequest.parse', () {
    test('parses valid args incl. allowOverwrite', () {
      final r = EnrollRequest.parse({
        'employeeId': 'E1',
        'name': 'A',
        'department': 'Patrol',
        'allowOverwrite': true,
      });
      expect(r.employeeId, 'E1');
      expect(r.allowOverwrite, isTrue);
    });

    test('missing required field throws SdkArgumentError', () {
      expect(() => EnrollRequest.parse({'employeeId': 'E1', 'name': 'A'}),
          throwsA(isA<SdkArgumentError>()));
      expect(() => EnrollRequest.parse({'employeeId': '', 'name': 'A', 'department': 'P'}),
          throwsA(isA<SdkArgumentError>()));
    });
  });

  group('SummaryRequest.parse', () {
    final now = DateTime(2026, 6, 1, 9);
    test('defaults to daily/today when absent', () {
      final r = SummaryRequest.parse({}, now: now);
      expect(r.scope, 'daily');
      expect(r.date, now);
    });
    test('parses monthly + explicit date', () {
      final r = SummaryRequest.parse(
          {'scope': 'monthly', 'date': '2026-03-15T00:00:00.000'}, now: now);
      expect(r.scope, 'monthly');
      expect(r.date.month, 3);
    });
    test('invalid scope throws', () {
      expect(() => SummaryRequest.parse({'scope': 'yearly'}, now: now),
          throwsA(isA<SdkArgumentError>()));
    });
  });

  group('SyncRequest / MarkAttendanceRequest', () {
    test('SyncRequest purge flag', () {
      expect(SyncRequest.parse({}).purge, isFalse);
      expect(SyncRequest.parse({'purge': true}).purge, isTrue);
    });
    test('MarkAttendanceRequest forced passthrough', () {
      expect(MarkAttendanceRequest.parse({}).forced, isNull);
      expect(MarkAttendanceRequest.parse({'forced': 'checkOut'}).forced, 'checkOut');
    });
  });

  test('SdkMethods enumerates the five public methods', () {
    expect(SdkMethods.all, hasLength(5));
    expect(SdkMethods.all, contains('markAttendance'));
  });
}
