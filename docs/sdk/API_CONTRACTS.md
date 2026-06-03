# NHAI Biometric SDK — API Contracts

All five methods cross the platform channel `ai.nhai.biometric/sdk` and return
the uniform **`SdkResult`** envelope. The host (React Native) never receives raw
camera frames or face embeddings — the AI pipeline stays entirely inside the
Flutter module.

## Result envelope

Every call resolves to:

```jsonc
{
  "ok": true,                 // operation succeeded
  "code": "OK",               // stable, non-localized status code
  "message": "Identity verified", // optional human string
  "data": { /* method-specific */ }
}
```

### Status codes (`SdkCodes`)

| Code | Meaning |
|------|---------|
| `OK` | success |
| `VALIDATION_ERROR` | bad/missing arguments or invalid employee form |
| `NOT_VERIFIED` | face did not match / liveness failed |
| `NOT_FOUND` | entity not found |
| `CANCELLED` | user cancelled the capture flow |
| `UNKNOWN_METHOD` | unsupported method name |
| `ERROR` | unexpected failure (message carries detail) |

---

## 1. `enrollEmployee(args)`

Registers an employee and captures their multi-pose face gallery.

**Args**
```jsonc
{ "employeeId": "EMP-1001", "name": "A. Singh", "department": "Patrol", "allowOverwrite": false }
```
**Success `data`**
```jsonc
{ "employeeId": "EMP-1001", "name": "A. Singh", "department": "Patrol",
  "templateCount": 5, "poses": ["FRONTAL","LEFT","RIGHT","UP","DOWN"] }
```
**Failure** — `VALIDATION_ERROR` (with `data.fieldErrors`), `CANCELLED`, `ERROR`.

## 2. `authenticateEmployee()`

Runs the face + blink flow and identifies the live subject.

**Success `data`** `{ "verified": true, "employeeId": "EMP-1001", "trustScore": 0.93 }`
**Failure** — `NOT_VERIFIED` (`data: { verified:false, trustScore }`).

## 3. `markAttendance(args)`

Authenticates the live subject, then marks attendance (auto check-in/out).

**Args** `{ "forced": "checkIn" }` *(optional; omit for turnstile auto-resolve)*
**Success `data`**
```jsonc
{ "marked": true, "employeeId": "EMP-1001", "eventType": "checkIn",
  "message": "Checked in successfully", "trustScore": 0.93, "attendanceId": "ATT-…" }
```
**Failure** — `NOT_VERIFIED`, `ERROR`.

## 4. `getAttendanceSummary(args)`

Read-only metrics + report. No camera.

**Args** `{ "scope": "daily", "date": "2026-06-01T00:00:00.000" }` *(both optional; default daily/today)*
**Success `data`**
```jsonc
{ "scope": "daily", "date": "2026-06-01T00:00:00.000",
  "metrics": { "totalEmployees": 42, "presentToday": 30, "absentToday": 12,
               "lateToday": 3, "pendingSyncRecords": 5,
               "authenticationSuccessRate": 0.98, "averageTrustScore": 0.92, … },
  "report": { "type":"daily", "summary": {…}, "records": [ … ] } }
```

## 5. `syncRecords(args)`

Drains the offline sync queue; optionally purges synced+expired records.

**Args** `{ "purge": true }` *(optional)*
**Success `data`**
```jsonc
{ "sync":  { "processed": 5, "synced": 5, "failed": 0, "conflicts": 0, "skippedOffline": 0 },
  "purge": { "attendancePurged": 12, "queuePurged": 5 } }
```

---

## Contract guarantees

- **No PII/biometrics cross the boundary.** Only IDs, scores, counts, and
  metadata. Embeddings never leave the Flutter module.
- **Deterministic codes.** The host branches on `code`, not on message text.
- **Idempotent reads.** `getAttendanceSummary` and `syncRecords` never mutate
  the AI pipeline; attendance writes go only through the verified flows.
- **The AI pipeline is frozen.** The SDK *consumes* detection / recognition /
  matcher / attendance / sync / dashboard; it does not modify them.
