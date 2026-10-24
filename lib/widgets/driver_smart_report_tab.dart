import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class DriverSmartReportTab extends StatefulWidget {
  const DriverSmartReportTab({
    required this.client,
    required this.adminToken,
    required this.driverId,
    required this.onSessionExpired,
    super.key,
  });

  final Dio client;
  final String adminToken;
  final int driverId;
  final ValueChanged<String> onSessionExpired;

  @override
  State<DriverSmartReportTab> createState() => _DriverSmartReportTabState();
}

class _DriverSmartReportTabState extends State<DriverSmartReportTab> {
  String _period = 'month';
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

  Future<void> _loadReport() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/drivers/${widget.driverId}/smart-report',
        queryParameters: {'period': _period},
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
      setState(() {
        _error = error.response?.data is Map
            ? (error.response?.data['message']?.toString() ??
                'تعذر تحميل التقرير الذكي')
            : 'تعذر تحميل التقرير الذكي';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  String _count(Object? value) => (int.tryParse(value?.toString() ?? '') ?? 0)
      .toString();

  String _percent(Object? value) {
    final rate = double.tryParse(value?.toString() ?? '');
    return rate == null ? 'غير متاح' : '${(rate * 100).toStringAsFixed(1)}٪';
  }

  String _decimal(Object? value, {int places = 1}) {
    final number = double.tryParse(value?.toString() ?? '');
    return number == null ? 'غير متاح' : number.toStringAsFixed(places);
  }

  String _hours(Object? value) {
    final seconds = int.tryParse(value?.toString() ?? '');
    return seconds == null ? 'غير متاح' : '${(seconds / 3600).toStringAsFixed(1)} ساعة';
  }

  String _shortDate(Object? value) {
    final text = value?.toString();
    if (text == null || text.length < 10) return '—';
    return text.substring(0, 10);
  }

  Color _verdictColor(String code, ColorScheme colors) => switch (code) {
        'excellent' => Colors.green.shade700,
        'review' => colors.error,
        'monitor' => Colors.orange.shade800,
        _ => colors.primary,
      };

  IconData _verdictIcon(String code) => switch (code) {
        'excellent' => Icons.check_circle_outline,
        'review' => Icons.report_gmailerrorred_outlined,
        'monitor' => Icons.visibility_outlined,
        _ => Icons.info_outline,
      };

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const Divider(height: 20),
            _metricGrid(children),
          ],
        ),
      );

  Widget _metricGrid(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760
              ? 3
              : constraints.maxWidth >= 440
                  ? 2
                  : 1;
          final width =
              (constraints.maxWidth - (12 * (columns - 1))) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children) SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Widget _metric(String label, String value, String note, IconData icon) =>
      Card(
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

  Widget _buildReport(Map<String, dynamic> report) {
    final current = _map(report['current']);
    final previous = _map(report['previous']);
    final driver = _map(report['driver']);
    final online = _map(report['online']);
    final comparison = _map(report['comparison']);
    final offers = _map(current['offers']);
    final rides = _map(current['rides']);
    final ratings = _map(current['ratings']);
    final reports = _map(current['reports']);
    final previousRides = _map(previous['rides']);
    final previousOffers = _map(previous['offers']);
    final previousRatings = _map(previous['ratings']);
    final range = _map(current['range']);
    final recommendation = _map(report['recommendation']);
    final reasons = recommendation['reasons'] is List
        ? (recommendation['reasons'] as List).map((item) => item.toString())
        : const <String>[];
    final colorScheme = Theme.of(context).colorScheme;
    final code = recommendation['code']?.toString() ?? 'insufficient_data';
    final verdictColor = _verdictColor(code, colorScheme);
    final accountStatus = driver['accountStatus']?.toString() ?? 'غير معروف';
    final onlineNow = driver['isOnline'] == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
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
                selected: {_period},
                onSelectionChanged: (selection) {
                  final selected = selection.first;
                  if (selected == _period) return;
                  setState(() => _period = selected);
                  unawaited(_loadReport());
                },
              ),
            ),
            IconButton(
              tooltip: 'تحديث التقرير',
              onPressed: _loading ? null : _loadReport,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الملخص التنفيذي',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: Icon(_verdictIcon(code), color: verdictColor),
                      label: Text(recommendation['label']?.toString() ??
                          'بيانات غير كافية للحكم'),
                    ),
                    Chip(
                      label: Text(onlineNow ? 'متصل الآن' : 'غير متصل الآن'),
                    ),
                    Chip(label: Text('حالة الحساب: $accountStatus')),
                  ],
                ),
                Text('الفترة: ${_shortDate(range['startAt'])} إلى ${_shortDate(range['endAt'])}'),
                const SizedBox(height: 4),
                Text('التوصية إدارية مساعدة ولا تغيّر حالة الحساب تلقائياً.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final reason in reasons)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $reason'),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _section('وقت الاتصال والمقارنة', [
          _metric(
            'ساعات الاتصال',
            _hours(online['currentSeconds']),
            'تشمل الوقت أثناء الرحلة، ولا تعني الجاهزية لطلب جديد',
            Icons.wifi_tethering,
          ),
          _metric(
            'الفترة السابقة',
            _hours(online['previousSeconds']),
            'التغطية تبدأ ${_shortDate(online['coverageStart'])}',
            Icons.history,
          ),
          _metric(
            'فرق ساعات الاتصال',
            online['currentSeconds'] == null || online['previousSeconds'] == null
                ? 'غير متاح'
                : '${_decimal((int.parse(online['currentSeconds'].toString()) - int.parse(online['previousSeconds'].toString())) / 3600)} ساعة',
            'مقارنة بالفترة السابقة المناظرة',
            Icons.compare_arrows,
          ),
          _metric(
            'فرق الرحلات المكتملة',
            _count(comparison['completedRidesDelta']),
            'الحالية ${_count(rides['completed'])} · السابقة ${_count(previousRides['completed'])}',
            Icons.route_outlined,
          ),
          _metric(
            'فرق معدل القبول',
            comparison['acceptanceRateDelta'] == null
                ? 'غير متاح'
                : '${_decimal(double.parse(comparison['acceptanceRateDelta'].toString()) * 100)} نقطة',
            'الحالي ${_percent(offers['acceptanceRate'])} · السابق ${_percent(previousOffers['acceptanceRate'])}',
            Icons.trending_up,
          ),
        ]),
        _section('النقاط الإيجابية', [
          _metric(
            'معدل قبول العروض',
            _percent(offers['acceptanceRate']),
            '${_count(offers['accepted'])} قبول من ${_count(offers['closed'])} عرض مغلق',
            Icons.thumb_up_alt_outlined,
          ),
          _metric(
            'رحلات مكتملة',
            _count(rides['completed']),
            'معدل الإكمال ${_percent(rides['completionRate'])}',
            Icons.task_alt,
          ),
          _metric(
            'متوسط تقييم الركاب',
            _decimal(ratings['average'], places: 2),
            'من 5 · ${_count(ratings['count'])} تقييمات · السابق ${_decimal(previousRatings['average'], places: 2)} من ${_count(previousRatings['count'])}',
            Icons.star_outline,
          ),
          _metric(
            'متوسط استجابة العروض',
            offers['averageResponseSeconds'] == null
                ? 'غير متاح'
                : '${_decimal(double.parse(offers['averageResponseSeconds'].toString()))} ثانية',
            '',
            Icons.bolt_outlined,
          ),
        ]),
        _section('الملاحظات التشغيلية', [
          _metric(
            'رفض صريح',
            _count(offers['rejected']),
            'انتهاء المهلة ${_count(offers['expired'])} · ملغى ${_count(offers['cancelled'])}',
            Icons.block_outlined,
          ),
          _metric(
            'متوسط الوصول للاستلام',
            rides['averagePickupDelayMinutes'] == null
                ? 'غير متاح'
                : '${_decimal(rides['averagePickupDelayMinutes'])} دقيقة',
            'عينة ${_count(rides['pickupDelaySample'])}',
            Icons.timer_outlined,
          ),
          _metric(
            'متوسط مدة الرحلة',
            rides['averageRideDurationMinutes'] == null
                ? 'غير متاح'
                : '${_decimal(rides['averageRideDurationMinutes'])} دقيقة',
            'عينة ${_count(rides['rideDurationSample'])}',
            Icons.schedule_outlined,
          ),
          _metric(
            'نسبة طول المسار',
            rides['averageRouteDistanceRatio'] == null
                ? 'غير متاح'
                : '${_decimal(rides['averageRouteDistanceRatio'])}×',
            'عينة ${_count(rides['routeSample'])} · لا تثبت التعمد',
            Icons.alt_route,
          ),
          _metric(
            'عدم حضور مسجل',
            _count(rides['noShow']),
            'يُحتسب من الحالات الموثقة منذ التحديث فقط',
            Icons.person_off_outlined,
          ),
          _metric(
            'تذاكر ركاب مرتبطة',
            _count(reports['linkedRiderTickets']),
            'غير المحلولة ${_count(reports['unresolved'])} · ليست إثباتاً لمخالفة',
            Icons.report_outlined,
          ),
          _metric(
            'تذاكر قدّمها السائق',
            _count(report['driverFiledTickets']),
            'تعرض منفصلة ولا تُحسب شكوى ضده',
            Icons.support_agent_outlined,
          ),
        ]),
        if (online['coverageStart'] == null)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('لا تتوفر تغطية تاريخية لساعات الاتصال بعد.'),
          ),
        if (online['coverageStart'] != null &&
            range['startAt'] != null &&
            online['coverageStart'].toString().compareTo(
                    range['startAt'].toString()) >
                0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(
                'ساعات الاتصال تغطي الفترة منذ ${_shortDate(online['coverageStart'])} فقط.'),
          ),
        if (int.tryParse(ratings['count']?.toString() ?? '') == 0 ||
            int.tryParse(offers['closed']?.toString() ?? '') == 0)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('تُعرض المؤشرات دون تقييم عند غياب عينة كافية.'),
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
        if (_loading)
          const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}