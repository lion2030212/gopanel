import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class StaffSmartReportTab extends StatefulWidget {
  const StaffSmartReportTab({
    required this.client,
    required this.adminToken,
    required this.staffId,
    required this.onSessionExpired,
    super.key,
  });

  final Dio client;
  final String adminToken;
  final int staffId;
  final ValueChanged<String> onSessionExpired;

  @override
  State<StaffSmartReportTab> createState() => _StaffSmartReportTabState();
}

class _StaffSmartReportTabState extends State<StaffSmartReportTab> {
  String _period = 'month';
  DateTimeRange? _customRange;
  Map<String, dynamic>? _report;
  String? _error;
  bool _loading = true;
  int _requestId = 0;

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  @override
  void initState() {
    super.initState();
    unawaited(_loadReport());
  }

  String _dateParameter(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _selectCustomRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _customRange ?? DateTimeRange(start: today, end: today),
      helpText: 'اختر مدة التقرير',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );
    if (!mounted || selectedRange == null) return;
    setState(() {
      _period = 'custom';
      _customRange = DateTimeRange(
        start: DateUtils.dateOnly(selectedRange.start),
        end: DateUtils.dateOnly(selectedRange.end),
      );
    });
    unawaited(_loadReport());
  }

  Future<void> _loadReport() async {
    final requestId = ++_requestId;
    final queryParameters = <String, dynamic>{'period': _period};
    if (_period == 'custom' && _customRange != null) {
      queryParameters['startAt'] = _dateParameter(_customRange!.start);
      queryParameters['endAt'] = _dateParameter(_customRange!.end);
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/staff/${widget.staffId}/smart-report',
        queryParameters: queryParameters,
        options: _requestOptions,
      );
      if (!mounted || requestId != _requestId) return;
      final report = response.data?['report'];
      setState(() {
        _report = report is Map ? Map<String, dynamic>.from(report) : null;
        _loading = false;
        if (_report == null) _error = 'تعذر قراءة بيانات التقرير';
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
      }
      final responseData = error.response?.data;
      final message = responseData is Map
          ? responseData['message']?.toString()
          : null;
      setState(() {
        _error = message ?? 'تعذر تحميل التقرير الذكي';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  String _count(Object? value) =>
      (int.tryParse(value?.toString() ?? '') ?? 0).toString();

  String _decimal(Object? value) {
    final number = double.tryParse(value?.toString() ?? '');
    return number == null ? 'غير متاح' : number.toStringAsFixed(2);
  }

  String _duration(Object? value) {
    final seconds = int.tryParse(value?.toString() ?? '');
    if (seconds == null) return 'غير متاح';
    final hours = seconds ~/ 3600;
    final minutes = seconds.remainder(3600) ~/ 60;
    return hours == 0 ? '$minutes دقيقة' : '$hours ساعة و $minutes دقيقة';
  }

  String _durationDelta(Object? value) {
    final seconds = int.tryParse(value?.toString() ?? '');
    if (seconds == null) return 'غير متاح';
    final sign = seconds > 0 ? '+' : seconds < 0 ? '−' : '';
    return '$sign${_duration(seconds.abs())}';
  }

  String _delta(Object? value) {
    final delta = int.tryParse(value?.toString() ?? '');
    if (delta == null) return 'غير متاح';
    return delta > 0 ? '+$delta' : '$delta';
  }

  String _shortDate(Object? value) {
    final text = value?.toString();
    return text == null || text.length < 10 ? '—' : text.substring(0, 10);
  }

  String _categorySummary(Object? value) {
    final categories = _map(value);
    if (categories.isEmpty) return 'لا توجد تذاكر محلولة في هذه الفترة';
    const labels = {
      'payment': 'الدفع',
      'driver_issue': 'مشكلة سائق',
      'past_ride': 'رحلة سابقة',
      'technical': 'تقنية',
      'other': 'أخرى',
    };
    return categories.entries
        .map((entry) => '${labels[entry.key] ?? entry.key}: ${_count(entry.value)}')
        .join(' · ');
  }

  Widget _metric(String label, String value, String note, IconData icon) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 5),
                    Text(value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(note, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _metricGrid(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760
              ? 3
              : constraints.maxWidth >= 440
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children) SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Widget _section(String title, List<Widget> metrics) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const Divider(height: 20),
            _metricGrid(metrics),
          ],
        ),
      );

  Widget _buildReport(Map<String, dynamic> report) {
    final staff = _map(report['staff']);
    final current = _map(report['current']);
    final previous = _map(report['previous']);
    final currentConversations = _map(current['conversations']);
    final previousConversations = _map(previous['conversations']);
    final currentTickets = _map(current['tickets']);
    final previousTickets = _map(previous['tickets']);
    final currentRatings = _map(current['ratings']);
    final previousRatings = _map(previous['ratings']);
    final currentSessions = _map(current['sessions']);
    final previousSessions = _map(previous['sessions']);
    final currentNotifications = _map(current['notifications']);
    final previousNotifications = _map(previous['notifications']);
    final comparison = _map(report['comparison']);
    final advisory = _map(report['advisory']);
    final range = _map(current['range']);
    final rangeEnd = _period == 'custom' && _customRange != null
        ? _dateParameter(_customRange!.end)
        : _shortDate(range['endAt']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(
                    value: 'week',
                    label: Text('الأسبوع'),
                    icon: Icon(Icons.calendar_view_week_outlined),
                  ),
                  ButtonSegment(
                    value: 'month',
                    label: Text('الشهر'),
                    icon: Icon(Icons.calendar_month_outlined),
                  ),
                ],
                selected: _period == 'custom' ? <String>{} : {_period},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty || selection.first == _period) return;
                  setState(() => _period = selection.first);
                  unawaited(_loadReport());
                },
              ),
            ),
            IconButton(
              tooltip: 'مدة محددة',
              onPressed: _selectCustomRange,
              style: _period == 'custom'
                  ? IconButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                    )
                  : null,
              icon: const Icon(Icons.date_range_outlined),
            ),
            IconButton(
              tooltip: 'تحديث التقرير',
              onPressed: _loading ? null : _loadReport,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الملخص التنفيذي والتوصية',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 8),
                Text('${staff['fullName'] ?? 'ملف الموظف'} · ${staff['jobTitle'] ?? 'موظف'}'),
                Text('الفترة: ${_shortDate(range['startAt'])} إلى $rangeEnd'),
                const SizedBox(height: 8),
                Text(advisory['label']?.toString() ?? 'ملخص اتجاهات الفترة',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 4),
                Text(advisory['summary']?.toString() ??
                    'تعرض المؤشرات النشاط المسجل دون إصدار حكم وظيفي.'),
                if (advisory['reasons'] is List)
                  for (final reason in advisory['reasons'] as List)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $reason'),
                    ),
              ],
            ),
          ),
        ),
        _section('وقت تسجيل الدخول والمقارنة', [
          _metric(
            'مدة تسجيل الدخول',
            _duration(currentSessions['durationSeconds']),
            'الفترة السابقة ${_duration(previousSessions['durationSeconds'])}',
            Icons.login_outlined,
          ),
          _metric(
            'فرق مدة تسجيل الدخول',
            _durationDelta(comparison['sessionDurationSecondsDelta']),
            'مقارنة بالفترة السابقة المناظرة',
            Icons.compare_arrows,
          ),
          _metric(
            'جلسات مسجلة',
            _count(currentSessions['count']),
            'الفترة السابقة ${_count(previousSessions['count'])}',
            Icons.devices_outlined,
          ),
        ]),
        _section('النقاط الإيجابية', [
          _metric(
            'محادثات مغلقة',
            _count(currentConversations['closed']),
            'السابقة ${_count(previousConversations['closed'])} · التغير ${_delta(comparison['closedConversationsDelta'])}',
            Icons.forum_outlined,
          ),
          _metric(
            'تذاكر محلولة',
            _count(currentTickets['resolved']),
            'السابقة ${_count(previousTickets['resolved'])} · التغير ${_delta(comparison['resolvedTicketsDelta'])}',
            Icons.task_alt_outlined,
          ),
          _metric(
            'متوسط التقييم',
            _decimal(currentRatings['average']),
            'من 5 · عينة ${_count(currentRatings['count'])} · السابق ${_decimal(previousRatings['average'])}',
            Icons.star_outline,
          ),
          _metric(
            'التقييمات المستلمة',
            _count(currentRatings['count']),
            'السابقة ${_count(previousRatings['count'])} · التغير ${_delta(comparison['ratingsCountDelta'])}',
            Icons.reviews_outlined,
          ),
        ]),
        _section('الملاحظات التشغيلية', [
          _metric(
            'الردود على المحادثات',
            _count(currentConversations['replies']),
            'السابقة ${_count(previousConversations['replies'])}',
            Icons.forum_outlined,
          ),
          _metric(
            'الردود على التذاكر',
            _count(currentTickets['replies']),
            'السابقة ${_count(previousTickets['replies'])}',
            Icons.reply_outlined,
          ),
          _metric(
            'متوسط زمن حل التذكرة',
            currentTickets['averageResolutionMinutes'] == null
                ? 'غير متاح'
                : '${_decimal(currentTickets['averageResolutionMinutes'])} دقيقة',
            'عينة ${_count(currentTickets['resolved'])} تذكرة',
            Icons.schedule_outlined,
          ),
          _metric(
            'فئات التذاكر المحلولة',
            _categorySummary(currentTickets['categories']),
            '',
            Icons.category_outlined,
          ),
          _metric(
            'حملات التنبيه',
            _count(currentNotifications['campaigns']),
            'السابقة ${_count(previousNotifications['campaigns'])} · التغير ${_delta(comparison['campaignsDelta'])}',
            Icons.notifications_outlined,
          ),
          _metric(
            'المستلمون المقبولون',
            _count(currentNotifications['acceptedRecipients']),
            'الفترة السابقة ${_count(previousNotifications['acceptedRecipients'])}',
            Icons.people_outline,
          ),
          _metric(
            'الأجهزة التي قبلت الإشعار',
            _count(currentNotifications['acceptedDevices']),
            'قراءات ${_count(currentNotifications['readNotifications'])} · إخفاقات مستلمين ${_count(currentNotifications['failedRecipients'])}',
            Icons.phonelink_ring_outlined,
          ),
        ]),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(
            'تبدأ تغطية الجلسات من ${_shortDate(currentSessions['coverageStart'])}، وتبدأ مقارنة المحادثات والتذاكر من تسجيل أوقات إتمامها.',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    final report = _report;
    if (report == null) return const SizedBox.shrink();
    return Stack(
      children: [
        _buildReport(report),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}