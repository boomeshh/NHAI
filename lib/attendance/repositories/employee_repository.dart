// Employee repository (Phase 1). Interface + in-memory implementation.
import '../models/employee.dart';

class DuplicateEmployeeException implements Exception {
  final String employeeId;
  DuplicateEmployeeException(this.employeeId);
  @override
  String toString() => 'Employee "$employeeId" already exists';
}

abstract class EmployeeRepository {
  Future<void> add(Employee employee);
  Future<void> update(Employee employee);
  Future<Employee?> getById(String employeeId);
  Future<bool> exists(String employeeId);
  Future<List<Employee>> getAll();
  Future<List<Employee>> getActive();
  Future<void> delete(String employeeId);
}

class InMemoryEmployeeRepository implements EmployeeRepository {
  final Map<String, Employee> _store = {};

  @override
  Future<void> add(Employee employee) async {
    if (_store.containsKey(employee.employeeId)) {
      throw DuplicateEmployeeException(employee.employeeId);
    }
    _store[employee.employeeId] = employee;
  }

  @override
  Future<void> update(Employee employee) async {
    _store[employee.employeeId] = employee;
  }

  @override
  Future<Employee?> getById(String employeeId) async => _store[employeeId];

  @override
  Future<bool> exists(String employeeId) async =>
      _store.containsKey(employeeId);

  @override
  Future<List<Employee>> getAll() async => _store.values.toList();

  @override
  Future<List<Employee>> getActive() async =>
      _store.values.where((e) => e.activeStatus).toList();

  @override
  Future<void> delete(String employeeId) async => _store.remove(employeeId);
}
