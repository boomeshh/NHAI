import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage_manager/storage_manager_interface.dart';
import '../../models/auth_log_entry.dart';
import '../../models/auth_result.dart';
import '../../models/employee_record.dart';

class VerificationResultScreen extends StatefulWidget {
  final StorageManagerInterface storageManager;
  final AuthResult? result;

  const VerificationResultScreen({
    super.key,
    required this.storageManager,
    this.result,
  });

  @override
  State<VerificationResultScreen> createState() =>
      _VerificationResultScreenState();
}

class _VerificationResultScreenState extends State<VerificationResultScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _securityGreen = Color(0xFF2E7D32);
  static const Color _failedRed = Color(0xFFC62828);

  AuthResult? _result;
  EmployeeRecord? _matchedEmployee;
  bool _logAttempted = false;
  bool _employeeLookupStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveResult();
    _logOnce();
    _loadMatchedEmployee();
  }

  @override
  void didUpdateWidget(covariant VerificationResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _result = null;
      _matchedEmployee = null;
      _logAttempted = false;
      _employeeLookupStarted = false;
      _resolveResult();
      _logOnce();
      _loadMatchedEmployee();
    }
  }

  void _resolveResult() {
    if (_result != null) return;

    if (widget.result != null) {
      _result = widget.result;
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is AuthResult) {
      _result = args;
    }
  }

  void _logOnce() {
    final result = _result;
    if (result == null || _logAttempted) return;

    _logAttempted = true;
    _logAuthAttempt(result);
  }

  void _loadMatchedEmployee() {
    final result = _result;
    final employeeId = result?.matchedEmployeeId;
    if (employeeId == null || _employeeLookupStarted) return;

    _employeeLookupStarted = true;
    widget.storageManager.getEmployeeRecord(employeeId).then((record) {
      if (!mounted) return;
      setState(() => _matchedEmployee = record);
    }).catchError((Object e) async {
      await widget.storageManager.logStorageError(
        'Failed to load matched employee $employeeId: $e',
      );
    });
  }

  Future<void> _logAuthAttempt(AuthResult result) async {
    final entry = AuthLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now().toUtc(),
      result: result.classification,
      trustScore: result.trustScore,
      employeeId: result.matchedEmployeeId,
      failureReason: result.failureReason,
    );

    try {
      await widget.storageManager.logAuthAttempt(entry);
    } catch (e) {
      await widget.storageManager.logStorageError(
        'Failed to log auth attempt: $e',
      );
    }
  }

  void _tryAgain() {
    Navigator.of(context).pushReplacementNamed('/authenticate');
  }

  void _returnHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result ?? widget.result;

    return Scaffold(
      key: const Key('verification_result_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Verification Result',
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
        child: result == null
            ? _buildNoResultView()
            : result.classification == AuthClassification.verified
                ? _buildVerifiedView(result)
                : _buildFailedView(result),
      ),
    );
  }

  Widget _buildNoResultView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, color: _white, size: 56),
            const SizedBox(height: 16),
            const Text(
              'No result available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white, fontSize: 16),
            ),
            const SizedBox(height: 32),
            _ActionButtons(
              onTryAgain: _tryAgain,
              onReturnHome: _returnHome,
              accentColor: _saffron,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifiedView(AuthResult result) {
    final employeeId = result.matchedEmployeeId ?? 'Unavailable';
    final employeeName = _matchedEmployee?.name ?? employeeId;
    final department = _matchedEmployee?.department ?? 'Unavailable';
    final trustPercent = '${(result.trustScore * 100).round()}%';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              key: const Key('verified_accent'),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _securityGreen.withValues(alpha: 0.15),
                border: const Border.fromBorderSide(
                  BorderSide(color: _securityGreen, width: 3),
                ),
              ),
              child: const Icon(
                Icons.verified_user,
                color: _securityGreen,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Identity Verified',
            key: Key('verified_headline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _securityGreen,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 28),
          _ResultPanel(
            key: const Key('verified_card'),
            borderColor: _securityGreen,
            children: [
              _DetailRow(
                label: 'Name',
                value: employeeName,
                valueKey: const Key('employee_name_text'),
              ),
              const _Divider(),
              _DetailRow(
                label: 'Employee ID',
                value: employeeId,
                valueKey: const Key('employee_id_text'),
              ),
              const _Divider(),
              _DetailRow(
                label: 'Department',
                value: department,
                valueKey: const Key('department_text'),
              ),
              const _Divider(),
              _DetailRow(
                label: 'Trust Score',
                value: trustPercent,
                valueKey: const Key('trust_score_text'),
              ),
              const _Divider(),
              _DetailRow(
                label: 'Liveness',
                value: 'Confirmed',
                valueKey: const Key('liveness_confirmed_text'),
                valueColor: _securityGreen,
              ),
              const _Divider(),
              _DetailRow(
                label: 'Mode',
                value: 'Offline Active',
                valueKey: const Key('offline_mode_text'),
              ),
            ],
          ),
          const SizedBox(height: 40),
          _ActionButtons(
            onTryAgain: _tryAgain,
            onReturnHome: _returnHome,
            accentColor: _securityGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildFailedView(AuthResult result) {
    final reason = result.failureReason ?? 'Face not recognized';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              key: const Key('failed_accent'),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _failedRed.withValues(alpha: 0.15),
                border: const Border.fromBorderSide(
                  BorderSide(color: _failedRed, width: 3),
                ),
              ),
              child: const Icon(
                Icons.gpp_bad,
                color: _failedRed,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Authentication Failed',
            key: Key('failed_headline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _failedRed,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 28),
          _ResultPanel(
            key: const Key('failed_card'),
            borderColor: _failedRed,
            children: [
              _DetailRow(
                label: 'Reason',
                value: reason,
                valueKey: const Key('failure_reason_text'),
                valueColor: const Color(0xFFEF9A9A),
              ),
              const _Divider(),
              _DetailRow(
                label: 'Mode',
                value: 'Offline Active',
                valueKey: const Key('offline_mode_text'),
              ),
            ],
          ),
          const SizedBox(height: 40),
          _ActionButtons(
            onTryAgain: _tryAgain,
            onReturnHome: _returnHome,
            accentColor: _failedRed,
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final List<Widget> children;
  final Color borderColor;

  static const Color _white = Color(0xFFFFFFFF);

  const _ResultPanel({
    super.key,
    required this.children,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;
  final Color? valueColor;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueKey,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: _saffron,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            style: TextStyle(
              color: valueColor ?? _white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        color: Colors.white.withValues(alpha: 0.12),
        height: 1,
        thickness: 1,
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onTryAgain;
  final VoidCallback onReturnHome;
  final Color accentColor;

  static const Color _white = Color(0xFFFFFFFF);

  const _ActionButtons({
    required this.onTryAgain,
    required this.onReturnHome,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          key: const Key('try_again_button'),
          onPressed: onTryAgain,
          icon: const Icon(Icons.refresh),
          label: const Text(
            'Try Again',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: _white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 3,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          key: const Key('return_home_button'),
          onPressed: onReturnHome,
          style: OutlinedButton.styleFrom(
            foregroundColor: _white,
            side: BorderSide(
              color: _white.withValues(alpha: 0.4),
              width: 1.2,
            ),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Return to Home',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
