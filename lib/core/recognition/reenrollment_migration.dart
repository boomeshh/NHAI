// Automatic re-enrollment migration.
//
// Stored face templates carry no pipeline-version tag, so provenance is
// inferred from the embedding itself. The current recognition pipeline always
// produces a fixed-dimension, L2-normalized (magnitude ≈ 1.0) embedding from an
// eye-aligned crop. A stored template that does NOT match those invariants was
// produced by an older pipeline (different model dimension, or pre-alignment /
// pre-normalization) and CANNOT be reconciled by re-computation — the original
// face image is not retained — so the employee must re-enroll.
import '../storage_manager/storage_manager_interface.dart';
import 'embedding_math.dart';

/// Bump when the recognition pipeline changes in a way that invalidates stored
/// templates (model, alignment, normalization, input format).
const int kRecognitionPipelineVersion = 3;

class StaleEnrollment {
  final String employeeId;
  final int storedLength;
  final double storedMagnitude;
  final String reason;

  const StaleEnrollment({
    required this.employeeId,
    required this.storedLength,
    required this.storedMagnitude,
    required this.reason,
  });
}

class ReEnrollmentMigration {
  /// The current model's embedding dimension (e.g. 192 for the bundled model).
  final int expectedDimension;

  /// Tolerance around unit magnitude for "modern, L2-normalized" templates.
  final double unitTolerance;

  const ReEnrollmentMigration({
    required this.expectedDimension,
    this.unitTolerance = 0.05,
  });

  /// Returns the stored templates that must be re-enrolled, with the reason.
  Future<List<StaleEnrollment>> scan(StorageManagerInterface storage) async {
    final result = <StaleEnrollment>[];
    for (final r in await storage.getAllEmployeeRecords()) {
      final v = r.embedding.vector;
      final mag = EmbeddingMath.magnitude(v);
      String? reason;
      if (v.length != expectedDimension) {
        reason = 'wrong embedding dimension (${v.length} vs $expectedDimension)'
            ' — enrolled on a different model';
      } else if (!EmbeddingMath.isUsable(v)) {
        reason = 'corrupt / degenerate embedding';
      } else if ((mag - 1.0).abs() > unitTolerance) {
        reason = 'not L2-normalized (magnitude ${mag.toStringAsFixed(3)})'
            ' — enrolled before the alignment/normalization pipeline';
      }
      if (reason != null) {
        result.add(StaleEnrollment(
          employeeId: r.employeeId,
          storedLength: v.length,
          storedMagnitude: mag,
          reason: reason,
        ));
      }
    }
    return result;
  }

  /// Deletes every stale template so the employee is forced to re-enroll with
  /// the current pipeline. Returns the purged employee IDs.
  Future<List<String>> purgeStale(StorageManagerInterface storage) async {
    final stale = await scan(storage);
    for (final s in stale) {
      await storage.deleteEmployeeRecord(s.employeeId);
    }
    return stale.map((s) => s.employeeId).toList();
  }
}
