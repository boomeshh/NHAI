/**
 * NHAI Biometric SDK — React Native JS wrapper.
 *
 * Thin typed facade over the native module that bridges to the embedded Flutter
 * biometric engine via the `ai.nhai.biometric/sdk` MethodChannel. The AI
 * pipeline (MobileFaceNet, ML Kit, SQLCipher) lives inside the Flutter module;
 * this wrapper only sends commands and receives JSON results.
 *
 * Mirrors the Dart contracts in lib/sdk/nhai_sdk_contracts.dart.
 */
import { NativeModules } from 'react-native';

const { NhaiBiometric: Native } = NativeModules as {
  NhaiBiometric: NhaiBiometricNative;
};

export type SdkCode =
  | 'OK'
  | 'VALIDATION_ERROR'
  | 'NOT_VERIFIED'
  | 'NOT_FOUND'
  | 'CANCELLED'
  | 'UNKNOWN_METHOD'
  | 'ERROR';

export interface EnrollResult {
  employeeId: string;
  name: string;
  department: string;
  templateCount: number;
  poses: string[];
}

export interface AuthResult {
  verified: boolean;
  employeeId: string;
  trustScore: number;
}

export interface MarkResult {
  marked: boolean;
  employeeId: string;
  eventType: 'checkIn' | 'checkOut';
  message: string;
  trustScore: number;
  attendanceId: string | null;
}

export interface AttendanceMetrics {
  totalEmployees: number;
  presentToday: number;
  absentToday: number;
  lateToday: number;
  pendingSyncRecords: number;
  averageTrustScore: number;
  authenticationSuccessRate: number;
}

export interface SummaryResult {
  scope: 'daily' | 'monthly';
  date: string;
  metrics: AttendanceMetrics;
  report: Record<string, unknown>;
}

export interface SyncResult {
  sync: {
    processed: number;
    synced: number;
    failed: number;
    conflicts: number;
    skippedOffline: number;
  };
  purge?: { attendancePurged: number; queuePurged: number };
}

/** Error thrown when an SDK call returns a non-OK code. */
export class SdkError extends Error {
  constructor(public code: SdkCode, message: string, public data?: unknown) {
    super(message);
    this.name = 'SdkError';
  }
}

interface NhaiBiometricNative {
  enrollEmployee(args: object): Promise<EnrollResult>;
  authenticateEmployee(args: object): Promise<AuthResult>;
  markAttendance(args: object): Promise<MarkResult>;
  getAttendanceSummary(args: object): Promise<SummaryResult>;
  syncRecords(args: object): Promise<SyncResult>;
}

/**
 * The native module rejects with (code, message) on non-OK results; this helper
 * normalizes that into a typed {@link SdkError}.
 */
async function call<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e: any) {
    throw new SdkError((e?.code as SdkCode) ?? 'ERROR', e?.message ?? 'SDK call failed', e?.userInfo);
  }
}

export const NhaiBiometric = {
  enrollEmployee(input: {
    employeeId: string;
    name: string;
    department: string;
    allowOverwrite?: boolean;
  }): Promise<EnrollResult> {
    return call(() => Native.enrollEmployee(input));
  },

  authenticateEmployee(): Promise<AuthResult> {
    return call(() => Native.authenticateEmployee({}));
  },

  markAttendance(input: { forced?: 'checkIn' | 'checkOut' } = {}): Promise<MarkResult> {
    return call(() => Native.markAttendance(input));
  },

  getAttendanceSummary(
    input: { scope?: 'daily' | 'monthly'; date?: string } = {},
  ): Promise<SummaryResult> {
    return call(() => Native.getAttendanceSummary(input));
  },

  syncRecords(input: { purge?: boolean } = {}): Promise<SyncResult> {
    return call(() => Native.syncRecords(input));
  },
};
