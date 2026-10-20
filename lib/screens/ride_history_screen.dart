import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';
import '../widgets/dashboard_navigation.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.canReverseSettlement = false,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final bool canReverseSettlement;
  final Dio? client;

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  static const Map<String, String> _groups = {
    'active': 'النشطة',
    'cancelled': 'الملغاة',
    'completed': 'المكتملة',
  };
  static const Set<String> _activeStatuses = {
    'accepted',
    'arriving',
    'in_progress',
  };

  late final Dio _dio;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;
  String _group = 'active';
  String _period = 'all';
  DateTimeRange? _customRange;
  List<Map<String, dynamic>> _rides = [];
  Map<String, dynamic>? _ride;
  String? _error;
  bool _loading = false;
  bool _loadingDetails = false;
  bool _submittingAction = false;
  bool _hasMore = false;
  int _page = 1;
  int _requestId = 0;
  int _detailRequestId = 0;
  int? _selectedRideId;
  DashboardBackHandler? _dashboardBackHandler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final handler = DashboardBackHandlerScope.maybeOf(context);
    if (identical(handler, _dashboardBackHandler)) return;
    _dashboardBackHandler?.unregister(this);
    _dashboardBackHandler = handler;
    handler?.register(this, _handleDashboardBack);
  }

  @override
  void initState() {
    super.initState();
    _dio = widget.client ??
        createAdminApiClient(
          onSessionExpired: widget.onSessionExpired,
        );
    unawaited(_loadRides(reset: true));
  }

  @override
  void dispose() {
    _dashboardBackHandler?.unregister(this);
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    setState(() {});
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadRides(reset: true));
    });
  }

  Future<void> _selectPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _customRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة الرحلات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _period = period;
        _customRange = selectedRange;
      });
      await _loadRides(reset: true);
      return;
    }
    setState(() => _period = period);
    await _loadRides(reset: true);
  }

  DateTimeRange? _rideDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'today':
        return DateTimeRange(
            start: today, end: today.add(const Duration(days: 1)));
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: yesterday, end: today);
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1),
        );
      case 'custom':
        final range = _customRange;
        if (range == null) return null;
        final start =
            DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day)
            .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  String _dateLabel(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  Future<void> _selectGroup(String group) async {
    if (group == _group) return;
    setState(() {
      _group = group;
      _ride = null;
      _selectedRideId = null;
      _error = null;
    });
    await _loadRides(reset: true);
  }

  Future<void> _loadRides({required bool reset}) async {
    final requestId = ++_requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queryParameters = <String, dynamic>{
        'group': _group,
        'page': page,
        'limit': 30,
      };
      final search = _searchController.text.trim();
      if (search.isNotEmpty) queryParameters['search'] = search;
      final dateRange = _rideDateRange();
      if (dateRange != null) {
        queryParameters['startAt'] = dateRange.start.toUtc().toIso8601String();
        queryParameters['endAt'] = dateRange.end.toUtc().toIso8601String();
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/rides',
        queryParameters: queryParameters,
        options: _requestOptions,
      );
      if (!mounted || requestId != _requestId) return;
      final data = response.data ?? const {};
      final rows = data['rides'];
      final rides = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      final total = (data['total'] as num?)?.toInt() ?? rides.length;
      setState(() {
        _rides = reset ? rides : [..._rides, ...rides];
        _page = page;
        _hasMore = _rides.length < total;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (_isUnauthorized(error)) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() => _error = _messageFrom(error, 'تعذر تحميل سجل الرحلات'));
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openRide(int rideId) async {
    final requestId = ++_detailRequestId;
    setState(() {
      _selectedRideId = rideId;
      _ride = null;
      _loadingDetails = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/rides/$rideId',
        options: _requestOptions,
      );
      if (!mounted ||
          requestId != _detailRequestId ||
          _selectedRideId != rideId) {
        return;
      }
      final data = response.data ?? const {};
      final details = data['ride'];
      setState(() {
        _ride = details is Map ? Map<String, dynamic>.from(details) : null;
        _loadingDetails = false;
      });
    } on DioException catch (error) {
      if (!mounted ||
          requestId != _detailRequestId ||
          _selectedRideId != rideId) {
        return;
      }
      if (_isUnauthorized(error)) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() {
          _error = _messageFrom(error, 'تعذر تحميل تفاصيل الرحلة');
          _loadingDetails = false;
        });
      }
    }
  }

  bool _handleDashboardBack() {
    if (_selectedRideId == null) return false;
    if (_submittingAction) return true;
    _detailRequestId++;
    setState(() {
      _selectedRideId = null;
      _ride = null;
      _loadingDetails = false;
      _error = null;
    });
    return true;
  }

  Future<void> _performAction(String action) async {
    final rideId = _selectedRideId;
    if (rideId == null || _submittingAction) return;
    final isCancellation = action == 'cancel';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isCancellation ? 'إلغاء الرحلة مجانًا؟' : 'إنهاء الرحلة؟'),
        content: Text(isCancellation
            ? 'سيتم إلغاء الرحلة دون رسوم أو تسوية للأجرة، حتى إن كانت قد بدأت.'
            : 'سيتم تسجيل المبلغ النقدي المستلم بصفر، وتطبيق التسوية والمديونية حسب النظام.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isCancellation ? 'تأكيد الإلغاء' : 'تأكيد الإنهاء'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submittingAction = true;
      _error = null;
    });
    try {
      await _dio.post(
        '/api/admin/rides/$rideId/$action',
        options: _requestOptions,
      );
      if (!mounted) return;
      await _loadRides(reset: true);
      await _openRide(rideId);
      if (mounted) {
        _showMessage(isCancellation
            ? 'تم إلغاء الرحلة مجانًا'
            : 'تم إنهاء الرحلة وتسويتها');
      }
    } on DioException catch (error) {
      if (!mounted) return;
      if (_isUnauthorized(error)) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() => _error = _messageFrom(error, 'تعذر تنفيذ الإجراء'));
      }
    } finally {
      if (mounted) setState(() => _submittingAction = false);
    }
  }

  Future<void> _reverseSettlement() async {
    final rideId = _selectedRideId;
    final ride = _ride;
    if (rideId == null ||
        ride == null ||
        !widget.canReverseSettlement ||
        ride['canReverseSettlement'] != true ||
        _submittingAction) {
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReverseSettlementDialog(
        riderRefundAmount: ride['riderRefundAmount'],
      ),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() {
      _submittingAction = true;
      _error = null;
    });
    try {
      await _dio.post(
        '/api/admin/rides/$rideId/reverse-settlement',
        data: {'reason': reason.trim()},
        options: _requestOptions,
      );
      if (!mounted) return;
      await _loadRides(reset: true);
      await _openRide(rideId);
      if (mounted) _showMessage('تم عكس التسوية وحفظ القيود التعويضية');
    } on DioException catch (error) {
      if (!mounted) return;
      if (_isUnauthorized(error)) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() => _error = _messageFrom(error, 'تعذر عكس تسوية الرحلة'));
      }
    } finally {
      if (mounted) setState(() => _submittingAction = false);
    }
  }

  bool _isUnauthorized(DioException error) => error.response?.statusCode == 401;

  String _messageFrom(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['message'] is String
        ? data['message'] as String
        : fallback;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textAlign: TextAlign.center)),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'cancelled' => Colors.red.shade700,
        'completed' => Colors.green.shade700,
        _ => Colors.amber.shade800,
      };

  String _statusLabel(String status) => switch (status) {
        'requested' => 'بانتظار السائق',
        'accepted' => 'تم قبولها',
        'arriving' => 'السائق في الطريق',
        'in_progress' => 'جارية',
        'cancelled' => 'ملغاة',
        'completed' => 'مكتملة',
        _ => status,
      };

  String _displayValue(Object? value) {
    if (value == null || value.toString().isEmpty) return 'غير متوفر';
    if (value is DateTime) return _formatDate(value);
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null && value.toString().contains('-')) {
      return _formatDate(parsed);
    }
    return value.toString();
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final date = local.toString();
    return '${date.substring(0, 10)} ${date.substring(11, 16)}';
  }

  List<MapEntry<String, Object?>> _rideFields(Map<String, dynamic> ride) => [
        MapEntry('رقم الرحلة', ride['rideId']),
        MapEntry('الحالة', _statusLabel('${ride['status'] ?? ''}')),
        MapEntry('الراكب', ride['riderName']),
        MapEntry('هاتف الراكب', ride['riderPhone']),
        MapEntry('السائق', ride['driverName']),
        MapEntry('هاتف السائق', ride['driverPhone']),
        MapEntry('المركبة', ride['carModel']),
        MapEntry('اللون', ride['carColor']),
        MapEntry('لوحة المركبة', ride['licensePlate']),
        MapEntry('نقطة الانطلاق', ride['pickupAddress']),
        MapEntry('الوجهة', ride['dropoffAddress']),
        MapEntry('تاريخ الطلب', ride['createdAt']),
        MapEntry('تاريخ القبول', ride['acceptedAt']),
        MapEntry('تاريخ الوصول', ride['arrivedAt']),
        MapEntry('تاريخ البدء', ride['startedAt']),
        MapEntry('تاريخ الإكمال', ride['completedAt']),
        MapEntry('تاريخ الإلغاء', ride['cancelledAt']),
        MapEntry('الأجرة', ride['fare'] == null ? null : '${ride['fare']} ج.م'),
        MapEntry('المسافة',
            ride['distance'] == null ? null : '${ride['distance']} كم'),
        MapEntry('المدة',
            ride['duration'] == null ? null : '${ride['duration']} دقيقة'),
        MapEntry('طريقة الدفع', ride['paymentMethod']),
        MapEntry('حالة الدفع', ride['paymentStatus']),
        MapEntry('الكوبون', ride['couponCode']),
        MapEntry('خصم الكوبون', ride['couponDiscount']),
        MapEntry('المبلغ النقدي المستلم', ride['cashReceived']),
        MapEntry('تعديل محفظة الراكب', ride['riderWalletAdjustment']),
        MapEntry('العمولة', ride['commissionAmount']),
        MapEntry('صافي السائق', ride['driverNet']),
        MapEntry('سبب الإلغاء', ride['cancellationReason']),
        MapEntry('حالة عكس التسوية',
            ride['settlementReversedAt'] == null ? null : 'تم عكسها'),
        MapEntry('سبب عكس التسوية', ride['reversalReason']),
        MapEntry('مسؤول العكس', ride['reversedBy']),
        MapEntry('تاريخ عكس التسوية', ride['settlementReversedAt']),
      ];

  Widget _buildRideList() {
    if (_loading && _rides.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rides.isEmpty) {
      return _buildMessageState(_error!,
          onRetry: () => _loadRides(reset: true));
    }
    if (_rides.isEmpty) return _buildMessageState('لا توجد رحلات في هذا السجل');

    return RefreshIndicator(
      onRefresh: () => _loadRides(reset: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _rides.length + (_hasMore || _loading ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _rides.length) {
            return Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton.icon(
                      onPressed: () => _loadRides(reset: false),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('تحميل المزيد'),
                    ),
            );
          }
          final ride = _rides[index];
          final status = '${ride['status'] ?? ''}';
          final rideId = (ride['rideId'] as num?)?.toInt();
          final color = _statusColor(status);
          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: color.withValues(alpha: 0.65)),
            ),
            child: ListTile(
              leading: Icon(Icons.trip_origin, color: color),
              title: Text('رحلة #${rideId ?? '-'}'),
              subtitle: Text(
                '${ride['riderName'] ?? 'راكب غير محدد'} · ${_statusLabel(status)}',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: rideId == null ? null : () => _openRide(rideId),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRideFilters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final searchWidth =
                isWide ? constraints.maxWidth - 232 : constraints.maxWidth;
            final periodWidth = isWide ? 220.0 : constraints.maxWidth;
            final range = _period == 'custom' ? _customRange : null;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: searchWidth,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText:
                          'رقم الرحلة أو السائق أو الاسم أو الهاتف أو اللوحة',
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                _searchChanged('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: periodWidth,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'فترة الرحلات',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _period,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('كل الفترات')),
                          DropdownMenuItem(
                              value: 'today', child: Text('اليوم')),
                          DropdownMenuItem(
                              value: 'yesterday', child: Text('أمس')),
                          DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                          DropdownMenuItem(value: 'month', child: Text('شهر')),
                          DropdownMenuItem(
                              value: 'custom', child: Text('مدة محددة')),
                        ],
                        onChanged: (period) {
                          if (period != null) {
                            unawaited(_selectPeriod(period));
                          }
                        },
                      ),
                    ),
                  ),
                ),
                if (range != null)
                  SizedBox(
                    width: constraints.maxWidth,
                    child: Text(
                      '${_dateLabel(range.start)} - ${_dateLabel(range.end)}',
                      textAlign: TextAlign.start,
                    ),
                  ),
              ],
            );
          },
        ),
      );

  Widget _buildMessageState(String message, {VoidCallback? onRetry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildDetails() {
    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }
    final ride = _ride;
    if (ride == null) {
      return _buildMessageState(
        _error ?? 'تعذر تحميل تفاصيل الرحلة',
        onRetry:
            _selectedRideId == null ? null : () => _openRide(_selectedRideId!),
      );
    }
    final status = '${ride['status'] ?? ''}';
    final canAct = _activeStatuses.contains(status);
    final canReverse = widget.canReverseSettlement &&
        ['cancelled', 'completed'].contains(status) &&
        ride['canReverseSettlement'] == true;
    final fields = _rideFields(ride)
        .where(
            (field) => field.value != null && field.value.toString().isNotEmpty)
        .toList();
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('بيانات الرحلة'),
              ...fields.map((field) => ListTile(
                    dense: true,
                    title: Text(field.key),
                    subtitle: Text(_displayValue(field.value)),
                    leading: field.key == 'الحالة'
                        ? Icon(Icons.circle,
                            size: 13, color: _statusColor(status))
                        : null,
                  )),
            ],
          ),
        ),
        if (canAct || canReverse)
          Material(
            elevation: 4,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (canReverse)
                          OutlinedButton.icon(
                            onPressed:
                                _submittingAction ? null : _reverseSettlement,
                            icon: const Icon(Icons.undo),
                            label: const Text('عكس التسوية'),
                          ),
                        if (canAct) ...[
                          OutlinedButton.icon(
                            onPressed: _submittingAction
                                ? null
                                : () => _performAction('cancel'),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('إلغاء الرحلة مجانًا'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _submittingAction
                                ? null
                                : () => _performAction('complete'),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('إنهاء الرحلة'),
                          ),
                        ],
                      ],
                    ),
                    if (_submittingAction) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (_selectedRideId != null)
                      IconButton(
                        tooltip: 'العودة إلى السجل',
                        onPressed:
                            _submittingAction ? null : _handleDashboardBack,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    Text(
                      _selectedRideId == null
                          ? 'سجل الرحلات'
                          : 'تفاصيل الرحلة #$_selectedRideId',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              if (_selectedRideId == null) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<String>(
                    segments: _groups.entries
                        .map((entry) => ButtonSegment<String>(
                              value: entry.key,
                              label: Text(entry.value),
                            ))
                        .toList(),
                    selected: {_group},
                    onSelectionChanged: (selection) =>
                        _selectGroup(selection.first),
                  ),
                ),
                _buildRideFilters(),
                Expanded(child: _buildRideList()),
              ] else
                Expanded(child: _buildDetails()),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReverseSettlementDialog extends StatefulWidget {
  const _ReverseSettlementDialog({required this.riderRefundAmount});

  final Object? riderRefundAmount;

  @override
  State<_ReverseSettlementDialog> createState() =>
      _ReverseSettlementDialogState();
}

class _ReverseSettlementDialogState extends State<_ReverseSettlementDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('عكس تسوية الرحلة'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سيعاد إلى محفظة الراكب ${widget.riderRefundAmount ?? 0} ج.م، '
              'وتُصحح الحركات المرتبطة دون حذف الرحلة أو سجلها.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'سبب العكس',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: _reasonController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      _reasonController.text.trim(),
                    ),
            child: const Text('تأكيد العكس'),
          ),
        ],
      );
}
