// Suspicious-attendance anomaly event (Phase 9).
import 'enums.dart';

class AnomalyEvent {
  final String anomalyId;
  final AnomalyType type;
  final RiskLevel riskLevel;
  final String? employeeId;
  final DateTime timestamp;
  final String deviceId;
  final Map<String, dynamic> details;

  const AnomalyEvent({
    required this.anomalyId,
    required this.type,
    required this.riskLevel,
    required this.timestamp,
    required this.deviceId,
    this.employeeId,
    this.details = const {},
  });

  Map<String, dynamic> toJson() => {
        'anomalyId': anomalyId,
        'type': type.name,
        'riskLevel': riskLevel.name,
        'employeeId': employeeId,
        'timestamp': timestamp.toIso8601String(),
        'deviceId': deviceId,
        'details': details,
      };
}
