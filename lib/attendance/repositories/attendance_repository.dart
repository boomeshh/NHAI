// Attendance repository (Phase 1/3/5). Interface + in-memory implementation.
import '../models/attendance_record.dart';
import '../models/enums.dart';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

abstract class AttendanceRepository {
  Future<void> save(AttendanceRecord record);
  Future<void> update(AttendanceRecord record);
  Future<AttendanceRecord?> getById(String attendanceId);

  /// The employee's currently-open (checked-in, not checked-out) record, if any.
  Future<AttendanceRecord?> getOpenRecord(String employeeId);

  Future<List<AttendanceRecord>> getByEmployeeAndDate(
      String employeeId, DateTime date);
  Future<List<AttendanceRecord>> getByDate(DateTime date);
  Future<List<AttendanceRecord>> getByEmployee(String employeeId);
  Future<List<AttendanceRecord>> getByDateRange(DateTime from, DateTime to);
  Future<List<AttendanceRecord>> getAll();
  Future<List<AttendanceRecord>> getBySyncStatus(SyncStatus status);

  /// Removes the records with the given ids; returns the count removed.
  /// Used by the sync/purge engine to retire synced, expired records.
  Future<int> deleteByIds(Iterable<String> attendanceIds);
}

class InMemoryAttendanceRepository implements AttendanceRepository {
  final Map<String, AttendanceRecord> _store = {};

  @override
  Future<void> save(AttendanceRecord record) async =>
      _store[record.attendanceId] = record;

  @override
  Future<void> update(AttendanceRecord record) async =>
      _store[record.attendanceId] = record;

  @override
  Future<AttendanceRecord?> getById(String attendanceId) async =>
      _store[attendanceId];

  @override
  Future<AttendanceRecord?> getOpenRecord(String employeeId) async {
    for (final r in _store.values) {
      if (r.employeeId == employeeId && r.isOpen) return r;
    }
    return null;
  }

  @override
  Future<List<AttendanceRecord>> getByEmployeeAndDate(
          String employeeId, DateTime date) async =>
      _store.values
          .where((r) => r.employeeId == employeeId && _sameDate(r.date, date))
          .toList();

  @override
  Future<List<AttendanceRecord>> getByDate(DateTime date) async =>
      _store.values.where((r) => _sameDate(r.date, date)).toList();

  @override
  Future<List<AttendanceRecord>> getByEmployee(String employeeId) async =>
      _store.values.where((r) => r.employeeId == employeeId).toList();

  @override
  Future<List<AttendanceRecord>> getByDateRange(
          DateTime from, DateTime to) async =>
      _store.values
          .where((r) =>
              !r.date.isBefore(_dateOnly(from)) &&
              !r.date.isAfter(_dateOnly(to)))
          .toList();

  @override
  Future<List<AttendanceRecord>> getAll() async => _store.values.toList();

  @override
  Future<List<AttendanceRecord>> getBySyncStatus(SyncStatus status) async =>
      _store.values.where((r) => r.syncStatus == status).toList();

  @override
  Future<int> deleteByIds(Iterable<String> attendanceIds) async {
    var removed = 0;
    for (final id in attendanceIds) {
      if (_store.remove(id) != null) removed++;
    }
    return removed;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
