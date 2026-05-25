import 'face_embedding.dart';

class EmployeeRecord {
  final String employeeId; // alphanumeric, max 20 chars
  final String name; // max 60 chars
  final String department; // max 60 chars
  final FaceEmbedding embedding; // 128-dimensional float vector
  final DateTime enrolledAt; // UTC

  const EmployeeRecord({
    required this.employeeId,
    required this.name,
    required this.department,
    required this.embedding,
    required this.enrolledAt,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'department': department,
        'embedding': embedding.toJson(),
        'enrolledAt': enrolledAt.toUtc().toIso8601String(),
      };

  factory EmployeeRecord.fromJson(Map<String, dynamic> json) => EmployeeRecord(
        employeeId: json['employeeId'] as String,
        name: json['name'] as String,
        department: json['department'] as String,
        embedding:
            FaceEmbedding.fromJson(json['embedding'] as Map<String, dynamic>),
        enrolledAt: DateTime.parse(json['enrolledAt'] as String).toUtc(),
      );

  @override
  bool operator ==(Object other) =>
      other is EmployeeRecord &&
      employeeId == other.employeeId &&
      name == other.name &&
      department == other.department &&
      embedding == other.embedding &&
      enrolledAt.isAtSameMomentAs(other.enrolledAt);

  @override
  int get hashCode =>
      Object.hash(employeeId, name, department, embedding, enrolledAt);
}
