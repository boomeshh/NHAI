import 'auth_result.dart';

class AuthLogEntry {
  final String id; // UUID
  final DateTime timestamp; // ISO 8601 UTC
  final AuthClassification result;
  final double trustScore;
  final String? employeeId; // null if no match
  final String? failureReason; // null if VERIFIED

  const AuthLogEntry({
    required this.id,
    required this.timestamp,
    required this.result,
    required this.trustScore,
    this.employeeId,
    this.failureReason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'result': result.name,
        'trustScore': trustScore,
        'employeeId': employeeId,
        'failureReason': failureReason,
      };

  factory AuthLogEntry.fromJson(Map<String, dynamic> json) => AuthLogEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
        result: AuthClassification.values.byName(json['result'] as String),
        trustScore: (json['trustScore'] as num).toDouble(),
        employeeId: json['employeeId'] as String?,
        failureReason: json['failureReason'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is AuthLogEntry &&
      id == other.id &&
      timestamp.isAtSameMomentAs(other.timestamp) &&
      result == other.result &&
      trustScore == other.trustScore &&
      employeeId == other.employeeId &&
      failureReason == other.failureReason;

  @override
  int get hashCode =>
      Object.hash(id, timestamp, result, trustScore, employeeId, failureReason);
}
