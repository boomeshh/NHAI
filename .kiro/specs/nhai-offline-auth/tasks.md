# Implementation Plan: NHAI Offline Edge-AI Authentication Infrastructure — Phase 1 MVP

## Overview

Incremental implementation of the Flutter-based offline biometric authentication app. Tasks build from data models and module interfaces upward through storage, ML inference, liveness detection, UI screens, and final wiring. Each step integrates with the previous before moving forward.

## Tasks

- [x] 1. Define data models and core interfaces
  - Create `lib/models/employee_record.dart`, `face_embedding.dart`, `auth_result.dart`, `auth_log_entry.dart` with all fields and JSON serialization (`toJson`/`fromJson`)
  - Create abstract interface files: `auth_engine_interface.dart`, `enrollment_module_interface.dart`, `liveness_detector_interface.dart`, `storage_manager_interface.dart`
  - Add `pubspec.yaml` dependencies: `hive`, `hive_flutter`, `flutter_secure_storage`, `tflite_flutter`, `camera`, `uuid`
  - _Requirements: 10.1, 10.2, 10.3, 12.1, 12.3, 12.4_

  - [x] 1.1 Write property test for Employee_Record round-trip serialization
    - **Property 6: Employee_Record round-trip serialization**
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.4**

  - [x] 1.2 Write unit tests for model serialization edge cases
    - Test null-nullable fields, UTC timestamp round-trip, embedding vector length
    - _Requirements: 10.5_

- [x] 2. Implement Storage_Manager
  - [x] 2.1 Implement `StorageManagerImpl` using Hive with AES-256 encryption
    - On first launch, generate AES key via `flutter_secure_storage` and store in Android Keystore; never write key to Hive
    - Open two encrypted Hive boxes: `employee_records` (key = employeeId) and `auth_logs` (auto-increment)
    - Implement `saveEmployeeRecord` with transactional write: serialize to JSON → encrypt → write atomically; roll back on failure
    - Implement `getEmployeeRecord`, `getAllEmployeeRecords`, `employeeExists`, `deleteEmployeeRecord`
    - Implement `logAuthAttempt` with log rotation: after write, if count > 1000 delete oldest entry by timestamp
    - Implement `getAuthLogs` returning entries in reverse chronological order (most recent first), default limit 100
    - Implement `logStorageError` writing to an in-memory error buffer (not the encrypted store)
    - Corrupted records during `getAllEmployeeRecords` must be caught individually, skipped, and a storage error logged
    - _Requirements: 5.1, 5.2, 5.4, 5.5, 5.6, 9.1, 9.4, 9.5, 10.1, 10.2, 10.4, 10.5, 12.4_

  - [x] 2.2 Write property test for Employee_Record atomic write completeness
    - **Property 8: Employee_Record atomic write — all fields present on retrieval**
    - **Validates: Requirements 5.2**

  - [x] 2.3 Write property test for encrypted at rest
    - **Property 7: Stored data is encrypted at rest**
    - **Validates: Requirements 5.1, 9.5**

  - [x] 2.4 Write property test for log reverse chronological order
    - **Property 13: Log entries are retrieved in reverse chronological order**
    - **Validates: Requirements 9.2**

  - [x] 2.5 Write property test for log rotation cap
    - **Property 14: Log rotation maintains the 1000-entry cap**
    - **Validates: Requirements 9.4**

  - [x] 2.6 Write unit tests for Storage_Manager
    - Test write failure rollback (no partial record left), corrupted record skipping, encryption key unavailability error screen, 1000-entry boundary
    - _Requirements: 5.4, 10.5_

- [x] 3. Checkpoint — Ensure all storage tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement Auth_Engine
  - [x] 4.1 Implement `AuthEngineImpl` — embedding extraction
    - Load MobileFaceNet `.tflite` model from assets via `tflite_flutter`
    - Implement `extractEmbedding(CameraFrame frame)` returning a 128-dimensional `FaceEmbedding`
    - Return typed `EmbeddingError` (`NO_FACE_DETECTED`, `LOW_QUALITY_FRAME`, `MODEL_INFERENCE_FAILED`) on failure
    - _Requirements: 4.6, 4.7, 6.2_

  - [x] 4.2 Write property test for embedding dimensionality invariant
    - **Property 2: Embedding dimensionality invariant**
    - **Validates: Requirements 4.6, 6.2**

  - [x] 4.3 Implement `AuthEngineImpl` — cosine similarity and classification
    - Implement cosine similarity: `(a · b) / (||a|| × ||b||)`
    - Implement `authenticate(CameraFrame frame)`: extract live embedding → fetch all stored embeddings from `Storage_Manager` → compute cosine similarity against each → classify max score ≥ 0.75 as VERIFIED, < 0.75 as FAILED
    - If VERIFIED, invoke `Liveness_Detector.detectLiveness`; propagate `LivenessResult.failed` as overall FAILED with reason "Liveness check failed"
    - Return `AuthResult` with all four fields populated; complete within 2 seconds
    - Make zero network calls
    - _Requirements: 6.3, 6.4, 6.5, 6.6, 6.7, 7.1, 12.3_

  - [x] 4.4 Write property test for classification threshold
    - **Property 1: Classification threshold is a total function**
    - **Validates: Requirements 6.4, 6.5**

  - [x] 4.5 Write property test for liveness trigger condition
    - **Property 9: Liveness challenge is triggered if and only if face verification is VERIFIED**
    - **Validates: Requirements 7.1**

  - [x] 4.6 Write property test for Auth_Engine complete result
    - **Property 16: Auth_Engine always returns a complete structured result**
    - **Validates: Requirements 12.3**

  - [x] 4.7 Write property test for no network calls
    - **Property 15: No network calls during any core operation**
    - **Validates: Requirements 6.7, 7.6, 11.2**

  - [x] 4.8 Write unit tests for Auth_Engine
    - Test known face pairs with known similarity scores, embedding extraction errors, liveness failure propagation, 2-second performance constraint
    - _Requirements: 6.4, 6.5, 6.6, 7.1_

- [x] 5. Implement Liveness_Detector
  - [x] 5.1 Implement `LivenessDetectorImpl` using MediaPipe Face Mesh
    - Process `Stream<CameraFrame>` to extract eye landmark coordinates (p1–p6) per frame
    - Compute EAR: `(||p2-p6|| + ||p3-p5||) / (2 × ||p1-p4||)`
    - Confirm blink when EAR drops below 0.25 and recovers above 0.25 within 400 ms → return `LivenessResult.confirmed`
    - Resolve with `LivenessResult.failed` if no valid blink within 5-second timeout
    - Make zero network calls
    - _Requirements: 7.2, 7.3, 7.4, 7.6_

  - [x] 5.2 Write property test for blink EAR classification
    - **Property 10: Blink detection correctly classifies EAR sequences**
    - **Validates: Requirements 7.3, 7.4**

  - [x] 5.3 Write unit tests for Liveness_Detector
    - Test known EAR sequences (valid blink, too slow, never drops, recovers too late), 5-second timeout
    - _Requirements: 7.3, 7.4_

- [x] 6. Implement Enrollment_Module
  - [x] 6.1 Implement `EnrollmentModuleImpl` — form validation and sanitization
    - Implement `validateForm`: reject if any of Employee ID, Name, Department is empty or whitespace-only; return field-level errors
    - Sanitize all inputs by trimming leading/trailing whitespace before use
    - Enforce field constraints: Employee ID alphanumeric max 20 chars, Name max 60 chars, Department max 60 chars
    - _Requirements: 3.1, 3.2, 3.4_

  - [x] 6.2 Write property test for input sanitization
    - **Property 4: Input sanitization removes surrounding whitespace**
    - **Validates: Requirements 3.4**

  - [x] 6.3 Write property test for empty field validation
    - **Property 5: Empty field validation rejects incomplete submissions**
    - **Validates: Requirements 3.2**

  - [x] 6.4 Implement `EnrollmentModuleImpl` — frame selection and enrollment orchestration
    - Implement `selectBestFrame`: return the frame with the strictly highest sharpness score from a non-empty list
    - Implement `enroll`: validate → check duplicate via `Storage_Manager.employeeExists` → capture frames → select best → extract embedding via `Auth_Engine` → save `EmployeeRecord` via `Storage_Manager`
    - On embedding extraction failure, return descriptive error; offer retry
    - On storage write failure, do not show success screen; display error
    - _Requirements: 3.3, 4.4, 4.5, 4.7, 5.3, 5.4_

  - [x] 6.5 Write property test for best frame selection
    - **Property 3: Best frame selection is a maximum**
    - **Validates: Requirements 4.4**

  - [x] 6.6 Write unit tests for Enrollment_Module
    - Test duplicate ID warning, empty field rejection, storage failure (no partial record), embedding failure retry, sharpness selection with ties
    - _Requirements: 3.2, 3.3, 4.5, 4.7, 5.4_

- [x] 7. Checkpoint — Ensure all module tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Build UI screens — Splash and Home
  - [x] 8.1 Implement `SplashScreen`
    - Display for 2–3 seconds then navigate to `HomeScreen`
    - Show "Offline Workforce Authentication System", "Powered by Edge AI", NHAI logo and name
    - Use Deep Blue (#003580) background, White (#FFFFFF) text, Saffron (#FF6600) accent
    - Show minimal progress indicator during splash duration
    - If assets fail to load within 5 seconds, display fallback error with retry option
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

  - [x] 8.2 Write widget tests for SplashScreen
    - Test text content, color rendering, 2–3 second transition, fallback error display
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

  - [x] 8.3 Implement `HomeScreen`
    - Display "Enroll Employee" and "Authenticate Employee" buttons (min 48×48 dp touch targets)
    - Display `StatusBadge` widget showing "Offline Mode Active" when no network connection
    - Display navigation entry to `LocalLogsScreen`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 8.4 Write widget tests for HomeScreen
    - Test button presence, offline badge visibility, touch target sizes, logs navigation
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 9. Build UI screens — Enrollment flow
  - [x] 9.1 Implement `EnrollmentFormScreen`
    - Render form with Employee ID, Name, Department fields
    - On submit, call `EnrollmentModule.validateForm`; display field-level errors inline
    - On duplicate ID, show warning dialog with "Overwrite" / "Cancel" options
    - On valid form, navigate to `FaceCaptureScreen`
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 9.2 Write widget tests for EnrollmentFormScreen
    - Test field validation errors, duplicate warning dialog, navigation on valid submit
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 9.3 Implement `FaceCaptureScreen` (enrollment mode)
    - Activate front-facing camera with `FaceAlignmentOverlay` widget
    - Show green border indicator when face is detected within guide
    - Show "No face detected — please position face within the guide" after 10 seconds without detection
    - Capture minimum 3 frames; pass to `EnrollmentModule.selectBestFrame` then `enroll`
    - If quality below threshold, prompt retake
    - On success, navigate to enrollment confirmation view showing employee name and ID
    - On error, display human-readable message with retry option
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 5.3_

  - [x] 9.4 Write widget tests for FaceCaptureScreen (enrollment)
    - Test face detection indicator, 10-second timeout message, success confirmation, error retry
    - _Requirements: 4.1, 4.2, 4.3, 5.3_

- [x] 10. Build UI screens — Authentication flow
  - [x] 10.1 Implement `AuthenticationScreen`
    - Activate front-facing camera with `FaceAlignmentOverlay`
    - On face detection, call `Auth_Engine.authenticate`
    - While VERIFIED face check is pending liveness, display "Please blink naturally" prompt
    - On `AuthResult`, navigate to `VerificationResultScreen`
    - _Requirements: 6.1, 7.5_

  - [x] 10.2 Implement `VerificationResultScreen`
    - VERIFIED state: Security Green (#2E7D32) accent, show employee Name, ID, Department, Trust_Score as percentage, "Liveness: Confirmed", "Mode: Offline Active"
    - FAILED state: Red (#C62828) accent, show "Authentication Failed", failure reason, "Mode: Offline Active"
    - Display result within 500 ms of `Auth_Engine` completing classification
    - Log attempt via `Storage_Manager.logAuthAttempt` (timestamp, result, trust score, employee ID if matched, failure reason)
    - Provide "Try Again" and "Return to Home" buttons
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x] 10.3 Write property test for result screen fields
    - **Property 11: Result screen displays all required fields for any AuthResult**
    - **Validates: Requirements 8.1, 8.2, 8.3**

  - [x] 10.4 Write property test for auth attempt always logged
    - **Property 12: Authentication attempt is always logged**
    - **Validates: Requirements 8.6, 9.1**

  - [x] 10.5 Write widget tests for VerificationResultScreen
    - Test VERIFIED and FAILED state rendering, color accents, all required fields, button presence
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 11. Build UI screen — Local Logs
  - [x] 11.1 Implement `LocalLogsScreen`
    - Fetch logs via `Storage_Manager.getAuthLogs(limit: 100)`
    - Display entries in reverse chronological order showing timestamp, result, trust score, employee ID
    - _Requirements: 9.2, 9.3_

  - [x] 11.2 Write widget tests for LocalLogsScreen
    - Test reverse chronological ordering, minimum 100 entries displayed, empty state
    - _Requirements: 9.2, 9.3_

- [x] 12. Wire application shell and dependency injection
  - [x] 12.1 Implement `app.dart` and `main.dart`
    - Instantiate concrete implementations (`StorageManagerImpl`, `AuthEngineImpl`, `LivenessDetectorImpl`, `EnrollmentModuleImpl`) and inject via constructor or provider
    - Configure `MaterialApp` with named routes: `/` → `SplashScreen`, `/home` → `HomeScreen`, `/enroll` → `EnrollmentFormScreen`, `/authenticate` → `AuthenticationScreen`, `/logs` → `LocalLogsScreen`
    - Ensure app launches and reaches `HomeScreen` within 3 seconds regardless of network state
    - Block all operations and display critical error screen if AES key is unavailable on launch
    - _Requirements: 11.1, 11.3, 11.4, 12.1, 12.2_

  - [x] 12.2 Write integration tests for enrollment → authentication pipeline
    - Test full flow: enroll employee → authenticate same employee → verify VERIFIED result with correct fields
    - Test duplicate ID overwrite flow
    - _Requirements: 3.3, 5.3, 6.4, 8.2_

- [x] 13. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use `fast_check` (Dart) with a minimum of 100 iterations per property
- Unit tests cover specific examples, error conditions, and edge cases
- Checkpoints ensure incremental validation before moving to the next layer
