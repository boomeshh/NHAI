import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/models/attendance_record.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/attendance/repositories/attendance_repository.dart';
import 'package:nhai_auth/attendance/repositories/audit_repository.dart';
import 'package:nhai_auth/attendance/repositories/employee_repository.dart';
import 'package:nhai_auth/attendance/services/dashboard_service.dart';
import 'package:nhai_auth/attendance/sync/sync_queue.dart';

AttendanceRecord _rec(String id, String emp, {required bool late}) =>
    AttendanceRecord(
      attendanceId: id,
      employeeId: emp,
      date: DateTime(2026, 6, 1),
      checkInTime: DateTime(2026, 6, 1, 9),
      verificationMethod: VerificationMethod.face,
      trustScore: 0.9,
      deviceId: 'DEV1',
      offlineMode: true,
      syncStatus: SyncStatus.pending,
      isLate: late,
    );

void main() {
  test('DashboardService reports lateToday count from late records', () async {
    final attendance = InMemoryAttendanceRepository();
    await attendance.save(_rec('A1', 'EMP1', late: true));
    await attendance.save(_rec('A2', 'EMP2', late: false));
    await attendance.save(_rec('A3', 'EMP3', late: true));

    final dashboard = DashboardService(
      employees: InMemoryEmployeeRepository(),
      attendance: attendance,
      auditRepository: InMemoryAuditRepository(),
      syncQueue: InMemorySyncQueue(),
    );

    final m = await dashboard.compute(DateTime(2026, 6, 1));
    expect(m.lateToday, 2);
    expect(m.presentToday, 3);
    expect(m.toJson()['lateToday'], 2);
  });
}
