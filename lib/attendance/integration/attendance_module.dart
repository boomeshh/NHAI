// Composition root for the attendance engine (integration wiring). Bundles the
// repositories and services and bridges employees from the biometric store.
//
// This phase uses in-memory repositories (session-scoped). The repository
// interfaces already support Hive-backed implementations for durable offline
// storage — a drop-in swap with no service changes.
import '../../core/storage_manager/storage_manager_interface.dart';
import '../repositories/anomaly_repository.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/audit_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/shift_repository.dart';
import '../services/anomaly_detector.dart';
import '../services/attendance_engine.dart';
import '../services/audit_service.dart';
import '../services/dashboard_service.dart';
import '../services/id_generator.dart';
import '../services/report_service.dart';
import '../services/shift_service.dart';
import '../sync/sync_queue.dart';
import 'attendance_coordinator.dart';
import 'storage_employee_adapter.dart';

class AttendanceModule {
  final EmployeeRepository employees;
  final AttendanceRepository attendance;
  final AuditRepository auditRepository;
  final ShiftRepository shiftRepository;
  final AnomalyRepository anomalies;
  final SyncQueue syncQueue;

  final AuditService auditService;
  final ShiftService shiftService;
  final AnomalyDetector anomalyDetector;
  final AttendanceEngine engine;
  final DashboardService dashboard;
  final ReportService reports;
  final AttendanceCoordinator coordinator;

  AttendanceModule._({
    required this.employees,
    required this.attendance,
    required this.auditRepository,
    required this.shiftRepository,
    required this.anomalies,
    required this.syncQueue,
    required this.auditService,
    required this.shiftService,
    required this.anomalyDetector,
    required this.engine,
    required this.dashboard,
    required this.reports,
    required this.coordinator,
  });

  /// Wires the attendance engine over in-memory repositories, bridging the
  /// employee directory to the existing biometric [storage].
  factory AttendanceModule.inMemory({
    required StorageManagerInterface storage,
    String deviceId = 'NHAI-DEVICE',
  }) {
    final employees = StorageEmployeeAdapter(storage);
    final attendance = InMemoryAttendanceRepository();
    final auditRepo = InMemoryAuditRepository();
    final shiftRepo = InMemoryShiftRepository();
    final anomalyRepo = InMemoryAnomalyRepository();
    final queue = InMemorySyncQueue();
    final ids = IdGenerator('NHAI');

    final auditService =
        AuditService(repository: auditRepo, ids: ids, deviceId: deviceId);
    final shiftService = ShiftService(shiftRepo);
    final detector = AnomalyDetector(
      anomalies: anomalyRepo,
      auditRepository: auditRepo,
      audit: auditService,
      ids: ids,
      deviceId: deviceId,
    );
    final engine = AttendanceEngine(
      employees: employees,
      attendance: attendance,
      audit: auditService,
      shifts: shiftService,
      anomalyDetector: detector,
      syncQueue: queue,
      ids: ids,
      deviceId: deviceId,
    );
    final dashboard = DashboardService(
      employees: employees,
      attendance: attendance,
      auditRepository: auditRepo,
      syncQueue: queue,
    );
    final reports = ReportService(attendance: attendance);
    final coordinator = AttendanceCoordinator(
      engine: engine,
      attendance: attendance,
      deviceId: deviceId,
    );

    return AttendanceModule._(
      employees: employees,
      attendance: attendance,
      auditRepository: auditRepo,
      shiftRepository: shiftRepo,
      anomalies: anomalyRepo,
      syncQueue: queue,
      auditService: auditService,
      shiftService: shiftService,
      anomalyDetector: detector,
      engine: engine,
      dashboard: dashboard,
      reports: reports,
      coordinator: coordinator,
    );
  }
}
