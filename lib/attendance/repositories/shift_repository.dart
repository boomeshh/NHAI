// Shift repository (Phase 8).
import '../models/shift.dart';

abstract class ShiftRepository {
  Future<void> save(Shift shift);
  Future<Shift?> getById(String shiftId);
  Future<List<Shift>> getAll();
}

class InMemoryShiftRepository implements ShiftRepository {
  final Map<String, Shift> _store = {};

  @override
  Future<void> save(Shift shift) async => _store[shift.shiftId] = shift;

  @override
  Future<Shift?> getById(String shiftId) async => _store[shiftId];

  @override
  Future<List<Shift>> getAll() async => _store.values.toList();
}
