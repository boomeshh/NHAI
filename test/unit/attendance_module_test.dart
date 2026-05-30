import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/models/employee.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/attendance/models/shift.dart';
import 'package:nhai_auth/attendance/repositories/anomaly_repository.dart';
import 'package:nhai_auth/attendance/repositories/attendance_repository.dart';
import 'package:nhai_auth/attendance/repositories/audit_repository.dart';
import 'package:nhai_auth/attendance/repositories/employee_repository.dart';
import 'package:nhai_auth/attendance/repositories/shift_repository.dart';
import 'package:nhai_auth/attendance/security/field_encryptor.dart';
import 'package:nhai_auth/attendance/services/anomaly_detector.dart';
import 'package:nhai_auth/attendance/services/attendance_engine.dart';
import 'package:nhai_auth/attendance/services/audit_service.dart';
import 'package:nhai_auth/attendance/services/dashboard_service.dart';
import 'package:nhai_auth/attendance/services/employee_service.dart';
import 'package:nhai_auth/attendance/services/id_generator.dart';
import 'package:nhai_auth/attendance/services/report_service.dart';
import 'package:nhai_auth/attendance/services/shift_service.dart';
import 'package:nhai_auth/attendance/sync/sync_queue.dart';

class Harness {
  final emp = InMemoryEmployeeRepository();
  final att = InMemoryAttendanceRepository();
  final aud = InMemoryAuditRepository();
  final shf = InMemoryShiftRepository();
  final ano = InMemoryAnomalyRepository();
  final queue = InMemorySyncQueue();
  final ids = IdGenerator('TEST');

  late final BiometricCodec codec;
  late final AuditService audit;
  late final EmployeeService employees;
  late final ShiftService shifts;
  late final AnomalyDetector detector;
  late final AttendanceEngine engine;
  late final DashboardService dashboard;
  late final ReportService reports;

  Harness() {
    codec = BiometricCodec(KeyedFieldEncryptor('unit-test-secret'));
    audit = AuditService(repository: aud, ids: ids, deviceId: 'DEV-1');
    employees = EmployeeService(
        repository: emp, audit: audit, codec: codec, ids: ids);
    shifts = ShiftService(shf);
    detector = AnomalyDetector(
      anomalies: ano,
      auditRepository: aud,
      audit: audit,
      ids: ids,
      deviceId: 'DEV-1',
    );
    engine = AttendanceEngine(
      employees: emp,
      attendance: att,
      audit: audit,
      shifts: shifts,
      anomalyDetector: detector,
      syncQueue: queue,
      ids: ids,
      deviceId: 'DEV-1',
    );
    dashboard = DashboardService(
        employees: emp, attendance: att, auditRepository: aud, syncQueue: queue);
    reports = ReportService(attendance: att);
  }
}

final _embedding = List<double>.generate(128, (i) => (i % 10) * 0.1 + 0.05);

VerificationContext _goodCtx({double trust = 0.95, bool blink = true}) =>
    VerificationContext(
      faceVerified: true,
      blinkPassed: blink,
      trustScore: trust,
      deviceId: 'DEV-1',
      offlineMode: true,
    );

Future<Employee> _enroll(Harness h, String id, {bool active = true}) =>
    h.employees.create(
      employeeId: id,
      employeeCode: 'C-$id',
      fullName: 'Operator $id',
      designation: 'Toll Operator',
      department: 'Tolling',
      mobileNumber: '9876543210',
      joiningDate: DateTime.utc(2025, 1, 1),
      faceEmbedding: _embedding,
      now: DateTime.utc(2026, 1, 1),
      activeStatus: active,
    );

void main() {
  final now = DateTime.utc(2026, 1, 5, 10, 0);

  group('Employee', () {
    test('Test 1: create employee', () async {
      final h = Harness();
      final e = await _enroll(h, 'EMP1');
      expect(e.employeeId, 'EMP1');
      expect(await h.emp.exists('EMP1'), isTrue);
    });

    test('Test 2: duplicate employee rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      expect(() => _enroll(h, 'EMP1'),
          throwsA(isA<DuplicateEmployeeException>()));
    });

    test('Test 3: invalid employee rejected', () async {
      final h = Harness();
      expect(
        () => h.employees.create(
          employeeId: 'BAD',
          employeeCode: '',
          fullName: '',
          designation: 'x',
          department: '',
          mobileNumber: '12',
          joiningDate: DateTime.utc(2025, 1, 1),
          faceEmbedding: const [],
          now: now,
        ),
        throwsA(isA<EmployeeValidationException>()),
      );
    });
  });

  group('Attendance state machine', () {
    test('Test 4: check-in success', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      expect(r.accepted, isTrue);
      expect(r.record!.isOpen, isTrue);
    });

    test('Test 5: double check-in rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final r2 = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now.add(const Duration(minutes: 1)));
      expect(r2.accepted, isFalse);
      expect(r2.rejectionReason, contains('Already checked in'));
    });

    test('Test 6: checkout before checkin rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkOut,
          ctx: _goodCtx(),
          now: now);
      expect(r.accepted, isFalse);
      expect(r.rejectionReason, contains('before checking in'));
    });

    test('Test 7: check-out success', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final out = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkOut,
          ctx: _goodCtx(),
          now: now.add(const Duration(hours: 8)));
      expect(out.accepted, isTrue);
      expect(out.record!.checkOutTime, isNotNull);
    });
  });

  group('Authentication validation', () {
    test('Test 8: face verification failed → rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: const VerificationContext(
              faceVerified: false,
              blinkPassed: true,
              trustScore: 0.95,
              deviceId: 'DEV-1'),
          now: now);
      expect(r.accepted, isFalse);
      expect(r.rejectionReason, contains('Face verification'));
    });

    test('Test 9: blink failed → rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(blink: false),
          now: now);
      expect(r.accepted, isFalse);
      expect(r.rejectionReason, contains('blink'));
    });

    test('Test 9b: trust below threshold → rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(trust: 0.74),
          now: now);
      expect(r.accepted, isFalse);
      expect(r.rejectionReason, contains('Trust score'));
    });

    test('Test 10: inactive employee → rejected', () async {
      final h = Harness();
      await _enroll(h, 'EMP1', active: false);
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      expect(r.accepted, isFalse);
      expect(r.rejectionReason, contains('inactive'));
    });
  });

  group('Offline-first storage', () {
    test('Test 11: attendance stored offline', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final stored = await h.att.getById(r.record!.attendanceId);
      expect(stored, isNotNull);
      expect(stored!.offlineMode, isTrue);
      expect(stored.syncStatus, SyncStatus.pending);
    });

    test('Test 12: pending sync record created', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final pending = await h.queue.pending();
      expect(pending, isNotEmpty);
      expect(pending.first.entityType, 'attendance');
      expect(pending.first.status, SyncStatus.pending);
    });
  });

  group('Audit engine', () {
    test('Test 13: audit generated on attendance', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final logs = await h.aud.getAll();
      expect(
          logs.any((l) => l.eventType == AuditEventType.attendanceMarked), isTrue);
      expect(
          logs.any((l) => l.eventType == AuditEventType.employeeCreated), isTrue);
    });

    test('Test 14: audit log is immutable (append-only)', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      final logs = await h.aud.getAll();
      expect(() => logs.add(logs.first), throwsUnsupportedError);
    });
  });

  group('Shifts', () {
    test('Test 15: attendance linked to shift', () async {
      final h = Harness();
      await h.shifts.defineShift(const Shift(
          shiftId: 'GEN',
          shiftName: 'General',
          shiftType: ShiftType.general,
          startMinute: 9 * 60,
          endMinute: 18 * 60));
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: DateTime.utc(2026, 1, 5, 9, 5),
          shiftId: 'GEN');
      expect(r.accepted, isTrue);
      expect(r.record!.shiftId, 'GEN');
      expect(r.record!.isLate, isFalse);
    });

    test('Test 16: late arrival flagged', () async {
      final h = Harness();
      await h.shifts.defineShift(const Shift(
          shiftId: 'GEN',
          shiftName: 'General',
          shiftType: ShiftType.general,
          startMinute: 9 * 60,
          endMinute: 18 * 60,
          graceMinutes: 10));
      await _enroll(h, 'EMP1');
      final r = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: DateTime.utc(2026, 1, 5, 9, 25),
          shiftId: 'GEN');
      expect(r.record!.isLate, isTrue);
    });
  });

  group('Suspicious activity', () {
    test('Test 17: repeated verification failures flagged', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      for (var i = 0; i < 3; i++) {
        await h.engine.mark(
            employeeId: 'EMP1',
            eventType: AttendanceEventType.checkIn,
            ctx: _goodCtx(trust: 0.1),
            now: now.add(Duration(seconds: i)));
      }
      final anomalies = await h.ano.getByEmployee('EMP1');
      expect(
          anomalies.any(
              (a) => a.type == AnomalyType.repeatedVerificationFailure),
          isTrue);
    });

    test('Test 18: multiple check-ins flagged', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final r2 = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now.add(const Duration(minutes: 1)));
      expect(r2.anomalies.any((a) => a.type == AnomalyType.multipleCheckIn),
          isTrue);
    });

    test('Test 19: high-risk event recorded', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final r2 = await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now.add(const Duration(minutes: 1)));
      expect(r2.risk, RiskLevel.high);
      expect(
          (await h.ano.getAll()).any((a) => a.riskLevel == RiskLevel.high),
          isTrue);
    });
  });

  group('Dashboard', () {
    test('Test 20: present count', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await _enroll(h, 'EMP2');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final m = await h.dashboard.compute(now);
      expect(m.presentToday, 1);
      expect(m.checkInCount, 1);
    });

    test('Test 21: absent count', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await _enroll(h, 'EMP2');
      await _enroll(h, 'EMP3');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final m = await h.dashboard.compute(now);
      expect(m.absentToday, 2); // EMP2 + EMP3
    });

    test('Test 22: authentication success rate', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now); // 1 marked
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(trust: 0.1),
          now: now.add(const Duration(minutes: 1))); // 1 failed
      final m = await h.dashboard.compute(now);
      expect(m.authenticationSuccessRate, closeTo(0.5, 1e-9));
    });
  });

  group('Security', () {
    test('Test 23: sensitive data encrypted (round-trips, not plaintext)',
        () async {
      final h = Harness();
      final e = await _enroll(h, 'EMP1');
      final plainJson = jsonEncode(_embedding);
      expect(e.faceEmbeddingEncrypted, isNot(equals(plainJson)));
      final decoded = h.codec.decode(e.faceEmbeddingEncrypted);
      for (var i = 0; i < _embedding.length; i++) {
        expect(decoded[i], closeTo(_embedding[i], 1e-9));
      }
    });

    test('Test 24: embedding never serialized as plaintext', () async {
      final h = Harness();
      final e = await _enroll(h, 'EMP1');
      final serialized = jsonEncode(e.toJson());
      // The raw embedding values must not appear in the serialized record.
      expect(serialized.contains('0.05,0.15'), isFalse);
      expect(serialized.contains(jsonEncode(_embedding)), isFalse);
    });
  });

  group('Reporting', () {
    test('Test 25: daily report', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: now);
      final report = await h.reports.dailyReport(now);
      expect(report['type'], 'daily');
      expect((report['summary'] as Map)['records'], 1);
      expect((report['records'] as List).length, 1);
    });

    test('Test 26: monthly report', () async {
      final h = Harness();
      await _enroll(h, 'EMP1');
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkIn,
          ctx: _goodCtx(),
          now: DateTime.utc(2026, 1, 3, 10));
      await h.engine.mark(
          employeeId: 'EMP1',
          eventType: AttendanceEventType.checkOut,
          ctx: _goodCtx(),
          now: DateTime.utc(2026, 1, 3, 18));
      final report = await h.reports.monthlyReport(2026, 1);
      expect(report['type'], 'monthly');
      expect((report['summary'] as Map)['records'], 1);
    });
  });
}
