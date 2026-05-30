import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/employee_record.dart';

class InMemoryStorage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> records = {};
  final List<AuthLogEntry> logs = [];
  final List<String> errors = [];

  int getAuthLogsCallCount = 0;
  int logAuthAttemptCallCount = 0;
  int lastRequestedLimit = 0;

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord record) async {
    records[record.employeeId] = record;
  }

  @override
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async {
    return records[employeeId];
  }

  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async {
    return records.values.toList();
  }

  @override
  Future<bool> employeeExists(String employeeId) async {
    return records.containsKey(employeeId);
  }

  @override
  Future<void> deleteEmployeeRecord(String employeeId) async {
    records.remove(employeeId);
  }

  @override
  Future<void> logAuthAttempt(AuthLogEntry entry) async {
    logAuthAttemptCallCount++;
    logs.add(entry);
  }

  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async {
    getAuthLogsCallCount++;
    lastRequestedLimit = limit;
    final sorted = List<AuthLogEntry>.from(logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  @override
  Future<void> logStorageError(String message) async {
    errors.add(message);
  }
}
