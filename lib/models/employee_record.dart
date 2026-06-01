import 'face_embedding.dart';
import 'face_template.dart';

class EmployeeRecord {
  final String employeeId; // alphanumeric, max 20 chars
  final String name; // max 60 chars
  final String department; // max 60 chars
  final FaceEmbedding embedding; // primary/frontal template (backward compat)
  final DateTime enrolledAt; // UTC

  /// Multi-pose gallery (frontal/left/right/up/down). Null/absent for legacy
  /// single-template employees enrolled before the multi-pose upgrade — those
  /// continue to match via [embedding].
  final List<FaceTemplate>? templates;

  const EmployeeRecord({
    required this.employeeId,
    required this.name,
    required this.department,
    required this.embedding,
    required this.enrolledAt,
    this.templates,
  });

  /// True when this record carries a multi-pose gallery.
  bool get hasGallery => templates != null && templates!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'department': department,
        'embedding': embedding.toJson(),
        'enrolledAt': enrolledAt.toUtc().toIso8601String(),
        // Omitted when null so legacy records serialize byte-identically.
        if (templates != null)
          'templates': templates!.map((t) => t.toJson()).toList(),
      };

  factory EmployeeRecord.fromJson(Map<String, dynamic> json) => EmployeeRecord(
        employeeId: json['employeeId'] as String,
        name: json['name'] as String,
        department: json['department'] as String,
        embedding:
            FaceEmbedding.fromJson(json['embedding'] as Map<String, dynamic>),
        enrolledAt: DateTime.parse(json['enrolledAt'] as String).toUtc(),
        templates: json['templates'] == null
            ? null
            : (json['templates'] as List)
                .map((e) => FaceTemplate.fromJson(e as Map<String, dynamic>))
                .toList(),
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
