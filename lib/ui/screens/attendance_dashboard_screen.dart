import 'package:flutter/material.dart';

import '../../attendance/services/dashboard_service.dart';

/// Attendance dashboard (Phase 7 metrics): Total Employees, Present Today,
/// Absent Today, Pending Sync, Average Trust Score.
class AttendanceDashboardScreen extends StatefulWidget {
  final DashboardService dashboard;

  /// Injectable clock for tests (defaults to now).
  final DateTime Function() clock;

  // ignore: prefer_const_constructors_in_immutables
  AttendanceDashboardScreen({
    super.key,
    required this.dashboard,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  @override
  State<AttendanceDashboardScreen> createState() =>
      _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends State<AttendanceDashboardScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  late Future<DashboardMetrics> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.dashboard.compute(widget.clock());
  }

  void _refresh() =>
      setState(() => _future = widget.dashboard.compute(widget.clock()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('attendance_dashboard_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        title: const Text('Attendance Dashboard',
            style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _white),
        actions: [
          IconButton(
            key: const Key('dashboard_refresh'),
            icon: const Icon(Icons.refresh, color: _white),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<DashboardMetrics>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_saffron),
                ),
              );
            }
            final m = snap.data!;
            return GridView.count(
              key: const Key('dashboard_grid'),
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(
                    label: 'Total Employees', value: '${m.totalEmployees}'),
                _MetricCard(label: 'Present Today', value: '${m.presentToday}'),
                _MetricCard(label: 'Absent Today', value: '${m.absentToday}'),
                _MetricCard(
                    label: 'Pending Sync', value: '${m.pendingSyncRecords}'),
                _MetricCard(
                    label: 'Avg Trust Score',
                    value: '${(m.averageTrustScore * 100).round()}%'),
                _MetricCard(
                    label: 'Auth Success',
                    value:
                        '${(m.authenticationSuccessRate * 100).round()}%'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _saffron.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              key: Key('metric_$label'),
              style: const TextStyle(
                  color: _saffron, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white, fontSize: 13)),
        ],
      ),
    );
  }
}
