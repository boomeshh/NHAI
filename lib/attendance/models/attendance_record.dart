// AttendanceRecord (Phase 3) and AttendanceSession (open check-in view).
import 'enums.dart';

class AttendanceRecord {
  final String attendanceId;
  final String employeeId;

  /// Calendar date (time component zeroed) the record belongs to.
  final DateTime date;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final VerificationMethod verificationMethod;
  final double trustScore;
  final String deviceId;
  final double? latitude;
  final double? longitude;
  final bool offlineMode;
  final SyncStatus syncStatus;
  final String? shiftId;
  final bool isLate;

  const AttendanceRecord({
    required this.attendanceId,
    required this.employeeId,
    required this.date,
    required this.checkInTime,
    required this.verificationMethod,
    required this.trustScore,
    required this.deviceId,
    required this.offlineMode,
    required this.syncStatus,
    this.checkOutTime,
    this.latitude,
    this.longitude,
    this.shiftId,
    this.isLate = false,
  });

  bool get isOpen => checkOutTime == null;

  AttendanceRecord copyWith({
    DateTime? checkOutTime,
    SyncStatus? syncStatus,
    bool? isLate,
  }) =>
      AttendanceRecord(
        attendanceId: attendanceId,
        employeeId: employeeId,
        date: date,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime ?? this.checkOutTime,
        verificationMethod: verificationMethod,
        trustScore: trustScore,
        deviceId: deviceId,
        latitude: latitude,
        longitude: longitude,
        offlineMode: offlineMode,
        syncStatus: syncStatus ?? this.syncStatus,
        shiftId: shiftId,
        isLate: isLate ?? this.isLate,
      );

  Map<String, dynamic> toJson() => {
        'attendanceId': attendanceId,
        'employeeId': employeeId,
        'date': date.toIso8601String(),
        'checkInTime': checkInTime.toIso8601String(),
        'checkOutTime': checkOutTime?.toIso8601String(),
        'verificationMethod': verificationMethod.name,
        'trustScore': trustScore,
        'deviceId': deviceId,
        'latitude': latitude,
        'longitude': longitude,
        'offlineMode': offlineMode,
        'syncStatus': syncStatus.name,
        'shiftId': shiftId,
        'isLate': isLate,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        attendanceId: j['attendanceId'] as String,
        employeeId: j['employeeId'] as String,
        date: DateTime.parse(j['date'] as String),
        checkInTime: DateTime.parse(j['checkInTime'] as String),
        checkOutTime: j['checkOutTime'] == null
            ? null
            : DateTime.parse(j['checkOutTime'] as String),
        verificationMethod: enumByName(VerificationMethod.values,
            j['verificationMethod'] as String?, VerificationMethod.face),
        trustScore: (j['trustScore'] as num).toDouble(),
        deviceId: j['deviceId'] as String,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        offlineMode: j['offlineMode'] as bool,
        syncStatus: enumByName(
            SyncStatus.values, j['syncStatus'] as String?, SyncStatus.pending),
        shiftId: j['shiftId'] as String?,
        isLate: (j['isLate'] as bool?) ?? false,
      );
}

/// A lightweight view of an employee's currently-open (checked-in) record.
class AttendanceSession {
  final String employeeId;
  final String attendanceId;
  final DateTime checkInTime;
  final String? shiftId;

  const AttendanceSession({
    required this.employeeId,
    required this.attendanceId,
    required this.checkInTime,
    this.shiftId,
  });

  factory AttendanceSession.fromRecord(AttendanceRecord r) => AttendanceSession(
        employeeId: r.employeeId,
        attendanceId: r.attendanceId,
        checkInTime: r.checkInTime,
        shiftId: r.shiftId,
      );
}
