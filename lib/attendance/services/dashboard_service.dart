// Attendance dashboard metrics (Phase 7).
import '../models/enums.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/audit_repository.dart';
import '../repositories/employee_repository.dart';
import '../sync/sync_queue.dart';

class DashboardMetrics {
  final int totalEmployees;
  final int presentToday;
  final int absentToday;
  final int checkInCount;
  final int checkOutCount;
  final int pendingSyncRecords;
  final double averageTrustScore;
  final double authenticationSuccessRate;

  /// Per-day check-in counts, keyed by `yyyy-mm-dd`.
  final Map<String, int> attendanceTrend;

  const DashboardMetrics({
    required this.totalEmployees,
    required this.presentToday,
    required this.absentToday,
    required this.checkInCount,
    required this.checkOutCount,
    required this.pendingSyncRecords,
    required this.averageTrustScore,
    required this.authenticationSuccessRate,
    required this.attendanceTrend,
  });

  Map<String, dynamic> toJson() => {
        'totalEmployees': totalEmployees,
        'presentToday': presentToday,
        'absentToday': absentToday,
        'checkInCount': checkInCount,
        'checkOutCount': checkOutCount,
        'pendingSyncRecords': pendingSyncRecords,
        'averageTrustScore': averageTrustScore,
        'authenticationSuccessRate': authenticationSuccessRate,
        'attendanceTrend': attendanceTrend,
      };
}

class DashboardService {
  final EmployeeRepository employees;
  final AttendanceRepository attendance;
  final AuditRepository auditRepository;
  final SyncQueue syncQueue;

  DashboardService({
    required this.employees,
    required this.attendance,
    required this.auditRepository,
    required this.syncQueue,
  });

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<DashboardMetrics> compute(DateTime today, {int trendDays = 7}) async {
    final allEmployees = await employees.getAll();
    final activeEmployees = await employees.getActive();
    final todays = await attendance.getByDate(today);

    final presentIds = todays.map((r) => r.employeeId).toSet();
    final checkInCount = todays.length;
    final checkOutCount = todays.where((r) => r.checkOutTime != null).length;
    final pending = (await syncQueue.pending()).length;
    final avgTrust = todays.isEmpty
        ? 0.0
        : todays.map((r) => r.trustScore).reduce((a, b) => a + b) /
            todays.length;

    final logs = await auditRepository.getAll();
    final marked =
        logs.where((l) => l.eventType == AuditEventType.attendanceMarked).length;
    final failed = logs
        .where((l) =>
            l.eventType == AuditEventType.attendanceFailed ||
            l.eventType == AuditEventType.authenticationFailed)
        .length;
    final total = marked + failed;
    final successRate = total == 0 ? 0.0 : marked / total;

    final trend = <String, int>{};
    for (int i = trendDays - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      trend[_key(d)] = (await attendance.getByDate(d)).length;
    }

    return DashboardMetrics(
      totalEmployees: allEmployees.length,
      presentToday: presentIds.length,
      absentToday:
          activeEmployees.where((e) => !presentIds.contains(e.employeeId)).length,
      checkInCount: checkInCount,
      checkOutCount: checkOutCount,
      pendingSyncRecords: pending,
      averageTrustScore: avgTrust,
      authenticationSuccessRate: successRate,
      attendanceTrend: trend,
    );
  }
}
