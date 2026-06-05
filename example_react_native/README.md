# NHAI Biometric — React Native Integration Example

Shows how an **existing React Native NHAI app** consumes the Flutter biometric
engine **without rewriting the AI pipeline**. The Flutter module ships as a
binary (AAR/xcframework); React Native talks to it over a platform channel.

```
example_react_native/
├── App.tsx                         # mock host screen using the SDK
├── src/NhaiBiometric.ts            # typed JS wrapper (NativeModules → channel)
└── android/NhaiBiometricModule.kt  # native module hosting the FlutterEngine
```

> These files are **illustrative** for the judges' demo — they document the
> integration shape. The runnable, tested logic is the Dart side
> (`lib/sdk/**`) plus its unit/integration tests.

## How it fits together

```
React Native (App.tsx)
   └─ NhaiBiometric.ts            (JS wrapper)
        └─ NativeModules.NhaiBiometric
             └─ NhaiBiometricModule.kt        (Android native module)
                  └─ MethodChannel("ai.nhai.biometric/sdk")
                       └─ NhaiSdkChannel        (lib/sdk/nhai_sdk_channel.dart)
                            └─ NhaiSdkBridge     (lib/sdk/nhai_sdk_bridge.dart)
                                 └─ FROZEN engine: AuthEngine · EnrollmentModule
                                    · AttendanceModule · SyncPurgeEngine
```

## Integration steps (production)

1. **Build the Flutter module**
   ```bash
   flutter build aar           # Android → .aar
   # iOS: add-to-app via CocoaPods / xcframework
   ```
2. **Pre-warm the engine** at app launch and register the channel handler
   (Dart side):
   ```dart
   // in the Flutter module entrypoint
   final bridge = NhaiSdkBridge(
     enrollment: enrollmentModule,
     attendance: attendanceModule,
     launcher: NavigatorBiometricFlowLauncher(...), // drives capture screens
   );
   NhaiSdkChannel(bridge).register();
   ```
3. **Add the native module** (`NhaiBiometricModule.kt` / `.swift`) to the RN
   app and register it in the package list.
4. **Install the JS wrapper** (`src/NhaiBiometric.ts`) and call it:
   ```ts
   const r = await NhaiBiometric.markAttendance();
   console.log(r.eventType, r.attendanceId);
   ```

## API surface

| Method | Camera? | Returns |
|--------|---------|---------|
| `enrollEmployee(input)` | yes (multi-pose) | `{ employeeId, templateCount, poses }` |
| `authenticateEmployee()` | yes (face+blink) | `{ verified, employeeId, trustScore }` |
| `markAttendance(input?)` | yes | `{ marked, eventType, attendanceId, trustScore }` |
| `getAttendanceSummary(input?)` | no | `{ metrics, report }` |
| `syncRecords(input?)` | no | `{ sync, purge? }` |

Full contracts: [../docs/architecture/API_CONTRACTS.md](../docs/architecture/API_CONTRACTS.md).

## What never crosses the boundary

Camera frames and face embeddings stay inside the Flutter module. The host only
ever sees IDs, trust scores, counts, and metadata — keeping PII on-device and
the AI pipeline frozen and reusable.
