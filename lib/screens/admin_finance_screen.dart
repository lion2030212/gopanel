import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/admin_api_client.dart';

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen>
    with SingleTickerProviderStateMixin {
  static const _periods = <String, String>{
    'day': 'اليوم',
    'week': 'هذا الأسبوع',
    'month': 'هذا الشهر',
    'custom': 'مدة محددة',
  };
  static const _chartPeriods = <String, String>{
    '24h': '24 ساعة',
    'week': 'الأسبوع',
    'month': 'الشهر',
    'custom': 'مخصص',
  };
  static final _currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final _number = NumberFormat.decimalPattern('en');

  late final Dio _dio;
  late final TabController _tabController;
  Map<String, dynamic>? _overview;
  Map<String, dynamic>? _reports;
  DateTimeRange? _selectedRange;
  String _period = 'day';
  String _chartPeriod = '24h';
  String? _error;
  bool _isLoading = true;
  int _page = 1;
  int _selectedChartIndex = 0;
  Set<String> _visibleSeries = {'all', 'completed', 'cancelled'};

  @override
  void initState() {
    super.initState();
    _dio = widget.client ??
        createAdminApiClient(onSessionExpired: widget.onSessionExpired);
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (widget.client == null) _dio.close(force: true);
    super.dispose();
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  Map<String, dynamic> _periodParameters() => {
        'period': _period,
        if (_period == 'custom' && _selectedRange != null) ...{
          'startDate': DateFormat('yyyy-MM-dd').format(_selectedRange!.start),
          'endDate': DateFormat('yyyy-MM-dd').format(_selectedRange!.end),
        },
      };

  Future<void> _load() async {
    if (_period == 'custom' && _selectedRange == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final parameters = _periodParameters();
      final chartParameters = {
        ...parameters,
        'chartPeriod': _chartPeriod,
        if (_chartPeriod == 'custom' && _selectedRange != null) ...{
          'startDate': DateFormat('yyyy-MM-dd').format(_selectedRange!.start),
          'endDate': DateFormat('yyyy-MM-dd').format(_selectedRange!.end),
        },
      };
      final responses = await Future.wait([
        _dio.get<Map<String, dynamic>>(
          '/api/admin/finance/overview',
          queryParameters: chartParameters,
          options: _requestOptions,
        ),
        _dio.get<Map<String, dynamic>>(
          '/api/admin/finance/reports',
          queryParameters: {...parameters, 'page': _page, 'limit': 20},
          options: _requestOptions,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = _asMap(responses[0].data);
        _reports = _asMap(responses[1].data);
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
      } else if (error.response?.statusCode == 403) {
        setState(() => _error = 'ليست لديك صلاحية عرض الإدارة المالية');
      } else {
        setState(() => _error = 'تعذر تحميل التقارير المالية');
      }
    } on FormatException {
      if (mounted) setState(() => _error = 'بيانات التقارير المالية غير مكتملة');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _chooseRange({required bool forChart}) async {
    final now = DateTime.now();
    final initial = _selectedRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
      helpText: 'حدد بداية الفترة ونهايتها',
      saveText: 'تطبيق',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
    );
    if (range == null || !mounted) return;
    setState(() {
      _selectedRange = range;
      _selectedChartIndex = 0;
      if (forChart) {
        _chartPeriod = 'custom';
      } else {
        _period = 'custom';
        _page = 1;
      }
    });
    await _load();
  }

  Future<void> _selectPeriod(String period) async {
    if (period == 'custom') {
      await _chooseRange(forChart: false);
      return;
    }
    setState(() {
      _period = period;
      _page = 1;
    });
    await _load();
  }

  Future<void> _selectChartPeriod(String period) async {
    if (period == 'custom') {
      await _chooseRange(forChart: true);
      return;
    }
    setState(() {
      _chartPeriod = period;
      _selectedChartIndex = 0;
    });
    await _load();
  }

  Future<void> _changePage(int direction, int total) async {
    final lastPage = math.max(1, (total / 20).ceil());
    final nextPage = (_page + direction).clamp(1, lastPage);
    if (nextPage == _page) return;
    setState(() => _page = nextPage);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإدارة المالية'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'نظرة عامة', icon: Icon(Icons.insights_outlined)),
            Tab(text: 'التقارير المالية', icon: Icon(Icons.receipt_long_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'تحديث التقارير',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          _PeriodSelector(
            periods: _periods,
            selected: _period,
            onSelected: _selectPeriod,
            selectedRange: _selectedRange,
          ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              leading: Icon(Icons.error_outline, color: colors.error),
              actions: [
                TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
              ],
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildReports(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    if (_isLoading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_overview == null) return _buildEmpty();
    final totals = _asMap(_overview!['totals']);
    final comparison = _asMap(_overview!['comparison']);
    final growth = _asMap(_overview!['growth']);
    final chart = _asMap(_overview!['chart']);
    final buckets = _asMaps(chart['buckets']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          _MetricGrid(
            items: [
              _MetricData(
                title: 'الرحلات المكتملة',
                value: _number.format(_numberValue(totals['completedTrips'])),
                icon: Icons.route_outlined,
                color: const Color(0xff157a67),
                comparison: _numberValue(comparison['completedTrips']),
                growth: _nullableNumber(growth['completedTrips']),
              ),
              _MetricData(
                title: 'مدفوعات الركاب',
                value: _money(totals['riderPaid']),
                icon: Icons.payments_outlined,
                color: const Color(0xff2368a0),
                comparison: _numberValue(comparison['riderPaid']),
              ),
              _MetricData(
                title: 'صافي السائقين',
                value: _money(totals['driverNet']),
                icon: Icons.local_taxi_outlined,
                color: const Color(0xffb35b24),
                comparison: _numberValue(comparison['driverNet']),
              ),
              _MetricData(
                title: 'عمولة المنصة',
                value: _money(totals['commission']),
                icon: Icons.account_balance_outlined,
                color: const Color(0xff665c9a),
                comparison: _numberValue(comparison['commission']),
                growth: _nullableNumber(growth['commission']),
              ),
              _MetricData(
                title: 'العمولة المتحصلة',
                value: _money(totals['commissionCollected']),
                icon: Icons.task_alt_outlined,
                color: const Color(0xff4e7d39),
                comparison: _numberValue(comparison['commissionCollected']),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildChartCard(buckets),
        ],
      ),
    );
  }

  Widget _buildChartCard(List<Map<String, dynamic>> buckets) {
    final colors = Theme.of(context).colorScheme;
    final seriesColors = <String, Color>{
      'all': const Color(0xff202d39),
      'completed': const Color(0xff16846f),
      'cancelled': const Color(0xffc3524a),
    };
    final selected = buckets.isEmpty
        ? null
        : buckets[_selectedChartIndex.clamp(0, buckets.length - 1)];
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text('حركة الطلب',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: _chartPeriods.entries
                    .map((entry) => ButtonSegment(
                          value: entry.key,
                          label: Text(entry.value),
                        ))
                    .toList(),
                selected: {_chartPeriod},
                onSelectionChanged: (selection) =>
                    _selectChartPeriod(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final entry in seriesColors.entries)
                FilterChip(
                  selected: _visibleSeries.contains(entry.key),
                  avatar: Icon(Icons.circle, size: 12, color: entry.value),
                  label: Text(_seriesTitle(entry.key)),
                  onSelected: (selected) => setState(() {
                    final updated = Set<String>.from(_visibleSeries);
                    if (selected) {
                      updated.add(entry.key);
                    } else {
                      updated.remove(entry.key);
                    }
                    _visibleSeries = updated;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (buckets.isEmpty)
            const SizedBox(height: 220, child: Center(child: Text('لا توجد بيانات للفترة')))
          else
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final plotWidth = math.max(1, constraints.maxWidth - 38);
                    final index = ((details.localPosition.dx - 30) /
                            plotWidth * buckets.length)
                        .floor()
                        .clamp(0, buckets.length - 1);
                    setState(() => _selectedChartIndex = index);
                  },
                  child: CustomPaint(
                    painter: _FinanceChartPainter(
                      buckets: buckets,
                      visibleSeries: _visibleSeries,
                      seriesColors: seriesColors,
                      selectedIndex: _selectedChartIndex,
                      gridColor: colors.outlineVariant,
                      labelColor: colors.onSurfaceVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          if (selected != null) ...[
            const Divider(height: 16),
            Text(
              '${_bucketLabel(selected['bucket'])}  •  ${_seriesTitle('all')}: ${_number.format(_numberValue(selected['all']))}  •  مكتملة: ${_number.format(_numberValue(selected['completed']))}  •  ملغاة: ${_number.format(_numberValue(selected['cancelled']))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReports() {
    if (_isLoading && _reports == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reports == null) return _buildEmpty();
    final totals = _asMap(_reports!['totals']);
    final activity = _asMap(_reports!['riderWalletAdjustments']);
    final adjustments = _asMaps(activity['items']);
    final commissions = _asMaps(_reports!['commissionEvents']);
    final total = _numberValue(activity['total']).toInt();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          _MetricGrid(
            items: [
              _MetricData(title: 'إجمالي مدفوعات الركاب', value: _money(totals['riderPaid']), icon: Icons.payments_outlined, color: const Color(0xff2368a0)),
              _MetricData(title: 'صافي السائقين', value: _money(totals['driverNet']), icon: Icons.local_taxi_outlined, color: const Color(0xffb35b24)),
              _MetricData(title: 'إجمالي العمولة', value: _money(totals['commission']), icon: Icons.account_balance_outlined, color: const Color(0xff665c9a)),
              _MetricData(title: 'العمولة المتحصلة', value: _money(totals['commissionCollected']), icon: Icons.task_alt_outlined, color: const Color(0xff4e7d39)),
              _MetricData(title: 'إضافة لمحافظ الركاب', value: _money(totals['riderWalletAdded']), icon: Icons.add_circle_outline, color: const Color(0xff157a67)),
              _MetricData(title: 'خصم من محافظ الركاب', value: _money(totals['riderWalletDeducted']), icon: Icons.remove_circle_outline, color: const Color(0xffc3524a)),
              _MetricData(title: 'رسوم الإلغاء المحصلة', value: _money(totals['cancellationFeesCollected']), icon: Icons.event_busy_outlined, color: const Color(0xff8a6130)),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('حركات محفظة الركاب', total),
          if (adjustments.isEmpty)
            const _EmptySection(text: 'لا توجد حركات محفظة في هذه الفترة')
          else
            ...adjustments.map(_walletAdjustmentTile),
          if (total > 20)
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'الصفحة السابقة',
                    onPressed: _page > 1 ? () => _changePage(-1, total) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  Text('$_page / ${math.max(1, (total / 20).ceil())}'),
                  IconButton(
                    tooltip: 'الصفحة التالية',
                    onPressed: _page * 20 < total
                        ? () => _changePage(1, total)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _sectionTitle('سجل العمولات والتحصيلات', commissions.length),
          if (commissions.isEmpty)
            const _EmptySection(text: 'لا توجد حركات عمولة في هذه الفترة')
          else
            ...commissions.map(_commissionTile),
        ],
      ),
    );
  }

  Widget _walletAdjustmentTile(Map<String, dynamic> item) {
    final isCredit = item['direction'] == 'credit';
    final date = _formatDate(item['createdAt']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: (isCredit ? const Color(0xff157a67) : const Color(0xffc3524a))
            .withValues(alpha: 0.12),
        child: Icon(
          isCredit ? Icons.add : Icons.remove,
          color: isCredit ? const Color(0xff157a67) : const Color(0xffc3524a),
        ),
      ),
      title: Text(item['riderName']?.toString().isNotEmpty == true
          ? item['riderName'].toString()
          : 'راكب'),
      subtitle: Text([
        date,
        item['description']?.toString() ?? '',
        if (item['adminId'] != null) 'بواسطة ${item['adminId']}',
      ].where((value) => value.isNotEmpty).join(' • ')),
      trailing: Text(
        '${isCredit ? '+' : '-'}${_money(item['amount'])}',
        style: TextStyle(
          color: isCredit ? const Color(0xff157a67) : const Color(0xffc3524a),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _commissionTile(Map<String, dynamic> item) {
    final eventType = item['eventType']?.toString() ?? '';
    final collected = _numberValue(item['collectedAmount']);
    final debt = _numberValue(item['debtAmount']);
    final isReversed = item['isReversed'] == true || item['isReversed'] == 1;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        collected > 0 ? Icons.check_circle_outline : Icons.pending_outlined,
        color: collected > 0 ? const Color(0xff157a67) : const Color(0xffb35b24),
      ),
      title: Text('${_commissionTitle(eventType)}${isReversed ? ' • معكوسة' : ''}'),
      subtitle: Text(_formatDate(item['createdAt'])),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('متحصل ${_money(item['collectedAmount'])}'),
          if (debt > 0) Text('مستحق ${_money(debt)}'),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('$count', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد بيانات مالية لعرضها'),
            if (_error == null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      );

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _asMaps(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  static double _numberValue(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  static double? _nullableNumber(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

  static String _money(dynamic value) => _currency.format(_numberValue(value));

  static String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? value?.toString() ?? '' : DateFormat('yyyy/MM/dd  HH:mm').format(date.toLocal());
  }

  static String _bucketLabel(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 16) return text.substring(11, 16);
    return text;
  }

  static String _seriesTitle(String series) => switch (series) {
        'completed' => 'مكتملة',
        'cancelled' => 'ملغاة',
        _ => 'الإجمالي',
      };

  static String _commissionTitle(String type) => switch (type) {
        'ride_commission' => 'عمولة رحلة',
        'shortfall_recovery' => 'تحصيل عمولة دين رحلة',
        'debt_recovery' => 'سداد دين من محفظة السائق',
        'debt_increase' => 'زيادة الدين على السائق',
        _ => 'حركة عمولة',
      };
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.periods,
    required this.selected,
    required this.onSelected,
    required this.selectedRange,
  });

  final Map<String, String> periods;
  final String selected;
  final ValueChanged<String> onSelected;
  final DateTimeRange? selectedRange;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: periods.entries
                  .map((entry) => ButtonSegment(value: entry.key, label: Text(entry.value)))
                  .toList(),
              selected: {selected},
              onSelectionChanged: (values) => onSelected(values.first),
            ),
            if (selected == 'custom' && selectedRange != null)
              Text(
                '${DateFormat('yyyy/MM/dd').format(selectedRange!.start)} - ${DateFormat('yyyy/MM/dd').format(selectedRange!.end)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      );
}

class _MetricData {
  const _MetricData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.comparison,
    this.growth,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double? comparison;
  final double? growth;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_MetricData> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 3
              : constraints.maxWidth >= 650
                  ? 2
                  : 1;
          const spacing = 12.0;
          final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: _MetricCard(item: item),
                ),
            ],
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  static final _currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  final _MetricData item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final comparison = item.comparison;
    final growth = item.growth;
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: item.color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(item.title, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              item.value,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          if (growth != null)
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  growth >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: growth >= 0 ? const Color(0xff157a67) : colors.error,
                ),
                Text(
                  '${growth > 0 ? '+' : ''}${growth.toStringAsFixed(1)}% مقارنة بالفترة السابقة',
                  style: TextStyle(
                    fontSize: 11,
                    color: growth >= 0 ? const Color(0xff157a67) : colors.error,
                  ),
                ),
              ],
            )
          else if (comparison != null)
            Text('الفترة السابقة: ${item.title.contains('رحلات') ? _numberText(comparison) : _currency.format(comparison)}',
                style: Theme.of(context).textTheme.bodySmall)
          else
            Text('لا توجد فترة مقارنة', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  static String _numberText(double value) => NumberFormat.decimalPattern('en').format(value);
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      );
}

class _FinanceChartPainter extends CustomPainter {
  const _FinanceChartPainter({
    required this.buckets,
    required this.visibleSeries,
    required this.seriesColors,
    required this.selectedIndex,
    required this.gridColor,
    required this.labelColor,
  });

  final List<Map<String, dynamic>> buckets;
  final Set<String> visibleSeries;
  final Map<String, Color> seriesColors;
  final int selectedIndex;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 24.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final maxValue = math.max(
      1,
      buckets.fold<double>(
        0,
        (maximum, row) => visibleSeries.fold<double>(
          maximum,
          (current, series) => math.max(current, _value(row[series])),
        ),
      ),
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: labelColor, fontSize: 10);
    for (var line = 0; line <= 4; line++) {
      final y = plot.top + plot.height * line / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawText(canvas, _number(maxValue * (4 - line) / 4),
          Offset(0, y - 6), labelStyle);
    }
    for (final series in visibleSeries) {
      final color = seriesColors[series]!;
      final path = Path();
      final points = <Offset>[];
      for (var index = 0; index < buckets.length; index++) {
        final x = buckets.length <= 1
            ? plot.center.dx
            : plot.left + plot.width * index / (buckets.length - 1);
        final y = plot.bottom - plot.height * _value(buckets[index][series]) / maxValue;
        final point = Offset(x, y);
        points.add(point);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..strokeWidth = series == 'all' ? 2.8 : 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      for (var index = 0; index < points.length; index++) {
        canvas.drawCircle(points[index], index == selectedIndex ? 4 : 2.5,
            Paint()..color = color);
      }
    }
    if (buckets.isNotEmpty && selectedIndex < buckets.length) {
      final x = buckets.length <= 1
          ? plot.center.dx
          : plot.left + plot.width * selectedIndex / (buckets.length - 1);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), Paint()
        ..color = labelColor.withValues(alpha: 0.4)
        ..strokeWidth = 1);
    }
    _drawText(canvas, _bucketAxisLabel(buckets.first['bucket']),
        Offset(plot.left, plot.bottom + 7), labelStyle);
    _drawText(canvas, _bucketAxisLabel(buckets.last['bucket']),
        Offset(math.max(plot.left, plot.right - 38), plot.bottom + 7), labelStyle);
  }

  static double _value(dynamic value) => value is num ? value.toDouble() : 0;

  static String _number(double value) => value % 1 == 0
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static String _bucketAxisLabel(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 16 ? text.substring(11, 16) : text.substring(math.max(0, text.length - 5));
  }

  static void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.rtl,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_FinanceChartPainter oldDelegate) =>
      oldDelegate.buckets != buckets ||
      oldDelegate.visibleSeries != visibleSeries ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.gridColor != gridColor;
}