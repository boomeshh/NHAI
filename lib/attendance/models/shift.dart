// Shift definition (Phase 8). Times are stored as minutes-from-midnight for
// straightforward comparison; night shifts may wrap past midnight.
import 'enums.dart';

class Shift {
  final String shiftId;
  final String shiftName;
  final ShiftType shiftType;

  /// Start/end as minutes from midnight [0, 1440).
  final int startMinute;
  final int endMinute;

  /// Grace period (minutes) before a check-in is flagged late.
  final int graceMinutes;

  const Shift({
    required this.shiftId,
    required this.shiftName,
    required this.shiftType,
    required this.startMinute,
    required this.endMinute,
    this.graceMinutes = 10,
  });

  bool get wrapsMidnight => endMinute <= startMinute;

  int _minuteOfDay(DateTime t) => t.hour * 60 + t.minute;

  /// Whether [t]'s time-of-day falls within the shift window.
  bool isWithin(DateTime t) {
    final m = _minuteOfDay(t);
    if (wrapsMidnight) {
      return m >= startMinute || m < endMinute;
    }
    return m >= startMinute && m < endMinute;
  }

  /// Whether a check-in at [t] is late (past start + grace).
  bool isLateCheckIn(DateTime t) {
    final m = _minuteOfDay(t);
    final lateAfter = startMinute + graceMinutes;
    if (wrapsMidnight) {
      // Within the evening portion of a night shift.
      if (m >= startMinute) return m > lateAfter;
      return false; // after-midnight portion is not "late" by start time
    }
    return m > lateAfter;
  }

  Map<String, dynamic> toJson() => {
        'shiftId': shiftId,
        'shiftName': shiftName,
        'shiftType': shiftType.name,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'graceMinutes': graceMinutes,
      };

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        shiftId: j['shiftId'] as String,
        shiftName: j['shiftName'] as String,
        shiftType: enumByName(
            ShiftType.values, j['shiftType'] as String?, ShiftType.general),
        startMinute: j['startMinute'] as int,
        endMinute: j['endMinute'] as int,
        graceMinutes: (j['graceMinutes'] as int?) ?? 10,
      );
}
