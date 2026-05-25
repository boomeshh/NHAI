# Requirements Document

## Introduction

This document defines Phase 1 requirements for the NHAI Offline Edge-AI Authentication Infrastructure — a fully offline, on-device workforce authentication system for field personnel of the National Highways Authority of India (NHAI). The system uses face recognition and basic liveness detection to verify employee identity without any cloud dependency. It is designed to operate on standard Android devices in remote or network-constrained environments, and is architected as a modular foundation for future SDK extraction and Datalake 3.0 integration.

---

## Glossary

- **System**: The NHAI Offline Workforce Authentication application as a whole.
- **Auth_Engine**: The on-device module responsible for face embedding extraction, comparison, and verification decisions.
- **Enrollment_Module**: The module responsible for capturing, processing, and securely storing employee face embeddings.
- **Liveness_Detector**: The module responsible for detecting real human presence via blink detection.
- **Storage_Manager**: The module responsible for encrypted local persistence of embeddings and employee records.
- **Result_Screen**: The UI screen that displays the final authentication outcome to the operator.
- **Employee_Record**: A data structure containing Employee ID, Name, Department, and associated face embedding(s).
- **Face_Embedding**: A numerical vector representation of a face, extracted by MobileFaceNet via TensorFlow Lite.
- **Trust_Score**: A percentage value (0–100) representing the cosine similarity between a captured face embedding and the stored reference embedding.
- **Liveness_Check**: A challenge-response verification step requiring the subject to blink, used to prevent static image spoofing.
- **Encrypted_Store**: The local on-device database (Hive or SQLCipher) where all Employee_Records and Face_Embeddings are stored using AES-256 encryption.
- **Operator**: A field supervisor or security personnel who uses the System to enroll or authenticate employees.
- **Employee**: A field worker whose identity is being enrolled or verified.

---

## Requirements

### Requirement 1: Splash Screen

**User Story:** As an operator, I want to see a professional government-style splash screen on app launch, so that the system identity and branding are immediately clear.

#### Acceptance Criteria

1. WHEN the application is launched, THE System SHALL display a splash screen for a minimum of 2 seconds and a maximum of 3 seconds before transitioning to the Home screen.
2. THE System SHALL display the text "Offline Workforce Authentication System" and "Powered by Edge AI" on the splash screen.
3. THE System SHALL display the NHAI logo and name on the splash screen.
4. THE System SHALL render the splash screen using the government color palette: Deep Blue (#003580) as the primary background, White (#FFFFFF) for text, and Saffron (#FF6600) as an accent element.
5. THE System SHALL display a minimal loading animation (e.g., a progress indicator) during the splash screen duration.
6. IF the application assets fail to load within 5 seconds of launch, THEN THE System SHALL display a fallback error message and allow the operator to retry.

---

### Requirement 2: Home Screen

**User Story:** As an operator, I want a clear home screen with distinct actions for enrollment and authentication, so that I can quickly navigate to the required workflow.

#### Acceptance Criteria

1. THE System SHALL display a Home screen with two primary action buttons: "Enroll Employee" and "Authenticate Employee".
2. THE System SHALL display the current offline status indicator on the Home screen at all times.
3. WHILE the device has no active network connection, THE System SHALL display an "Offline Mode Active" status badge on the Home screen.
4. THE System SHALL display a navigation entry point to the Local Logs screen from the Home screen.
5. THE System SHALL render all Home screen buttons with a minimum touch target size of 48×48 dp to ensure field-worker accessibility.

---

### Requirement 3: Employee Enrollment — Data Entry

**User Story:** As an operator, I want to enter an employee's ID, name, and department before capturing their face, so that the enrollment record is complete and identifiable.

#### Acceptance Criteria

1. THE Enrollment_Module SHALL present a form with three mandatory fields: Employee ID (alphanumeric, max 20 characters), Name (text, max 60 characters), and Department (text, max 60 characters).
2. WHEN the operator submits the enrollment form with one or more empty mandatory fields, THE Enrollment_Module SHALL display a field-level validation error and prevent progression to face capture.
3. WHEN the operator submits the enrollment form with an Employee ID that already exists in the Encrypted_Store, THE Enrollment_Module SHALL display a duplicate-record warning and require the operator to confirm overwrite or cancel.
4. THE Enrollment_Module SHALL sanitize all text inputs by trimming leading and trailing whitespace before storing.

---

### Requirement 4: Employee Enrollment — Face Capture

**User Story:** As an operator, I want to capture a clear face image of the employee, so that a high-quality embedding can be generated for future authentication.

#### Acceptance Criteria

1. WHEN the operator proceeds from the enrollment form, THE Enrollment_Module SHALL activate the front-facing camera and display a real-time viewfinder with a face-alignment overlay guide.
2. WHEN a face is detected within the alignment guide, THE Enrollment_Module SHALL display a visual confirmation indicator (e.g., green border) to signal correct positioning.
3. WHEN no face is detected within 10 seconds of camera activation during enrollment, THE Enrollment_Module SHALL display a "No face detected — please position face within the guide" message.
4. THE Enrollment_Module SHALL capture a minimum of 3 face frames and use the highest-quality frame (based on sharpness score) for embedding extraction.
5. WHEN the captured frame quality score falls below the minimum threshold, THE Enrollment_Module SHALL prompt the operator to retake the capture.
6. THE Auth_Engine SHALL extract a 128-dimensional Face_Embedding from the selected frame using MobileFaceNet via TensorFlow Lite.
7. WHEN embedding extraction fails, THE Auth_Engine SHALL return a descriptive error code and THE Enrollment_Module SHALL display a human-readable error message and offer a retry option.

---

### Requirement 5: Employee Enrollment — Secure Storage

**User Story:** As an operator, I want enrolled employee data to be stored securely on-device, so that sensitive biometric data is protected even if the device is lost or compromised.

#### Acceptance Criteria

1. THE Storage_Manager SHALL encrypt all Face_Embeddings using AES-256 encryption before writing to the Encrypted_Store.
2. THE Storage_Manager SHALL store each Employee_Record as a single atomic unit containing Employee ID, Name, Department, encrypted Face_Embedding, and enrollment timestamp.
3. WHEN an Employee_Record is successfully saved, THE Enrollment_Module SHALL display a "Enrollment Successful" confirmation screen with the employee's name and ID.
4. IF the Storage_Manager fails to write an Employee_Record, THEN THE Enrollment_Module SHALL display an error message and SHALL NOT leave a partial record in the Encrypted_Store.
5. THE Storage_Manager SHALL complete an enrollment write operation within 2 seconds on a standard Android device (minimum 2 GB RAM, Android 8.0+).
6. THE Storage_Manager SHALL support storage of a minimum of 500 Employee_Records on a single device without performance degradation.

---

### Requirement 6: Offline Authentication — Face Verification

**User Story:** As an operator, I want to verify an employee's identity using their face, so that access or attendance can be confirmed without network connectivity.

#### Acceptance Criteria

1. WHEN the operator initiates authentication, THE Auth_Engine SHALL activate the front-facing camera and display a real-time viewfinder with a face-alignment overlay guide.
2. WHEN a face is detected and aligned, THE Auth_Engine SHALL extract a Face_Embedding from the live frame using MobileFaceNet via TensorFlow Lite.
3. THE Auth_Engine SHALL compare the live Face_Embedding against all stored Face_Embeddings using cosine similarity.
4. WHEN the highest cosine similarity score meets or exceeds the verification threshold of 0.75, THE Auth_Engine SHALL classify the result as VERIFIED and assign the corresponding Trust_Score.
5. WHEN the highest cosine similarity score falls below 0.75, THE Auth_Engine SHALL classify the result as FAILED.
6. THE Auth_Engine SHALL complete the full face comparison and classification within 2 seconds of face detection on a standard Android device (minimum 2 GB RAM, Android 8.0+).
7. THE Auth_Engine SHALL operate entirely on-device with no network calls during the authentication process.

---

### Requirement 7: Liveness Detection — Blink Verification

**User Story:** As an operator, I want the system to confirm the subject is a live person by detecting a blink, so that static photo spoofing attacks are prevented.

#### Acceptance Criteria

1. WHEN face verification produces a VERIFIED classification, THE Liveness_Detector SHALL initiate a blink detection challenge before finalizing the result.
2. THE Liveness_Detector SHALL use MediaPipe Face Mesh landmarks to detect eye aspect ratio (EAR) changes consistent with a natural blink.
3. WHEN the Liveness_Detector detects a valid blink (EAR drops below 0.25 and recovers above 0.25 within 400 milliseconds), THE Liveness_Detector SHALL mark the liveness check as Confirmed.
4. WHEN no valid blink is detected within 5 seconds of the liveness challenge start, THE Liveness_Detector SHALL mark the liveness check as Failed and THE Auth_Engine SHALL classify the overall result as FAILED.
5. THE Liveness_Detector SHALL display a visible on-screen prompt "Please blink naturally" during the liveness challenge.
6. THE Liveness_Detector SHALL process liveness detection entirely on-device with no network calls.

---

### Requirement 8: Verification Result Display

**User Story:** As an operator, I want to see a clear, unambiguous verification result screen, so that I can immediately act on the authentication outcome.

#### Acceptance Criteria

1. WHEN authentication completes, THE Result_Screen SHALL display one of two states: VERIFIED (Security Green #2E7D32 background accent) or FAILED (Red #C62828 background accent).
2. WHEN the result is VERIFIED, THE Result_Screen SHALL display: the employee's Name, Employee ID, Department, Trust_Score as a percentage, "Liveness: Confirmed", and "Mode: Offline Active".
3. WHEN the result is FAILED, THE Result_Screen SHALL display: "Authentication Failed", the reason code (e.g., "Face not recognized" or "Liveness check failed"), and "Mode: Offline Active".
4. THE Result_Screen SHALL display the result within 500 milliseconds of the Auth_Engine completing classification.
5. THE Result_Screen SHALL provide a "Try Again" button and a "Return to Home" button.
6. THE Result_Screen SHALL log the authentication attempt (timestamp, result, Trust_Score, Employee ID if matched) to the Encrypted_Store via the Storage_Manager.

---

### Requirement 9: Local Authentication Logs

**User Story:** As an operator, I want to review a history of authentication attempts on the device, so that I can audit field activity without network access.

#### Acceptance Criteria

1. THE Storage_Manager SHALL record each authentication attempt as a log entry containing: timestamp (ISO 8601), result (VERIFIED/FAILED), Trust_Score, Employee ID (if matched), and failure reason (if applicable).
2. THE System SHALL display a Local Logs screen listing all stored authentication log entries in reverse chronological order.
3. THE System SHALL display a minimum of the 100 most recent log entries on the Local Logs screen.
4. WHEN the log store exceeds 1000 entries, THE Storage_Manager SHALL automatically delete the oldest entries to maintain the 1000-entry limit.
5. THE Storage_Manager SHALL encrypt all log entries using AES-256 encryption before writing to the Encrypted_Store.

---

### Requirement 10: Encrypted Storage — Parser and Serializer

**User Story:** As a developer, I want all data written to and read from the Encrypted_Store to be correctly serialized and deserialized, so that data integrity is guaranteed across app sessions.

#### Acceptance Criteria

1. WHEN an Employee_Record is written to the Encrypted_Store, THE Storage_Manager SHALL serialize the record to a defined binary or JSON schema before encryption.
2. WHEN an Employee_Record is read from the Encrypted_Store, THE Storage_Manager SHALL decrypt and deserialize the data back into a valid Employee_Record object.
3. THE Storage_Manager SHALL format Employee_Record objects back into the defined schema (pretty-print equivalent for the storage format).
4. FOR ALL valid Employee_Record objects, serializing then storing then retrieving then deserializing SHALL produce an object equal to the original (round-trip property).
5. IF the Storage_Manager encounters a corrupted or unreadable record during deserialization, THEN THE Storage_Manager SHALL skip the corrupted record, log a storage error entry, and continue reading remaining records.

---

### Requirement 11: Offline-First Operation

**User Story:** As a field operator, I want the system to function fully without any network connection, so that authentication is reliable in remote locations with no connectivity.

#### Acceptance Criteria

1. THE System SHALL complete all enrollment and authentication workflows while the device is in airplane mode.
2. THE System SHALL NOT make any network requests during enrollment, authentication, liveness detection, or result display.
3. WHILE the device has no active network connection, THE System SHALL continue to operate all core features without degradation.
4. THE System SHALL launch and reach the Home screen within 3 seconds on a standard Android device (minimum 2 GB RAM, Android 8.0+) regardless of network state.

---

### Requirement 12: Modular Architecture

**User Story:** As a developer, I want the authentication engine to be implemented as a self-contained module, so that it can be extracted as a reusable SDK in future phases.

#### Acceptance Criteria

1. THE Auth_Engine SHALL expose a defined interface (abstract class or interface) that is independent of any Flutter UI widget.
2. THE Enrollment_Module, Auth_Engine, Liveness_Detector, and Storage_Manager SHALL each be implemented as separate Dart packages or clearly bounded modules within the project.
3. THE Auth_Engine SHALL accept a raw image frame and return a structured result object containing: classification (VERIFIED/FAILED), Trust_Score, matched Employee ID (nullable), and failure reason (nullable).
4. THE Storage_Manager SHALL expose a defined interface that allows the underlying storage implementation (Hive or SQLCipher) to be swapped without changes to the Auth_Engine or Enrollment_Module.
