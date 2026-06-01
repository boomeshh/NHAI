// End-to-end integration (Integration Phase, requirement 9):
//   Employee Creation → Face Enrollment → Face Authentication → Check In →
//   Dashboard Update → Check Out → Attendance History
//
// Exercises the real wiring: the biometric store (StorageManagerInterface) is
// bridged into the AttendanceModule; a verified AuthResult is routed through
// the AttendanceCoordinator exactly as the verification screen does.
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/integration/attendance_module.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

/// Minimal in-memory biometric store (stands in for StorageManagerImpl/Hive).
class _MemStorage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> employees = {};
  final List<AuthLogEntry> logs = [];

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async =>
      employees[r.employeeId] = r;
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => employees[id];
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async =>
      employees.values.toList();
  @override
  Future<bool> employeeExists(String id) async => employees.containsKey(id);
  @override
  Future<void> deleteEmployeeRecord(String id) async => employees.remove(id);
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async => logs.add(e);
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => logs;
  @override
  Future<void> logStorageError(String m) async {}
}

AuthResult _verified(String id, {double trust = 0.92}) => AuthResult(
      classification: AuthClassification.verified,
      trustScore: trust,
      matchedEmployeeId: id,
    );

void main() {
  test('full pipeline: enroll → authenticate → check-in → dashboard → '
      'check-out → history', () async {
    final now = DateTime(2026, 2, 10, 9, 5);

    // 1. Employee Creation + Face Enrollment (biometric store).
    final storage = _MemStorage();
    await storage.saveEmployeeRecord(EmployeeRecord(
      employeeId: 'EMP-100',
      name: 'Patrol Officer A',
      department: 'Patrol',
      embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
      enrolledAt: DateTime.utc(2026, 1, 1),
    ));

    // 2. Wire the attendance engine over the same store (bridge).
    final module = AttendanceModule.inMemory(storage: storage);

    // 3 + 4. Face Authentication → Check In (auto-resolved, no open session).
    final checkIn = await module.coordinator
        .markFromAuthResult(_verified('EMP-100'), now: now);
    expect(checkIn.marked, isTrue);
    expect(checkIn.eventType, AttendanceEventType.checkIn);
    expect(checkIn.engineResult!.record!.isOpen, isTrue);

    // 5. Dashboard Update reflects the check-in.
    final dash1 = await module.dashboard.compute(now);
    expect(dash1.totalEmployees, 1);
    expect(dash1.presentToday, 1);
    expect(dash1.absentToday, 0);
    expect(dash1.checkInCount, 1);
    expect(dash1.pendingSyncRecords, greaterThanOrEqualTo(1));
    expect(dash1.averageTrustScore, closeTo(0.92, 1e-9));

    // 6. Face Authentication → Check Out (open session now exists).
    final checkOut = await module.coordinator.markFromAuthResult(
        _verified('EMP-100'),
        now: now.add(const Duration(hours: 8)));
    expect(checkOut.marked, isTrue);
    expect(checkOut.eventType, AttendanceEventType.checkOut);
    expect(checkOut.engineResult!.record!.checkOutTime, isNotNull);

    // 7. Attendance History contains the completed record.
    final history = await module.attendance.getAll();
    expect(history, hasLength(1));
    expect(history.first.checkOutTime, isNotNull);
    expect(history.first.employeeId, 'EMP-100');

    // Audit trail + offline sync queue were populated end-to-end.
    final audit = await module.auditRepository.getAll();
    expect(
        audit.where((a) => a.eventType == AuditEventType.attendanceMarked)
            .length,
        2);
    final pending = await module.syncQueue.pending();
    expect(pending.length, 2); // check-in + check-out queued for sync
  });

  test('verification not passed → attendance NOT marked', () async {
    final storage = _MemStorage();
    await storage.saveEmployeeRecord(EmployeeRecord(
      employeeId: 'EMP-200',
      name: 'X',
      department: 'Toll',
      embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
      enrolledAt: DateTime.utc(2026, 1, 1),
    ));
    final module = AttendanceModule.inMemory(storage: storage);

    final outcome = await module.coordinator.markFromAuthResult(
      const AuthResult(
          classification: AuthClassification.failed, trustScore: 0.4),
      now: DateTime(2026, 2, 10, 9, 0),
    );
    expect(outcome.marked, isFalse);
    expect(await module.attendance.getAll(), isEmpty);
  });

  test('dashboard counts an enrolled-but-absent employee', () async {
    final storage = _MemStorage();
    for (final id in ['A', 'B']) {
      await storage.saveEmployeeRecord(EmployeeRecord(
        employeeId: id,
        name: id,
        department: 'Maintenance',
        embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
      ));
    }
    final module = AttendanceModule.inMemory(storage: storage);
    final now = DateTime(2026, 2, 10, 9, 0);
    await module.coordinator.markFromAuthResult(_verified('A'), now: now);

    final dash = await module.dashboard.compute(now);
    expect(dash.totalEmployees, 2);
    expect(dash.presentToday, 1);
    expect(dash.absentToday, 1); // B enrolled but not present
  });
}
