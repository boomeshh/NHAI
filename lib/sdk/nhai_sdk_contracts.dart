// NHAI SDK — API contracts.
//
// Defines the wire format crossing the Flutter↔host (React Native) boundary:
// a uniform [SdkResult] envelope plus typed request parsers and response
// builders for the five public SDK methods. Everything here is pure,
// JSON-serializable, and host-agnostic — the same shapes travel over the
// platform channel and over the integration tests.
//
// This layer only *describes* the boundary. It does not modify face detection,
// recognition, the matcher, attendance, sync, or the dashboard.
library;

/// Stable method names exposed across the platform channel.
class SdkMethods {
  static const enrollEmployee = 'enrollEmployee';
  static const authenticateEmployee = 'authenticateEmployee';
  static const markAttendance = 'markAttendance';
  static const getAttendanceSummary = 'getAttendanceSummary';
  static const syncRecords = 'syncRecords';

  static const all = [
    enrollEmployee,
    authenticateEmployee,
    markAttendance,
    getAttendanceSummary,
    syncRecords,
  ];
}

/// Stable result codes the host can branch on (never localized).
class SdkCodes {
  static const ok = 'OK';
  static const validationError = 'VALIDATION_ERROR';
  static const notVerified = 'NOT_VERIFIED';
  static const notFound = 'NOT_FOUND';
  static const cancelled = 'CANCELLED';
  static const unknownMethod = 'UNKNOWN_METHOD';
  static const error = 'ERROR';
}

/// Uniform response envelope returned by every SDK method.
class SdkResult {
  final bool ok;
  final String code;
  final String? message;
  final Map<String, dynamic> data;

  const SdkResult({
    required this.ok,
    required this.code,
    this.message,
    this.data = const {},
  });

  factory SdkResult.success(Map<String, dynamic> data, {String? message}) =>
      SdkResult(ok: true, code: SdkCodes.ok, message: message, data: data);

  factory SdkResult.failure(String code, String message,
          {Map<String, dynamic> data = const {}}) =>
      SdkResult(ok: false, code: code, message: message, data: data);

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'code': code,
        if (message != null) 'message': message,
        'data': data,
      };

  factory SdkResult.fromJson(Map<String, dynamic> j) => SdkResult(
        ok: j['ok'] as bool,
        code: j['code'] as String,
        message: j['message'] as String?,
        data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}),
      );
}

/// Thrown by request parsers when a required argument is missing/invalid.
class SdkArgumentError implements Exception {
  final String message;
  SdkArgumentError(this.message);
  @override
  String toString() => 'SdkArgumentError: $message';
}

// ─── Request parsers ─────────────────────────────────────────────────────────

/// Coerces the platform-channel argument blob into a string-keyed map.
Map<String, dynamic> asArgs(Object? raw) {
  if (raw == null) return const {};
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw SdkArgumentError('Expected a map of arguments, got ${raw.runtimeType}');
}

String _requireString(Map<String, dynamic> a, String key) {
  final v = a[key];
  if (v is! String || v.isEmpty) {
    throw SdkArgumentError('Missing/empty required string "$key"');
  }
  return v;
}

/// enrollEmployee(employeeId, name, department, allowOverwrite?)
class EnrollRequest {
  final String employeeId;
  final String name;
  final String department;
  final bool allowOverwrite;

  const EnrollRequest({
    required this.employeeId,
    required this.name,
    required this.department,
    this.allowOverwrite = false,
  });

  factory EnrollRequest.parse(Map<String, dynamic> a) => EnrollRequest(
        employeeId: _requireString(a, 'employeeId'),
        name: _requireString(a, 'name'),
        department: _requireString(a, 'department'),
        allowOverwrite: a['allowOverwrite'] == true,
      );
}

/// markAttendance(forced? = 'checkIn'|'checkOut')
class MarkAttendanceRequest {
  /// Optional forced event; null ⇒ auto-resolve (turnstile).
  final String? forced;
  const MarkAttendanceRequest({this.forced});

  factory MarkAttendanceRequest.parse(Map<String, dynamic> a) =>
      MarkAttendanceRequest(forced: a['forced'] as String?);
}

/// getAttendanceSummary(scope = 'daily'|'monthly', date? ISO-8601)
class SummaryRequest {
  final String scope; // 'daily' | 'monthly'
  final DateTime date;

  const SummaryRequest({required this.scope, required this.date});

  factory SummaryRequest.parse(Map<String, dynamic> a, {required DateTime now}) {
    final scope = (a['scope'] as String?) ?? 'daily';
    final raw = a['date'] as String?;
    final date = raw == null ? now : DateTime.parse(raw);
    if (scope != 'daily' && scope != 'monthly') {
      throw SdkArgumentError('scope must be "daily" or "monthly"');
    }
    return SummaryRequest(scope: scope, date: date);
  }
}

/// syncRecords(purge? = bool)
class SyncRequest {
  final bool purge;
  const SyncRequest({this.purge = false});

  factory SyncRequest.parse(Map<String, dynamic> a) =>
      SyncRequest(purge: a['purge'] == true);
}
