/**
 * Mock NHAI React Native host app.
 *
 * Demonstrates how an EXISTING React Native application consumes the embedded
 * Flutter biometric engine through the NhaiBiometric SDK wrapper — enroll,
 * authenticate, mark attendance, view the dashboard summary, and trigger a
 * Datalake 3.0 sync — without any knowledge of the AI pipeline internals.
 *
 * This file is illustrative (not built by `flutter test`); it shows the
 * integration shape for the judges' demo.
 */
import React, { useState } from 'react';
import { SafeAreaView, ScrollView, Text, Button, View, StyleSheet } from 'react-native';
import { NhaiBiometric, SdkError, AttendanceMetrics } from './src/NhaiBiometric';

export default function App() {
  const [log, setLog] = useState<string[]>([]);
  const [metrics, setMetrics] = useState<AttendanceMetrics | null>(null);

  const append = (line: string) => setLog((l) => [line, ...l].slice(0, 20));

  const guard = (label: string, fn: () => Promise<void>) => async () => {
    try {
      await fn();
    } catch (e) {
      const err = e as SdkError;
      append(`✗ ${label}: [${err.code}] ${err.message}`);
    }
  };

  const onEnroll = guard('enroll', async () => {
    const r = await NhaiBiometric.enrollEmployee({
      employeeId: 'EMP-1001',
      name: 'A. Singh',
      department: 'Patrol',
    });
    append(`✓ Enrolled ${r.employeeId} with ${r.templateCount} pose templates`);
  });

  const onAuthenticate = guard('authenticate', async () => {
    const r = await NhaiBiometric.authenticateEmployee();
    append(`✓ Verified ${r.employeeId} (trust ${r.trustScore.toFixed(2)})`);
  });

  const onMark = guard('markAttendance', async () => {
    const r = await NhaiBiometric.markAttendance();
    append(`✓ ${r.message} (${r.eventType}) — ${r.attendanceId ?? ''}`);
  });

  const onSummary = guard('summary', async () => {
    const r = await NhaiBiometric.getAttendanceSummary({ scope: 'daily' });
    setMetrics(r.metrics);
    append(`✓ Summary for ${r.date.slice(0, 10)}`);
  });

  const onSync = guard('sync', async () => {
    const r = await NhaiBiometric.syncRecords({ purge: true });
    append(`✓ Synced ${r.sync.synced}, failed ${r.sync.failed}, purged ${r.purge?.attendancePurged ?? 0}`);
  });

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>NHAI Biometric — RN Host Demo</Text>

      <View style={styles.row}>
        <Button title="Enroll" onPress={onEnroll} />
        <Button title="Authenticate" onPress={onAuthenticate} />
        <Button title="Mark Attendance" onPress={onMark} />
      </View>
      <View style={styles.row}>
        <Button title="Summary" onPress={onSummary} />
        <Button title="Sync → Datalake 3.0" onPress={onSync} />
      </View>

      {metrics && (
        <View style={styles.card}>
          <Text style={styles.metric}>Present: {metrics.presentToday}</Text>
          <Text style={styles.metric}>Absent: {metrics.absentToday}</Text>
          <Text style={styles.metric}>Late: {metrics.lateToday}</Text>
          <Text style={styles.metric}>Pending Sync: {metrics.pendingSyncRecords}</Text>
          <Text style={styles.metric}>
            Auth Success: {(metrics.authenticationSuccessRate * 100).toFixed(0)}%
          </Text>
        </View>
      )}

      <ScrollView style={styles.logBox}>
        {log.map((line, i) => (
          <Text key={i} style={styles.logLine}>
            {line}
          </Text>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, padding: 16, backgroundColor: '#003580' },
  title: { color: '#fff', fontSize: 18, fontWeight: '700', marginBottom: 12 },
  row: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 10 },
  card: { backgroundColor: '#ffffff22', borderRadius: 10, padding: 12, marginVertical: 8 },
  metric: { color: '#fff', fontSize: 14, paddingVertical: 2 },
  logBox: { flex: 1, backgroundColor: '#00000033', borderRadius: 10, padding: 8, marginTop: 8 },
  logLine: { color: '#cfe', fontSize: 12, paddingVertical: 1 },
});
