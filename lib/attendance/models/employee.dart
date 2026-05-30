// Employee profile (Phase 2). The face embedding is stored ONLY as an encrypted
// blob — never as plaintext biometric data (Phase 12).

class Employee {
  final String employeeId;
  final String employeeCode;
  final String fullName;
  final String designation;
  final String department;
  final String mobileNumber;
  final DateTime joiningDate;
  final bool activeStatus;

  /// Encrypted face-embedding blob (see FieldEncryptor). Never plaintext.
  final String faceEmbeddingEncrypted;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Employee({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.designation,
    required this.department,
    required this.mobileNumber,
    required this.joiningDate,
    required this.activeStatus,
    required this.faceEmbeddingEncrypted,
    required this.createdAt,
    required this.updatedAt,
    this.photoPath,
  });

  Employee copyWith({
    String? employeeCode,
    String? fullName,
    String? designation,
    String? department,
    String? mobileNumber,
    DateTime? joiningDate,
    bool? activeStatus,
    String? faceEmbeddingEncrypted,
    String? photoPath,
    DateTime? updatedAt,
  }) =>
      Employee(
        employeeId: employeeId,
        employeeCode: employeeCode ?? this.employeeCode,
        fullName: fullName ?? this.fullName,
        designation: designation ?? this.designation,
        department: department ?? this.department,
        mobileNumber: mobileNumber ?? this.mobileNumber,
        joiningDate: joiningDate ?? this.joiningDate,
        activeStatus: activeStatus ?? this.activeStatus,
        faceEmbeddingEncrypted:
            faceEmbeddingEncrypted ?? this.faceEmbeddingEncrypted,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeCode': employeeCode,
        'fullName': fullName,
        'designation': designation,
        'department': department,
        'mobileNumber': mobileNumber,
        'joiningDate': joiningDate.toIso8601String(),
        'activeStatus': activeStatus,
        'faceEmbeddingEncrypted': faceEmbeddingEncrypted,
        'photoPath': photoPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        employeeId: j['employeeId'] as String,
        employeeCode: j['employeeCode'] as String,
        fullName: j['fullName'] as String,
        designation: j['designation'] as String,
        department: j['department'] as String,
        mobileNumber: j['mobileNumber'] as String,
        joiningDate: DateTime.parse(j['joiningDate'] as String),
        activeStatus: j['activeStatus'] as bool,
        faceEmbeddingEncrypted: j['faceEmbeddingEncrypted'] as String,
        photoPath: j['photoPath'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}
