import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class RiderSmartReportTab extends StatefulWidget {
  const RiderSmartReportTab({
    required this.client,
    required this.adminToken,
    required this.riderId,
    required this.onSessionExpired,
    super.key,
  });

  final Dio client;
  final String adminToken;
  final int riderId;
  final ValueChanged<String> onSessionExpired;

  @override
  State<RiderSmartReportTab> createState() => _RiderSmartReportTabState();
}

class _RiderSmartReportTabState extends State<RiderSmartReportTab> {
  String _period = 'day';
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
    final customRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _customRange ?? DateTimeRange(start: today, end: today),
      helpText: 'اختر مدة التقرير',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );
    if (!mounted || customRange == null) return;
    setState(() {
      _period = 'custom';
      _customRange = DateTimeRange(
        start: DateUtils.dateOnly(customRange.start),
        end: DateUtils.dateOnly(customRange.end),
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
        '/api/admin/riders/${widget.riderId}/smart-report',
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
      setState(() {
        _error = error.response?.data is Map
            ? (error.response?.data['message']?.toString() ??
                'تعذر تحميل التقرير الذكي')
            : 'تعذر تحميل التقرير الذكي';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  String _count(Object? value) =>
      (int.tryParse(value?.toString() ?? '') ?? 0).toString();

  double? _number(Object? value) =>
      value == null ? null : double.tryParse(value.toString());

  String _decimal(Object? value, {int places = 1}) =>
      _number(value)?.toStringAsFixed(places) ?? 'غير متاح';

  String _percent(Object? value) {
    final rate = _number(value);
    return rate == null ? 'غير متاح' : '${(rate * 100).toStringAsFixed(1)}٪';
  }

  String _date(Object? value) {
    final text = value?.toString();
    return text == null || text.length < 10 ? '—' : text.substring(0, 10);
  }

  String _delta(Object? value, {bool percent = false}) {
    final number = _number(value);
    if (number == null) return 'غير متاح';
    final prefix = number > 0 ? '+' : '';
    return percent
        ? '$prefix${(number * 100).toStringAsFixed(1)} نقطة'
        : '$prefix${number.toStringAsFixed(0)}';
  }

  Color _recommendationColor(String code, ColorScheme colors) => switch (code) {
        'excellent' => Colors.green.shade700,
        'review' => colors.error,
        'monitor' => Colors.orange.shade800,
        _ => colors.primary,
      };

  IconData _recommendationIcon(String code) => switch (code) {
        'excellent' => Icons.check_circle_outline,
        'review' => Icons.account_balance_wallet_outlined,
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
          final width = (constraints.maxWidth - (12 * (columns - 1))) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
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
              Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
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
    final rider = _map(report['rider']);
    final current = _map(report['current']);
    final previous = _map(report['previous']);
    final currentRides = _map(current['rides']);
    final previousRides = _map(previous['rides']);
    final currentRatings = _map(current['ratings']);
    final previousRatings = _map(previous['ratings']);
    final financial = _map(current['financial']);
    final support = _map(current['support']);
    final recommendation = _map(report['recommendation']);
    final reasons = recommendation['reasons'] is List
        ? (recommendation['reasons'] as List).map((item) => item.toString())
        : const <String>[];
    final colors = Theme.of(context).colorScheme;
    final code = recommendation['code']?.toString() ?? 'insufficient_data';
    final range = _map(current['range']);
    final endLabel = _period == 'custom' && _customRange != null
        ? _dateParameter(_customRange!.end)
        : _date(range['endAt']);
    final totalDue = _number(financial['totalDue']);

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
                    value: 'day',
                    label: Text('اليوم'),
                  ),
                  ButtonSegment(
                    value: 'week',
                    label: Text('الأسبوع'),
                  ),
                  ButtonSegment(
                    value: 'month',
                    label: Text('الشهر'),
                  ),
                ],
                selected: _period == 'custom' ? <String>{} : {_period},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  final selected = selection.first;
                  if (selected == _period) return;
                  setState(() => _period = selected);
                  unawaited(_loadReport());
                },
              ),
            ),
            IconButton(
              tooltip: 'مدة محددة',
              onPressed: _selectCustomRange,
              style: _period == 'custom'
                  ? IconButton.styleFrom(
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
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
                  children: [
                    Chip(
                      avatar: Icon(_recommendationIcon(code),
                          color: _recommendationColor(code, colors)),
                      label: Text(recommendation['label']?.toString() ??
                          'بيانات غير كافية للحكم'),
                    ),
                    Chip(
                      label: Text(
                          'حالة الحساب: ${rider['accountStatus'] ?? 'غير معروفة'}'),
                    ),
                  ],
                ),
                Text('الفترة: ${_date(range['startAt'])} إلى $endLabel'),
                const SizedBox(height: 4),
                Text(
                  'التوصية استرشادية؛ الإلغاءات وتذاكر الدعم لا تثبت مسؤولية الراكب.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
        _section('المقارنة مع الفترة السابقة', [
          _metric(
            'فرق الرحلات المكتملة',
            _delta(report['comparison']?['completedRidesDelta']),
            'الحالية ${_count(currentRides['completed'])} · السابقة ${_count(previousRides['completed'])}',
            Icons.compare_arrows,
          ),
          _metric(
            'فرق متوسط التقييم',
            _delta(report['comparison']?['ratingAverageDelta'], percent: true),
            'الحالي ${_decimal(currentRatings['average'], places: 2)} · السابق ${_decimal(previousRatings['average'], places: 2)}',
            Icons.trending_up,
          ),
        ]),
        _section('النقاط الإيجابية', [
          _metric(
            'رحلات مكتملة',
            _count(currentRides['completed']),
            'من ${_count(currentRides['requested'])} طلبات خلال الفترة',
            Icons.task_alt,
          ),
          _metric(
            'معدل إكمال الرحلات',
            _percent(currentRides['completionRate']),
            '${_count(currentRides['completed'])} مكتملة من الرحلات المكتملة والملغاة',
            Icons.check_circle_outline,
          ),
          _metric(
            'متوسط التقييم المستلم',
            _decimal(currentRatings['average'], places: 2),
            'من 5 · ${_count(currentRatings['count'])} تقييمات',
            Icons.star_outline,
          ),
        ]),
        _section('مؤشرات تحتاج انتباه', [
          _metric(
            'التقييمات المنخفضة',
            _count(currentRatings['lowCount']),
            '3 نجوم أو أقل من ${_count(currentRatings['count'])} تقييمات مستلمة',
            Icons.star_border,
          ),
          _metric(
            'مبالغ مستحقة مؤكدة',
            totalDue == null ? 'غير متاح' : totalDue.toStringAsFixed(2),
            'بعد احتساب التحصيل والاستردادات والتسويات',
            Icons.account_balance_wallet_outlined,
          ),
        ]),
        _section('سياق للمراجعة', [
          _metric(
            'رحلات ملغاة',
            _count(currentRides['cancelled']),
            'لا تتوفر نسبة موثوقة للإلغاء إلى الراكب أو الكابتن',
            Icons.do_not_disturb_on_outlined,
          ),
          _metric(
            'تذاكر دعم مقدمة',
            _count(support['submitted']),
            '${_count(support['unresolved'])} غير محلولة · مقدمة من الراكب ولا تعد شكوى ضده',
            Icons.support_agent_outlined,
          ),
        ]),
        if (_number(currentRatings['count']) == 0)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('لا توجد تقييمات مستلمة كافية لعرض حكم على التقييم.'),
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
