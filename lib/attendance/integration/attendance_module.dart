// Composition root for the attendance engine (integration wiring). Bundles the
// repositories and services and bridges employees from the biometric store.
//
// This phase uses in-memory repositories (session-scoped). The repository
// interfaces already support Hive-backed implementations for durable offline
// storage — a drop-in swap with no service changes.
import '../../core/storage_manager/storage_manager_interface.dart';
import '../persistence/secure_database.dart';
import '../repositories/anomaly_repository.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/audit_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/persistent_attendance_repository.dart';
import '../repositories/persistent_audit_repository.dart';
import '../repositories/shift_repository.dart';
import '../services/anomaly_detector.dart';
import '../services/attendance_engine.dart';
import '../services/audit_service.dart';
import '../services/dashboard_service.dart';
import '../services/id_generator.dart';
import '../services/report_service.dart';
import '../services/shift_service.dart';
import '../sync/persistent_sync_queue.dart';
import '../sync/sync_interfaces.dart';
import '../sync/sync_purge_engine.dart';
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
  final SyncPurgeEngine syncPurgeEngine;

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
    required this.syncPurgeEngine,
  });

  /// Wires the attendance engine over in-memory repositories, bridging the
  /// employee directory to the existing biometric [storage]. Session-scoped.
  factory AttendanceModule.inMemory({
    required StorageManagerInterface storage,
    String deviceId = 'NHAI-DEVICE',
    SyncProvider? syncProvider,
  }) {
    return _assemble(
      employees: StorageEmployeeAdapter(storage),
      attendance: InMemoryAttendanceRepository(),
      auditRepo: InMemoryAuditRepository(),
      shiftRepo: InMemoryShiftRepository(),
      anomalyRepo: InMemoryAnomalyRepository(),
      queue: InMemorySyncQueue(),
      deviceId: deviceId,
      syncProvider: syncProvider,
    );
  }

  /// Wires the attendance engine over DURABLE, encrypted storage. Attendance,
  /// the sync queue, and the audit trail are persisted via [database]
  /// (SQLCipher on-device); shifts/anomalies remain session-scoped and
  /// employees are bridged from the biometric [storage]. Initializes the
  /// database before returning.
  static Future<AttendanceModule> persistent({
    required SecureDatabase database,
    required StorageManagerInterface storage,
    String deviceId = 'NHAI-DEVICE',
    SyncProvider? syncProvider,
  }) async {
    await database.init();
    return _assemble(
      employees: StorageEmployeeAdapter(storage),
      attendance: PersistentAttendanceRepository(database),
      auditRepo: PersistentAuditRepository(database),
      shiftRepo: InMemoryShiftRepository(),
      anomalyRepo: InMemoryAnomalyRepository(),
      queue: PersistentSyncQueue(database),
      deviceId: deviceId,
      syncProvider: syncProvider,
    );
  }

  /// Shared assembly of services, engine, dashboard, reports, coordinator and
  /// the sync/purge engine over the provided (backend-agnostic) repositories.
  static AttendanceModule _assemble({
    required EmployeeRepository employees,
    required AttendanceRepository attendance,
    required AuditRepository auditRepo,
    required ShiftRepository shiftRepo,
    required AnomalyRepository anomalyRepo,
    required SyncQueue queue,
    required String deviceId,
    SyncProvider? syncProvider,
  }) {
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
    final syncPurgeEngine = SyncPurgeEngine(
      queue: queue,
      attendance: attendance,
      provider: syncProvider,
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
      syncPurgeEngine: syncPurgeEngine,
    );
  }
}
