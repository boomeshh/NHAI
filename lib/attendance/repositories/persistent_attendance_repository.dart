// Persistent [AttendanceRepository] backed by a [SecureDatabase] (SQLCipher on
// device, in-memory in tests). Records are stored as JSON documents keyed by
// attendanceId; date / employee / sync-status predicates are applied in Dart
// after loading the table. For an offline edge device the per-site dataset is
// small, so load-and-filter is both correct and fully testable — the identical
// logic runs over the encrypted SQLite backend on-device.
import '../models/attendance_record.dart';
import '../models/enums.dart';
import '../persistence/secure_database.dart';
import 'attendance_repository.dart';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class PersistentAttendanceRepository implements AttendanceRepository {
  final SecureDatabase db;
  static const _table = AttendanceTables.attendance;

  PersistentAttendanceRepository(this.db);

  @override
  Future<void> save(AttendanceRecord record) async =>
      db.put(_table, record.attendanceId, record.toJson());

  @override
  Future<void> update(AttendanceRecord record) async =>
      db.put(_table, record.attendanceId, record.toJson());

  @override
  Future<AttendanceRecord?> getById(String attendanceId) async {
    final row = await db.get(_table, attendanceId);
    return row == null ? null : AttendanceRecord.fromJson(row);
  }

  Future<List<AttendanceRecord>> _all() async {
    final rows = await db.getAll(_table);
    return rows.map(AttendanceRecord.fromJson).toList();
  }

  @override
  Future<AttendanceRecord?> getOpenRecord(String employeeId) async {
    for (final r in await _all()) {
      if (r.employeeId == employeeId && r.isOpen) return r;
    }
    return null;
  }

  @override
  Future<List<AttendanceRecord>> getByEmployeeAndDate(
          String employeeId, DateTime date) async =>
      (await _all())
          .where((r) => r.employeeId == employeeId && _sameDate(r.date, date))
          .toList();

  @override
  Future<List<AttendanceRecord>> getByDate(DateTime date) async =>
      (await _all()).where((r) => _sameDate(r.date, date)).toList();

  @override
  Future<List<AttendanceRecord>> getByEmployee(String employeeId) async =>
      (await _all()).where((r) => r.employeeId == employeeId).toList();

  @override
  Future<List<AttendanceRecord>> getByDateRange(
          DateTime from, DateTime to) async =>
      (await _all())
          .where((r) =>
              !r.date.isBefore(_dateOnly(from)) && !r.date.isAfter(_dateOnly(to)))
          .toList();

  @override
  Future<List<AttendanceRecord>> getAll() async => _all();

  @override
  Future<List<AttendanceRecord>> getBySyncStatus(SyncStatus status) async =>
      (await _all()).where((r) => r.syncStatus == status).toList();

  /// Removes the given records from durable storage. Used by the purge engine.
  @override
  Future<int> deleteByIds(Iterable<String> attendanceIds) =>
      db.deleteWhereIdIn(_table, attendanceIds);
}
