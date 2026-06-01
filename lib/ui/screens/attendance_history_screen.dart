import 'package:flutter/material.dart';

import '../../attendance/models/attendance_record.dart';
import '../../attendance/repositories/attendance_repository.dart';

/// Attendance history (Phase 10) — recent records, newest first.
class AttendanceHistoryScreen extends StatefulWidget {
  final AttendanceRepository attendance;

  const AttendanceHistoryScreen({super.key, required this.attendance});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF2E7D32);

  late Future<List<AttendanceRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AttendanceRecord>> _load() async {
    final all = await widget.attendance.getAll();
    all.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
    return all;
  }

  static String _t(DateTime? d) => d == null
      ? '—'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('attendance_history_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        title: const Text('Attendance History',
            style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _white),
      ),
      body: SafeArea(
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_saffron),
                ),
              );
            }
            final records = snap.data!;
            if (records.isEmpty) {
              return const Center(
                child: Text('No attendance records yet',
                    key: Key('history_empty'),
                    style: TextStyle(color: _white)),
              );
            }
            return ListView.separated(
              key: const Key('history_list'),
              padding: const EdgeInsets.all(12),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = records[i];
                return Container(
                  decoration: BoxDecoration(
                    color: _white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _saffron.withValues(alpha: 0.4)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        r.isOpen ? Icons.login : Icons.logout,
                        color: r.isOpen ? _saffron : _green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.employeeId,
                                style: const TextStyle(
                                    color: _white,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${_d(r.date)}  •  in ${_t(r.checkInTime)}  out ${_t(r.checkOutTime)}'
                              '${r.isLate ? '  • LATE' : ''}',
                              style: TextStyle(
                                  color: _white.withValues(alpha: 0.7),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text('${(r.trustScore * 100).round()}%',
                          style: const TextStyle(
                              color: _saffron, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
