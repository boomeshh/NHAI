// Domain enums for the NHAI Workforce Attendance Engine.

enum AttendanceEventType { checkIn, checkOut }

enum VerificationMethod { face, faceWithBlink, manual }

enum SyncStatus { pending, synced, failed }

enum RiskLevel { low, medium, high }

enum ShiftType { general, morning, evening, night }

enum AuditEventType {
  employeeCreated,
  employeeUpdated,
  attendanceMarked,
  attendanceFailed,
  authenticationFailed,
  syncCompleted,
  anomalyDetected,
}

enum AnomalyType {
  multipleCheckIn,
  outsideShift,
  repeatedVerificationFailure,
  locationMismatch,
  rapidRepeatedAuthentication,
}

/// Parses an enum [values] entry by its `.name`, falling back to [fallback].
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
