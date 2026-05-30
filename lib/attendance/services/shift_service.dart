// Shift service (Phase 8) — define shifts, resolve the active shift, late check.
import '../models/enums.dart';
import '../models/shift.dart';
import '../repositories/shift_repository.dart';

class ShiftService {
  final ShiftRepository repository;
  ShiftService(this.repository);

  Future<void> defineShift(Shift shift) => repository.save(shift);
  Future<Shift?> getById(String shiftId) => repository.getById(shiftId);
  Future<List<Shift>> getAll() => repository.getAll();

  /// Resolves the shift for a check-in: the explicit [shiftId] if provided, else
  /// the first defined shift whose window contains [now].
  Future<Shift?> resolve(String? shiftId, DateTime now) async {
    if (shiftId != null) return repository.getById(shiftId);
    for (final s in await repository.getAll()) {
      if (s.isWithin(now)) return s;
    }
    return null;
  }

  /// Convenience: seed the four standard NHAI shifts.
  Future<void> seedStandardShifts() async {
    await defineShift(const Shift(
        shiftId: 'GEN',
        shiftName: 'General',
        shiftType: ShiftType.general,
        startMinute: 9 * 60,
        endMinute: 18 * 60));
    await defineShift(const Shift(
        shiftId: 'MOR',
        shiftName: 'Morning',
        shiftType: ShiftType.morning,
        startMinute: 6 * 60,
        endMinute: 14 * 60));
    await defineShift(const Shift(
        shiftId: 'EVE',
        shiftName: 'Evening',
        shiftType: ShiftType.evening,
        startMinute: 14 * 60,
        endMinute: 22 * 60));
    await defineShift(const Shift(
        shiftId: 'NIG',
        shiftName: 'Night',
        shiftType: ShiftType.night,
        startMinute: 22 * 60,
        endMinute: 6 * 60));
  }
}
