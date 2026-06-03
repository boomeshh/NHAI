// Persistent, append-only [AuditRepository] backed by a [SecureDatabase].
// Entries are immutable (no update / delete) — the audit trail is durable and
// tamper-evident across restarts. Backs the dashboard's authentication-success
// metric. Stored as JSON keyed by auditId.
import '../models/attendance_audit_log.dart';
import '../persistence/secure_database.dart';
import 'audit_repository.dart';

class PersistentAuditRepository implements AuditRepository {
  final SecureDatabase db;
  static const _table = AttendanceTables.audit;

  PersistentAuditRepository(this.db);

  @override
  Future<void> append(AttendanceAuditLog entry) async =>
      db.put(_table, entry.auditId, entry.toJson());

  @override
  Future<List<AttendanceAuditLog>> getAll() async {
    final rows = await db.getAll(_table);
    return rows.map(AttendanceAuditLog.fromJson).toList();
  }

  @override
  Future<List<AttendanceAuditLog>> getByEmployee(String employeeId) async =>
      (await getAll()).where((e) => e.employeeId == employeeId).toList();
}
