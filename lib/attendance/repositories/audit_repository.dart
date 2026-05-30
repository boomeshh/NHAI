// Audit repository (Phase 6). Append-only / immutable: no update or delete.
import '../models/attendance_audit_log.dart';

abstract class AuditRepository {
  Future<void> append(AttendanceAuditLog entry);
  Future<List<AttendanceAuditLog>> getAll();
  Future<List<AttendanceAuditLog>> getByEmployee(String employeeId);
}

class InMemoryAuditRepository implements AuditRepository {
  final List<AttendanceAuditLog> _log = [];

  @override
  Future<void> append(AttendanceAuditLog entry) async => _log.add(entry);

  @override
  Future<List<AttendanceAuditLog>> getAll() async =>
      List.unmodifiable(_log); // callers cannot mutate the audit trail

  @override
  Future<List<AttendanceAuditLog>> getByEmployee(String employeeId) async =>
      _log.where((e) => e.employeeId == employeeId).toList();
}
