import 'package:flutter/material.dart';

import '../../core/storage_manager/storage_manager_interface.dart';
import '../../models/auth_log_entry.dart';
import '../../models/auth_result.dart';

class LocalLogsScreen extends StatefulWidget {
  final StorageManagerInterface storageManager;

  const LocalLogsScreen({
    super.key,
    required this.storageManager,
  });

  @override
  State<LocalLogsScreen> createState() => _LocalLogsScreenState();
}

class _LocalLogsScreenState extends State<LocalLogsScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  late Future<List<AuthLogEntry>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.storageManager.getAuthLogs(limit: 100);
  }

  Future<void> _refresh() async {
    setState(() {
      _logsFuture = widget.storageManager.getAuthLogs(limit: 100);
    });
    await _logsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('local_logs_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        leading: IconButton(
          key: const Key('back_button'),
          icon: const Icon(Icons.arrow_back_ios_new, color: _white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: const Text(
          'Local Logs',
          style: TextStyle(
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: _saffron, height: 2),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<AuthLogEntry>>(
          future: _logsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  key: Key('logs_loading_indicator'),
                  valueColor: AlwaysStoppedAnimation<Color>(_saffron),
                ),
              );
            }

            if (snapshot.hasError) {
              return _ErrorState(
                message: 'Unable to load local logs.',
                onRetry: _refresh,
              );
            }

            final logs = snapshot.data ?? const <AuthLogEntry>[];
            if (logs.isEmpty) {
              return const _EmptyState();
            }

            return RefreshIndicator(
              color: _saffron,
              onRefresh: _refresh,
              child: SingleChildScrollView(
                key: const Key('auth_logs_list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  children: [
                    for (int index = 0; index < logs.length; index++) ...[
                      _LogEntryTile(
                        key: Key('auth_log_entry_$index'),
                        entry: logs[index],
                      ),
                      if (index != logs.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final AuthLogEntry entry;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _securityGreen = Color(0xFF2E7D32);
  static const Color _failedRed = Color(0xFFC62828);

  const _LogEntryTile({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final isVerified = entry.result == AuthClassification.verified;
    final accentColor = isVerified ? _securityGreen : _failedRed;
    final trustPercent = '${(entry.trustScore * 100).round()}%';
    final employeeId = entry.employeeId ?? 'No match';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.16),
            ),
            child: Icon(
              isVerified ? Icons.verified_user : Icons.gpp_bad,
              color: accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isVerified ? 'VERIFIED' : 'FAILED',
                        key: const Key('log_result_text'),
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Text(
                      trustPercent,
                      key: const Key('log_trust_score_text'),
                      style: const TextStyle(
                        color: _saffron,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  entry.timestamp.toUtc().toIso8601String(),
                  key: const Key('log_timestamp_text'),
                  style: TextStyle(
                    color: _white.withValues(alpha: 0.72),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Employee ID: $employeeId',
                  key: const Key('log_employee_id_text'),
                  style: const TextStyle(
                    color: _white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (entry.failureReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.failureReason!,
                    key: const Key('log_failure_reason_text'),
                    style: const TextStyle(
                      color: Color(0xFFEF9A9A),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, color: _saffron, size: 56),
            const SizedBox(height: 16),
            const Text(
              'No authentication logs yet.',
              key: Key('logs_empty_state'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed attempts will appear here in offline storage.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _white.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _failedRed = Color(0xFFC62828);

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _failedRed, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              key: const Key('logs_error_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              key: const Key('logs_retry_button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saffron,
                foregroundColor: _white,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
