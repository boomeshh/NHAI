// Anomaly repository (Phase 9).
import '../models/anomaly_event.dart';

abstract class AnomalyRepository {
  Future<void> add(AnomalyEvent event);
  Future<List<AnomalyEvent>> getAll();
  Future<List<AnomalyEvent>> getByEmployee(String employeeId);
}

class InMemoryAnomalyRepository implements AnomalyRepository {
  final List<AnomalyEvent> _events = [];

  @override
  Future<void> add(AnomalyEvent event) async => _events.add(event);

  @override
  Future<List<AnomalyEvent>> getAll() async => List.unmodifiable(_events);

  @override
  Future<List<AnomalyEvent>> getByEmployee(String employeeId) async =>
      _events.where((e) => e.employeeId == employeeId).toList();
}
