// Audit engine (Phase 6) — produces immutable audit entries for every event.
import '../models/attendance_audit_log.dart';
import '../models/enums.dart';
import '../repositories/audit_repository.dart';
import 'id_generator.dart';

class AuditService {
  final AuditRepository repository;
  final IdGenerator ids;
  final String deviceId;

  AuditService({
    required this.repository,
    required this.ids,
    required this.deviceId,
  });

  Future<AttendanceAuditLog> record(
    AuditEventType eventType,
    DateTime now, {
    String? employeeId,
    Map<String, dynamic> details = const {},
  }) async {
    final entry = AttendanceAuditLog(
      auditId: ids.next('AUD'),
      eventType: eventType,
      employeeId: employeeId,
      timestamp: now,
      deviceId: deviceId,
      details: details,
    );
    await repository.append(entry);
    return entry;
  }
}
