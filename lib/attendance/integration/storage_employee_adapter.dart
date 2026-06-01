// Bridges the existing biometric employee store (StorageManagerInterface /
// EmployeeRecord) to the attendance EmployeeRepository, so the attendance
// engine sees enrolled employees without duplicating enrollment. Read-only:
// employee lifecycle stays owned by the biometric enrollment pipeline.
import '../../core/storage_manager/storage_manager_interface.dart';
import '../../models/employee_record.dart';
import '../models/employee.dart';
import '../repositories/employee_repository.dart';

class StorageEmployeeAdapter implements EmployeeRepository {
  final StorageManagerInterface storage;
  StorageEmployeeAdapter(this.storage);

  Employee _map(EmployeeRecord r) => Employee(
        employeeId: r.employeeId,
        employeeCode: r.employeeId,
        fullName: r.name,
        designation: 'NHAI Workforce',
        department: r.department,
        mobileNumber: '',
        joiningDate: r.enrolledAt,
        activeStatus: true,
        // The embedding lives encrypted in the biometric store; the attendance
        // engine never needs it (it consumes a VerificationContext instead).
        faceEmbeddingEncrypted: '',
        createdAt: r.enrolledAt,
        updatedAt: r.enrolledAt,
      );

  @override
  Future<Employee?> getById(String employeeId) async {
    final r = await storage.getEmployeeRecord(employeeId);
    return r == null ? null : _map(r);
  }

  @override
  Future<bool> exists(String employeeId) => storage.employeeExists(employeeId);

  @override
  Future<List<Employee>> getAll() async =>
      (await storage.getAllEmployeeRecords()).map(_map).toList();

  @override
  Future<List<Employee>> getActive() => getAll();

  @override
  Future<void> add(Employee employee) async =>
      throw UnsupportedError('Enrollment is owned by the biometric pipeline');

  @override
  Future<void> update(Employee employee) async =>
      throw UnsupportedError('Employee updates go through the biometric pipeline');

  @override
  Future<void> delete(String employeeId) =>
      storage.deleteEmployeeRecord(employeeId);
}
