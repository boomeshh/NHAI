import '../../models/employee_record.dart';
import '../../models/face_pose.dart';
import '../camera_frame.dart';

class ValidationResult {
  final bool isValid;
  final Map<String, String> fieldErrors; // field name -> error message
  const ValidationResult({required this.isValid, this.fieldErrors = const {}});
}

class EmployeeFormData {
  final String employeeId;
  final String name;
  final String department;
  final bool allowOverwrite;
  const EmployeeFormData({
    required this.employeeId,
    required this.name,
    required this.department,
    this.allowOverwrite = false,
  });
}

class EnrollmentResult {
  final bool success;
  final EmployeeRecord? record;
  final String? errorMessage;
  const EnrollmentResult({
    required this.success,
    this.record,
    this.errorMessage,
  });
}

abstract class EnrollmentModuleInterface {
  ValidationResult validateForm(
      String employeeId, String name, String department);
  CameraFrame selectBestFrame(List<CameraFrame> frames);
  Future<EnrollmentResult> enroll(
      EmployeeFormData formData, List<CameraFrame> frames);

  /// Multi-pose enrollment: builds one averaged [FaceTemplate] per captured
  /// pose and stores them as the employee's gallery (frontal also mirrored into
  /// the legacy single-embedding field for backward compatibility).
  Future<EnrollmentResult> enrollMultiPose(
      EmployeeFormData formData, Map<FacePose, List<CameraFrame>> posedFrames);
}
