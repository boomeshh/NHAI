import '../camera_frame.dart';
import '../recognition/embedding_math.dart';
import '../../models/employee_record.dart';
import '../../models/face_embedding.dart';
import '../auth_engine/auth_engine_interface.dart';
import '../auth_engine/embedding_error.dart';
import '../storage_manager/storage_manager_interface.dart';
import 'enrollment_module_interface.dart';

/// Concrete implementation of [EnrollmentModuleInterface].
///
/// Task 6.1 covers [validateForm].
/// Task 6.4 covers [selectBestFrame] and [enroll].
class EnrollmentModuleImpl implements EnrollmentModuleInterface {
  final AuthEngineInterface? _authEngine;
  final StorageManagerInterface? _storage;

  /// Creates an [EnrollmentModuleImpl].
  ///
  /// [authEngine] and [storage] are required for [enroll]; they may be omitted
  /// when only [validateForm] or [selectBestFrame] is needed (e.g., in tests
  /// that do not exercise the full enrollment flow).
  EnrollmentModuleImpl({
    AuthEngineInterface? authEngine,
    StorageManagerInterface? storage,
  })  : _authEngine = authEngine,
        _storage = storage;
  static const int _maxEmployeeIdLength = 20;
  static const int _maxNameLength = 60;
  static const int _maxDepartmentLength = 60;

  /// Alphanumeric pattern: letters and digits only.
  static final RegExp _alphanumeric = RegExp(r'^[a-zA-Z0-9]+$');

  /// Validates and sanitizes the enrollment form inputs.
  ///
  /// Sanitization: all fields are trimmed before validation and storage.
  ///
  /// Rules:
  /// - Employee ID: required, alphanumeric only, max [_maxEmployeeIdLength] chars.
  /// - Name: required, max [_maxNameLength] chars.
  /// - Department: required, max [_maxDepartmentLength] chars.
  ///
  /// Returns a [ValidationResult] with [ValidationResult.isValid] == true when
  /// all constraints pass, or with field-level errors otherwise.
  @override
  ValidationResult validateForm(
      String employeeId, String name, String department) {
    final trimmedId = employeeId.trim();
    final trimmedName = name.trim();
    final trimmedDepartment = department.trim();

    final errors = <String, String>{};

    // --- Employee ID ---
    if (trimmedId.isEmpty) {
      errors['employeeId'] = 'Employee ID is required.';
    } else if (!_alphanumeric.hasMatch(trimmedId)) {
      errors['employeeId'] =
          'Employee ID must contain only letters and digits.';
    } else if (trimmedId.length > _maxEmployeeIdLength) {
      errors['employeeId'] =
          'Employee ID must not exceed $_maxEmployeeIdLength characters.';
    }

    // --- Name ---
    if (trimmedName.isEmpty) {
      errors['name'] = 'Name is required.';
    } else if (trimmedName.length > _maxNameLength) {
      errors['name'] = 'Name must not exceed $_maxNameLength characters.';
    }

    // --- Department ---
    if (trimmedDepartment.isEmpty) {
      errors['department'] = 'Department is required.';
    } else if (trimmedDepartment.length > _maxDepartmentLength) {
      errors['department'] =
          'Department must not exceed $_maxDepartmentLength characters.';
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      fieldErrors: errors,
    );
  }

  /// Selects the frame with the strictly highest sharpness score from [frames].
  ///
  /// [frames] must be non-empty; throws [ArgumentError] otherwise.
  ///
  /// When multiple frames share the same maximum sharpness score the first
  /// such frame (lowest index) is returned, which satisfies the "strictly
  /// highest" requirement because no other frame has a *higher* score.
  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) {
    if (frames.isEmpty) {
      throw ArgumentError.value(frames, 'frames', 'frames must not be empty');
    }
    CameraFrame best = frames.first;
    for (int i = 1; i < frames.length; i++) {
      if (frames[i].sharpnessScore > best.sharpnessScore) {
        best = frames[i];
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Human-readable messages for embedding errors
  // ---------------------------------------------------------------------------

  static String _embeddingErrorMessage(EmbeddingError e) {
    switch (e.code) {
      case EmbeddingErrorCode.noFaceDetected:
        return 'No face was detected in the captured frame. '
            'Please position your face within the guide and try again.';
      case EmbeddingErrorCode.lowQualityFrame:
        return 'The captured frame quality is too low. '
            'Please ensure good lighting and hold the device steady, then retry.';
      case EmbeddingErrorCode.modelInferenceFailed:
        return 'Face embedding extraction failed due to an internal error. '
            'Please retry the capture.';
    }
  }

  /// Orchestrates the full enrollment flow.
  ///
  /// Steps:
  /// 1. Validate and sanitize [formData] fields.
  /// 2. Check for a duplicate Employee ID via [StorageManagerInterface.employeeExists].
  /// 3. Select the best frame from [frames] using [selectBestFrame].
  /// 4. Extract a face embedding via [AuthEngineInterface.extractEmbedding].
  /// 5. Build and persist an [EmployeeRecord] via [StorageManagerInterface.saveEmployeeRecord].
  ///
  /// Returns an [EnrollmentResult] with [EnrollmentResult.success] == true and
  /// the saved [EmployeeRecord] on success, or with a descriptive
  /// [EnrollmentResult.errorMessage] on any failure.
  ///
  /// On embedding extraction failure the caller is offered a retry by
  /// including a retry hint in the error message.
  ///
  /// On storage write failure no success screen is shown; the error is
  /// surfaced and no partial record is left in the store (the storage layer
  /// guarantees atomicity per Requirement 5.4).
  @override
  Future<EnrollmentResult> enroll(
      EmployeeFormData formData, List<CameraFrame> frames) async {
    assert(_authEngine != null,
        'AuthEngineInterface must be provided to use enroll()');
    assert(_storage != null,
        'StorageManagerInterface must be provided to use enroll()');

    // 1. Validate inputs.
    final validation =
        validateForm(formData.employeeId, formData.name, formData.department);
    if (!validation.isValid) {
      final messages = validation.fieldErrors.values.join(' ');
      return EnrollmentResult(
        success: false,
        errorMessage: messages,
      );
    }

    // Sanitized values (mirrors validateForm trimming).
    final trimmedId = formData.employeeId.trim();
    final trimmedName = formData.name.trim();
    final trimmedDepartment = formData.department.trim();

    // 2. Duplicate check (Requirement 3.3).
    final bool exists = await _storage!.employeeExists(trimmedId);
    if (exists && !formData.allowOverwrite) {
      return EnrollmentResult(
        success: false,
        errorMessage: 'An employee with ID "$trimmedId" already exists. '
            'Please confirm overwrite or use a different ID.',
      );
    }

    // 3. Select best frame (Requirement 4.4).
    if (frames.isEmpty) {
      return EnrollmentResult(
        success: false,
        errorMessage: 'No frames were captured. Please retry the face capture.',
      );
    }
    final CameraFrame bestFrame = selectBestFrame(frames);

    // 3b. Fail-closed face-count gate (set by the camera screen's detector).
    if (bestFrame.faceCount == 0) {
      return const EnrollmentResult(
        success: false,
        errorMessage: 'No face detected. Please position your face within the '
            'guide and try again.',
      );
    }
    if (bestFrame.faceCount > 1) {
      return const EnrollmentResult(
        success: false,
        errorMessage: 'Multiple faces detected. Ensure only one person is in '
            'frame and try again.',
      );
    }

    // 4. Extract & AVERAGE embeddings across all captured frames (Phase 7).
    //    A multi-frame, L2-normalized average is a far more stable enrollment
    //    template than a single frame, which raises genuine match scores.
    final FaceEmbedding embedding;
    try {
      final vectors = <List<double>>[];
      EmbeddingError? lastError;
      for (final f in frames) {
        try {
          final e = await _authEngine!.extractEmbedding(f);
          if (EmbeddingMath.isUsable(e.vector)) vectors.add(e.vector);
        } on EmbeddingError catch (e) {
          lastError = e;
        }
      }
      if (vectors.isEmpty) {
        // No usable frame — surface the most informative error.
        if (lastError != null) {
          return EnrollmentResult(
              success: false, errorMessage: _embeddingErrorMessage(lastError));
        }
        // Fall back to the single best frame (also throws on failure).
        embedding = await _authEngine!.extractEmbedding(bestFrame);
      } else {
        embedding = FaceEmbedding(EmbeddingMath.averageNormalized(vectors));
      }
    } on EmbeddingError catch (e) {
      return EnrollmentResult(
        success: false,
        errorMessage: _embeddingErrorMessage(e),
      );
    } catch (e) {
      return EnrollmentResult(
        success: false,
        errorMessage: 'An unexpected error occurred during face capture. '
            'Please retry.',
      );
    }

    // 4b. Phase 4 — never persist a corrupt / degenerate template.
    if (!EmbeddingMath.isUsable(embedding.vector)) {
      return const EnrollmentResult(
        success: false,
        errorMessage: 'Face capture quality was too low. Please retry.',
      );
    }

    // 5. Persist record (Requirements 5.2, 5.3, 5.4).
    final record = EmployeeRecord(
      employeeId: trimmedId,
      name: trimmedName,
      department: trimmedDepartment,
      embedding: embedding,
      enrolledAt: DateTime.now().toUtc(),
    );

    try {
      await _storage!.saveEmployeeRecord(record);
    } catch (e) {
      // Do NOT show success screen; surface the error (Requirement 5.4).
      return EnrollmentResult(
        success: false,
        errorMessage: 'Failed to save the enrollment record. '
            'Please try again. (${e.toString()})',
      );
    }

    return EnrollmentResult(success: true, record: record);
  }
}
