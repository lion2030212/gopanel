import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class AdminSecurityTab extends StatefulWidget {
  const AdminSecurityTab({
    required this.adminToken,
    required this.onSessionExpired,
    required this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio client;

  @override
  State<AdminSecurityTab> createState() => _AdminSecurityTabState();
}

class _AdminSecurityTabState extends State<AdminSecurityTab> {
  Map<String, dynamic> _security = const {};
  bool _isLoading = true;
  bool _isMutating = false;
  String? _errorMessage;
  String _period = 'day';
  DateTime? _customStartAt;
  DateTime? _customEndAt;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _securityRequestId = 0;

  Options get _requestOptions => Options(headers: {
        'Authorization': 'Bearer ${widget.adminToken}',
      });

  @override
  void initState() {
    super.initState();
    _loadSecurity();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSecuritySearchChanged(String _) {
    _securityRequestId++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchDebounce = null;
      _loadSecurity();
    });
  }

  Future<void> _loadSecurity() async {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    final requestId = ++_securityRequestId;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/security/overview',
        queryParameters: {
          'period': _period,
          'search': _searchController.text.trim(),
          if (_period == 'custom') ...{
            'startAt': _customStartAt!.toUtc().toIso8601String(),
            'endAt': _customEndAt!.toUtc().toIso8601String(),
          },
        },
        options: _requestOptions,
      );
      final security = response.data?['security'];
      if (security is! Map) throw const FormatException();
      if (!mounted || requestId != _securityRequestId) return;
      setState(() => _security = Map<String, dynamic>.from(security));
    } on DioException catch (error) {
      if (requestId != _securityRequestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else if (mounted) {
        setState(() => _errorMessage = _messageFrom(error, 'تعذر تحميل بيانات الأمان'));
      }
    } on FormatException {
      if (mounted && requestId == _securityRequestId) {
        setState(() => _errorMessage = 'استجابة بيانات الأمان غير مكتملة');
      }
    } finally {
      if (mounted && requestId == _securityRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _messageFrom(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map ? data['message']?.toString() ?? fallback : fallback;
  }

  List<Map<String, dynamic>> _asRows(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  Color _severityColor(String severity) => switch (severity) {
        'red' => Colors.red.shade700,
        'yellow' => Colors.amber.shade900,
        _ => Colors.green.shade700,
      };

  String _severityLabel(String severity) => switch (severity) {
        'red' => 'خطر أمني',
        'yellow' => 'يتطلب الانتباه',
        _ => 'النظام آمن',
      };

  String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return value?.toString() ?? 'غير متاح';
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  String _failureLabel(Object? value) => switch (value?.toString()) {
        'rate_limited' => 'محاولة أثناء القفل المؤقت',
        'ip_blocked' => 'محاولة من عنوان محظور',
        _ => 'بيانات دخول غير صحيحة',
      };

  String _sessionEndLabel(Map<String, dynamic> session) {
    if (session['active'] == true || session['active'] == 1) return 'نشطة';
    final logoutAt = session['logoutAt'];
    return logoutAt == null ? 'انتهت صلاحيتها' : _dateLabel(logoutAt);
  }

  Future<void> _selectPeriod(String period) async {
    if (period == 'custom') {
      await _selectCustomPeriod();
      return;
    }
    setState(() => _period = period);
    await _loadSecurity();
  }

  Future<DateTime?> _pickDate(DateTime initialDate) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: now.subtract(const Duration(days: 366)),
      lastDate: now,
    );
  }

  Future<void> _selectCustomPeriod() async {
    final now = DateTime.now();
    final startDate = await _pickDate(
      _customStartAt ?? now.subtract(const Duration(days: 1)),
    );
    if (startDate == null || !mounted) return;
    final endDate = await _pickDate(_customEndAt ?? now);
    if (endDate == null || !mounted) return;
    final startAt = DateTime(startDate.year, startDate.month, startDate.day);
    final endAt = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    );
    if (startDate.isAfter(endDate) || endDate.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد فترة صحيحة لا تتجاوز اليوم الحالي')),
      );
      return;
    }
    setState(() {
      _period = 'custom';
      _customStartAt = startAt;
      _customEndAt = endAt;
    });
    await _loadSecurity();
  }

  Future<void> _showBlockDialog({String? initialIp}) async {
    final blockDetails = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdminIpBlockDialog(
        initialIp: initialIp,
      ),
    );
    if (blockDetails == null || blockDetails['ipAddress']!.isEmpty) return;
    await _blockIp(blockDetails['ipAddress']!, blockDetails['reason']!);
  }

  Future<void> _blockIp(String ipAddress, String reason) async {
    setState(() => _isMutating = true);
    try {
      await widget.client.post<void>(
        '/api/admin/security/ip-blocks',
        data: {'ipAddress': ipAddress, 'reason': reason},
        options: _requestOptions,
      );
      await _loadSecurity();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else if (mounted) {
        setState(() => _errorMessage = _messageFrom(error, 'تعذر حظر عنوان IP'));
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _unblockIp(String ipAddress) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فك حظر عنوان IP؟'),
        content: Text(ipAddress, textDirection: TextDirection.ltr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey('securityConfirmUnblock'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('فك الحظر'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isMutating = true);
    try {
      await widget.client.delete<void>(
        '/api/admin/security/ip-blocks/${Uri.encodeComponent(ipAddress)}',
        options: _requestOptions,
      );
      await _loadSecurity();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else if (mounted) {
        setState(() => _errorMessage = _messageFrom(error, 'تعذر فك حظر عنوان IP'));
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _security['status']?.toString() ?? 'green';
    final statusColor = _severityColor(status);
    final alerts = _asRows(_security['alerts']);
    final recentFailures = _asRows(_security['recentFailures']);
    final sessions = _asRows(_security['sessions']);
    final blockedIps = _asRows(_security['blockedIps']);
    final failureCountsValue = _security['failureCounts'];
    final failureCounts = failureCountsValue is Map
      ? Map<String, dynamic>.from(failureCountsValue)
      : const <String, dynamic>{};

    return ListView(
      key: const ValueKey('adminSecurityTab'),
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          key: const ValueKey('securityStatusIndicator'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: statusColor, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _severityLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('حالة محاولات الدخول خلال آخر ${_security['windowMinutes'] ?? 5} دقائق'),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('refreshSecurity'),
                tooltip: 'تحديث المراقبة الأمنية',
                onPressed: _isLoading || _isMutating ? null : _loadSecurity,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Wrap(
            key: const ValueKey('securityPeriodFilters'),
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const {
                'day': 'يوم',
                'week': 'أسبوع',
                'month': 'شهر',
                'custom': 'مخصص',
              }.entries)
                ChoiceChip(
                  key: ValueKey('security-period-${option.key}'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.value),
                      if (option.key != 'custom' || _period == 'custom') ...[
                        const SizedBox(width: 6),
                        Container(
                          key: ValueKey('security-period-count-${option.key}'),
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: _period == option.key
                                ? Theme.of(context).colorScheme.onSecondaryContainer
                                    .withValues(alpha: 0.12)
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${failureCounts[option.key] ?? 0}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  selected: _period == option.key,
                  onSelected: _isLoading || _isMutating
                      ? null
                      : (_) => _selectPeriod(option.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('securitySearchInput'),
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'بحث باسم المستخدم أو عنوان IP',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _onSecuritySearchChanged,
          onSubmitted: (_) => _loadSecurity(),
        ),
        if (_isLoading) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(child: Text(_errorMessage!)),
                TextButton.icon(
                  onPressed: _loadSecurity,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        if (!_isLoading && _errorMessage == null) ...[
          const SizedBox(height: 20),
          _buildSectionTitle('الإنذارات الأمنية', Icons.notifications_active_outlined),
          if (alerts.isEmpty)
            const ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text('لا توجد محاولات مريبة خلال الفترة الحالية'),
            )
          else
            for (final alert in alerts)
              ListTile(
                key: ValueKey('securityAlert-${alert['ipAddress']}'),
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: _severityColor(alert['severity']?.toString() ?? 'yellow'),
                ),
                title: Text(
                  '${_severityLabel(alert['severity']?.toString() ?? 'yellow')} '
                  '(${alert['failureCount']} محاولات)',
                ),
                subtitle: Text(
                  alert['ipAddress']?.toString() ?? 'IP غير متاح',
                  textDirection: TextDirection.ltr,
                ),
                trailing: IconButton(
                  tooltip: 'حظر عنوان IP',
                  onPressed: _isMutating
                      ? null
                      : () => _showBlockDialog(
                            initialIp: alert['ipAddress']?.toString(),
                          ),
                  icon: const Icon(Icons.block_outlined),
                ),
              ),
          const SizedBox(height: 12),
          _buildSectionTitle('عناوين IP المحظورة', Icons.block_outlined),
          if (blockedIps.isEmpty)
            const ListTile(title: Text('لا توجد عناوين محظورة'))
          else
            for (final block in blockedIps)
              ListTile(
                key: ValueKey('blockedIp-${block['ipAddress']}'),
                title: Text(
                  block['ipAddress']?.toString() ?? 'IP غير متاح',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(block['reason']?.toString() ?? 'بدون سبب مسجل'),
                trailing: IconButton(
                  key: ValueKey('unblock-ip-${block['ipAddress']}'),
                  tooltip: 'فك الحظر',
                  onPressed: _isMutating
                      ? null
                      : () => _unblockIp(block['ipAddress'].toString()),
                  icon: const Icon(Icons.lock_open_outlined),
                ),
              ),
          const SizedBox(height: 12),
          _buildSectionTitle('محاولات الدخول الفاشلة', Icons.login_outlined),
          if (recentFailures.isEmpty)
            const ListTile(title: Text('لا توجد محاولات فاشلة مسجلة'))
          else
            for (final failure in recentFailures)
              ListTile(
                key: ValueKey('securityFailure-${failure['id']}'),
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text(failure['username']?.toString().isNotEmpty == true
                    ? failure['username'].toString()
                    : 'اسم مستخدم غير متاح'),
                subtitle: Text(
                  '${failure['ipAddress'] ?? 'IP غير متاح'} · '
                  '${_failureLabel(failure['failureReason'])} · '
                  '${_dateLabel(failure['attemptedAt'])}',
                  textDirection: TextDirection.rtl,
                ),
                trailing: IconButton(
                  tooltip: 'حظر عنوان IP',
                  onPressed: _isMutating || failure['ipAddress'] == null
                      ? null
                      : () => _showBlockDialog(
                            initialIp: failure['ipAddress'].toString(),
                          ),
                  icon: const Icon(Icons.block_outlined),
                ),
              ),
          const SizedBox(height: 12),
          _buildSectionTitle('جلسات الإدارة', Icons.devices_outlined),
          if (sessions.isEmpty)
            const ListTile(title: Text('لا توجد جلسات مسجلة'))
          else
            for (final session in sessions)
              ListTile(
                key: ValueKey('securitySession-${session['adminId']}-${session['loginAt']}'),
                leading: Icon(
                  session['active'] == true || session['active'] == 1
                      ? Icons.verified_user_outlined
                      : Icons.logout,
                ),
                title: Text(
                  session['username']?.toString() ??
                      session['adminId']?.toString() ??
                      'مدير',
                ),
                subtitle: Text(
                  '${session['ipAddress'] ?? 'IP غير متاح'} · '
                  'دخول ${_dateLabel(session['loginAt'])} · '
                  'خروج ${_sessionEndLabel(session)}',
                  textDirection: TextDirection.rtl,
                ),
              ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const ValueKey('addIpBlock'),
              onPressed: _isMutating ? null : () => _showBlockDialog(),
              icon: const Icon(Icons.add_moderator_outlined),
              label: const Text('حظر عنوان IP'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _AdminIpBlockDialog extends StatefulWidget {
  const _AdminIpBlockDialog({this.initialIp});

  final String? initialIp;

  @override
  State<_AdminIpBlockDialog> createState() => _AdminIpBlockDialogState();
}

class _AdminIpBlockDialogState extends State<_AdminIpBlockDialog> {
  late final TextEditingController _ipController;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialIp ?? '');
  }

  @override
  void dispose() {
    _ipController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('حظر عنوان IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('securityBlockIpInput'),
              controller: _ipController,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'عنوان IP'),
            ),
            TextField(
              key: const ValueKey('securityBlockReasonInput'),
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'سبب الحظر'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey('securityConfirmBlock'),
            onPressed: () => Navigator.pop(context, {
              'ipAddress': _ipController.text.trim(),
              'reason': _reasonController.text.trim(),
            }),
            icon: const Icon(Icons.block),
            label: const Text('تأكيد الحظر'),
          ),
        ],
      );
}