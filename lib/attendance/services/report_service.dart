// Attendance reports (Phase 10). Returns export-ready map/list structures
// (JSON-serializable) for daily/weekly/monthly/employee/trust-score reports.
import '../models/attendance_record.dart';
import '../repositories/attendance_repository.dart';

class ReportService {
  final AttendanceRepository attendance;
  ReportService({required this.attendance});

  Map<String, dynamic> _summary(List<AttendanceRecord> records) {
    final present = records.map((r) => r.employeeId).toSet().length;
    final lateCount = records.where((r) => r.isLate).length;
    final checkedOut = records.where((r) => r.checkOutTime != null).length;
    final avgTrust = records.isEmpty
        ? 0.0
        : records.map((r) => r.trustScore).reduce((a, b) => a + b) /
            records.length;
    return {
      'records': records.length,
      'uniqueEmployees': present,
      'checkOuts': checkedOut,
      'lateArrivals': lateCount,
      'averageTrustScore': avgTrust,
    };
  }

  Future<Map<String, dynamic>> dailyReport(DateTime date) async {
    final records = await attendance.getByDate(date);
    return {
      'type': 'daily',
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'summary': _summary(records),
      'records': records.map((r) => r.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> weeklyReport(DateTime weekStart) async {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));
    final records = await attendance.getByDateRange(start, end);
    return {
      'type': 'weekly',
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
      'summary': _summary(records),
      'records': records.map((r) => r.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> monthlyReport(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0); // last day of month
    final records = await attendance.getByDateRange(start, end);
    return {
      'type': 'monthly',
      'year': year,
      'month': month,
      'summary': _summary(records),
      'records': records.map((r) => r.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> employeeHistory(String employeeId) async {
    final records = await attendance.getByEmployee(employeeId);
    records.sort((a, b) => a.checkInTime.compareTo(b.checkInTime));
    return {
      'type': 'employeeHistory',
      'employeeId': employeeId,
      'summary': _summary(records),
      'records': records.map((r) => r.toJson()).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> trustScoreHistory(
      String employeeId) async {
    final records = await attendance.getByEmployee(employeeId);
    records.sort((a, b) => a.checkInTime.compareTo(b.checkInTime));
    return records
        .map((r) => {
              'attendanceId': r.attendanceId,
              'date': r.date.toIso8601String(),
              'trustScore': r.trustScore,
            })
        .toList();
  }
}
