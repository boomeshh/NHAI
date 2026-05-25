import '../../models/employee_record.dart';
import '../../models/auth_log_entry.dart';

abstract class StorageManagerInterface {
  Future<void> saveEmployeeRecord(EmployeeRecord record);
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId);
  Future<List<EmployeeRecord>> getAllEmployeeRecords();
  Future<bool> employeeExists(String employeeId);
  Future<void> deleteEmployeeRecord(String employeeId);
  Future<void> logAuthAttempt(AuthLogEntry entry);
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100});
  Future<void> logStorageError(String message);
}
