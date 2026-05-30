// Employee profile service (Phase 2 + Phase 12). Validates input, enforces
// unique IDs, and stores the face embedding ONLY as an encrypted blob.
import '../models/employee.dart';
import '../models/enums.dart';
import '../repositories/employee_repository.dart';
import '../security/field_encryptor.dart';
import 'audit_service.dart';
import 'id_generator.dart';

class EmployeeValidationException implements Exception {
  final List<String> errors;
  EmployeeValidationException(this.errors);
  @override
  String toString() => 'Invalid employee: ${errors.join('; ')}';
}

class EmployeeService {
  final EmployeeRepository repository;
  final AuditService audit;
  final BiometricCodec codec;
  final IdGenerator ids;

  static final RegExp _mobile = RegExp(r'^[0-9]{10}$');

  EmployeeService({
    required this.repository,
    required this.audit,
    required this.codec,
    required this.ids,
  });

  Future<Employee> create({
    required String employeeCode,
    required String fullName,
    required String designation,
    required String department,
    required String mobileNumber,
    required DateTime joiningDate,
    required List<double> faceEmbedding,
    required DateTime now,
    String? employeeId,
    String? photoPath,
    bool activeStatus = true,
  }) async {
    final id = employeeId ?? ids.next('EMP');
    _validate(
      employeeCode: employeeCode,
      fullName: fullName,
      department: department,
      mobileNumber: mobileNumber,
      faceEmbedding: faceEmbedding,
    );
    if (await repository.exists(id)) {
      throw DuplicateEmployeeException(id);
    }

    final employee = Employee(
      employeeId: id,
      employeeCode: employeeCode.trim(),
      fullName: fullName.trim(),
      designation: designation.trim(),
      department: department.trim(),
      mobileNumber: mobileNumber.trim(),
      joiningDate: joiningDate,
      activeStatus: activeStatus,
      faceEmbeddingEncrypted: codec.encode(faceEmbedding),
      photoPath: photoPath,
      createdAt: now,
      updatedAt: now,
    );
    await repository.add(employee);
    await audit.record(AuditEventType.employeeCreated, now,
        employeeId: id, details: {'employeeCode': employee.employeeCode});
    return employee;
  }

  Future<Employee> update(
    String employeeId,
    DateTime now, {
    String? designation,
    String? department,
    String? mobileNumber,
    bool? activeStatus,
  }) async {
    final existing = await repository.getById(employeeId);
    if (existing == null) {
      throw EmployeeValidationException(['Employee "$employeeId" not found']);
    }
    if (mobileNumber != null && !_mobile.hasMatch(mobileNumber)) {
      throw EmployeeValidationException(['mobileNumber must be 10 digits']);
    }
    final updated = existing.copyWith(
      designation: designation,
      department: department,
      mobileNumber: mobileNumber,
      activeStatus: activeStatus,
      updatedAt: now,
    );
    await repository.update(updated);
    await audit.record(AuditEventType.employeeUpdated, now,
        employeeId: employeeId);
    return updated;
  }

  /// Decrypts and returns an employee's enrolled embedding for matching.
  List<double> embeddingOf(Employee e) =>
      codec.decode(e.faceEmbeddingEncrypted);

  void _validate({
    required String employeeCode,
    required String fullName,
    required String department,
    required String mobileNumber,
    required List<double> faceEmbedding,
  }) {
    final errors = <String>[];
    if (employeeCode.trim().isEmpty) errors.add('employeeCode is required');
    if (fullName.trim().isEmpty) errors.add('fullName is required');
    if (department.trim().isEmpty) errors.add('department is required');
    if (!_mobile.hasMatch(mobileNumber.trim())) {
      errors.add('mobileNumber must be 10 digits');
    }
    if (faceEmbedding.isEmpty) errors.add('faceEmbedding is required');
    if (errors.isNotEmpty) throw EmployeeValidationException(errors);
  }
}
