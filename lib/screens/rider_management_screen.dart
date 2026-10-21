import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../core/admin_api_client.dart';
import 'coupon_management_screen.dart';
import '../widgets/dashboard_navigation.dart';
import '../widgets/support_history_tab.dart';

class RiderManagementScreen extends StatefulWidget {
  const RiderManagementScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<RiderManagementScreen> createState() => _RiderManagementScreenState();
}

class _RiderManagementScreenState extends State<RiderManagementScreen> {
  late final Dio _dio;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;
  DashboardBackHandler? _dashboardBackHandler;
  List<Map<String, dynamic>> _riders = [];
  Map<String, dynamic>? _details;
  String _status = 'all';
  String? _error;
  bool _loading = false;
  bool _loadingDetails = false;
  bool _hasMore = false;
  int _page = 1;
  int _requestId = 0;
  int _detailRequestId = 0;
  String _couponPeriod = 'all';
  DateTimeRange? _couponCustomRange;
  String _rideHistoryPeriod = 'week';
  DateTimeRange? _rideHistoryCustomRange;
  String _settlementsPeriod = 'week';
  DateTimeRange? _settlementsCustomRange;
  final Set<String> _settlementCategories = {};
  String _activityPeriod = 'week';
  DateTimeRange? _activityCustomRange;
  final Set<String> _activityCategories = {};
  String _ratingsPeriod = 'week';
  DateTimeRange? _ratingsCustomRange;

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
    unawaited(_loadRiders(reset: true));
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
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadRiders(reset: true));
    });
  }

  Future<void> _loadRiders({required bool reset}) async {
    final requestId = ++_requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/riders',
        queryParameters: {
          'search': _searchController.text.trim(),
          'status': _status,
          'page': page,
          'limit': 50,
        },
        options: _requestOptions,
      );
      if (!mounted || requestId != _requestId) return;
      final data = response.data ?? const {};
      final rows = data['riders'];
      final riders = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      final total = (data['total'] as num?)?.toInt() ?? riders.length;
      setState(() {
        _riders = reset ? riders : [..._riders, ...riders];
        _page = page;
        _hasMore = _riders.length < total;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() => _error = _messageFrom(error, 'تعذر تحميل قائمة الركاب'));
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openRider(Map<String, dynamic> rider) async {
    final riderId = rider['riderId'];
    if (riderId == null) return;
    final requestId = ++_detailRequestId;
    setState(() {
      _details = null;
      _loadingDetails = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/riders/$riderId',
        options: _requestOptions,
      );
      if (!mounted || requestId != _detailRequestId) return;
      setState(() {
        _details = response.data;
        _loadingDetails = false;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _detailRequestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() {
          _error = _messageFrom(error, 'تعذر تحميل ملف الراكب');
          _loadingDetails = false;
        });
      }
    }
  }

  bool _handleDashboardBack() {
    if (_details == null && !_loadingDetails) return false;
    _detailRequestId++;
    setState(() {
      _details = null;
      _loadingDetails = false;
      _error = null;
    });
    return true;
  }

  Future<void> _editRider() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _RiderEditDialog(profile: Map<String, dynamic>.from(profile)),
    );
    if (changes == null) return;
    try {
      await _dio.patch('/api/admin/riders/${profile['riderId']}',
          data: changes, options: _requestOptions);
      await _openRider({'riderId': profile['riderId']});
      if (mounted) _showMessage('تم تحديث بيانات الراكب');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تعديل بيانات الراكب');
    }
  }

  Future<void> _toggleStatus() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final isActive = profile['accountStatus'] == 'active' &&
        (profile['isActive'] == true || profile['isActive'] == 1);
    final nextStatus = isActive ? 'suspended' : 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'إيقاف حساب الراكب؟' : 'تفعيل حساب الراكب؟'),
        content: const Text('ستبقى الرحلات والمعاملات والسجلات محفوظة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _dio.patch('/api/admin/riders/${profile['riderId']}/status',
          data: {'status': nextStatus}, options: _requestOptions);
      await _openRider({'riderId': profile['riderId']});
      await _loadRiders(reset: true);
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحديث حالة الحساب');
    }
  }

  bool _couponBelongsToRider(
    Map<String, dynamic> coupon,
    dynamic riderId,
  ) =>
      coupon['riderId']?.toString() == riderId?.toString();

  Future<void> _editRiderCoupon(
    Map<String, dynamic> coupon,
    dynamic riderId,
  ) async {
    if (!_couponBelongsToRider(coupon, riderId)) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => CouponFormDialog(
        client: _dio,
        adminToken: widget.adminToken,
        coupon: coupon,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (values == null || !mounted) return;
    try {
      await _dio.patch('/api/admin/coupons/${coupon['couponId']}',
          data: values, options: _requestOptions);
      await _openRider({'riderId': riderId});
      if (mounted) _showMessage('تم تحديث الكوبون');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحديث الكوبون');
    }
  }

  Future<void> _toggleRiderCoupon(
    Map<String, dynamic> coupon,
    dynamic riderId,
  ) async {
    if (!_couponBelongsToRider(coupon, riderId)) return;
    final isActive = coupon['isActive'] == true ||
        coupon['isActive'] == 1 ||
        coupon['isActive'] == '1';
    try {
      await _dio.patch(
        '/api/admin/coupons/${coupon['couponId']}',
        data: {'isActive': !isActive},
        options: _requestOptions,
      );
      await _openRider({'riderId': riderId});
      if (mounted) {
        _showMessage(isActive ? 'تم تعطيل الكوبون' : 'تم تفعيل الكوبون');
      }
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تغيير حالة الكوبون');
    }
  }

  Future<void> _deleteRiderCoupon(
    Map<String, dynamic> coupon,
    dynamic riderId,
  ) async {
    if (!_couponBelongsToRider(coupon, riderId)) return;
    final reservationCount =
        int.tryParse(coupon['reservationCount']?.toString() ?? '') ?? 0;
    final redemptionCount =
        int.tryParse(coupon['redemptionCount']?.toString() ?? '') ?? 0;
    if (reservationCount > 0 || redemptionCount > 0) {
      _showMessage('لا يمكن حذف كوبون له حجوزات أو استخدامات؛ يمكنك تعطيله');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الكوبون؟'),
        content: Text('سيتم حذف الكوبون ${coupon['code']} نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _dio.delete('/api/admin/coupons/${coupon['couponId']}',
          options: _requestOptions);
      await _openRider({'riderId': riderId});
      if (mounted) _showMessage('تم حذف الكوبون');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر حذف الكوبون');
    }
  }

  Future<void> _adjustWallet() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final adjustment = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _WalletAdjustmentDialog(),
    );
    if (adjustment == null) return;
    try {
      await _dio.post(
        '/api/admin/riders/${profile['riderId']}/wallet-adjustments',
        data: adjustment,
        options: _requestOptions,
      );
      await _openRider({'riderId': profile['riderId']});
      if (mounted) _showMessage('تم تسجيل حركة المحفظة');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تعديل المحفظة');
    }
  }

  Future<void> _editRiderDebtLimit(Map<String, dynamic> profile) async {
    final initialValue = profile['riderDebtLimit'] ??
        profile['effectiveRiderDebtLimit'] ??
        '-30.00';
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RiderDebtLimitDialog(initialValue: '$initialValue'),
    );
    if (values == null) return;
    try {
      await _dio.patch(
        '/api/admin/riders/${profile['riderId']}',
        data: values,
        options: _requestOptions,
      );
      await _openRider({'riderId': profile['riderId']});
      if (mounted) _showMessage('تم تحديث حد مديونية الراكب');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحديث حد المديونية');
    }
  }

  void _handleRequestError(DioException error, String fallback) {
    if (error.response?.statusCode == 401) {
      widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
    } else {
      _showMessage(_messageFrom(error, fallback));
    }
  }

  String _messageFrom(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['message'] is String
        ? data['message'] as String
        : fallback;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: _details == null && !_loadingDetails
                  ? _buildRiderList()
                  : _buildRiderProfile(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRiderList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('إدارة الركاب',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchController,
            onChanged: _searchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث برقم الراكب أو الاسم أو الهاتف أو رقم الرحلة',
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        _searchController.clear();
                        _searchChanged('');
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('الكل')),
              ButtonSegment(value: 'active', label: Text('نشط')),
              ButtonSegment(value: 'inactive', label: Text('غير نشط')),
              ButtonSegment(value: 'suspended', label: Text('موقوف')),
            ],
            selected: {_status},
            onSelectionChanged: (selection) {
              setState(() => _status = selection.first);
              unawaited(_loadRiders(reset: true));
            },
          ),
        ),
        if (_error != null) _errorBanner(_error!),
        Expanded(
          child: _loading && _riders.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _riders.isEmpty
                  ? _emptyState('لا يوجد ركاب مطابقون للبحث')
                  : RefreshIndicator(
                      onRefresh: () => _loadRiders(reset: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: _riders.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _riders.length) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: _loading
                                    ? null
                                    : () => _loadRiders(reset: false),
                                icon: const Icon(Icons.expand_more),
                                label: const Text('تحميل المزيد'),
                              ),
                            );
                          }
                          return _riderTile(_riders[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _riderTile(Map<String, dynamic> rider) {
    final active = rider['accountStatus'] == 'active' &&
        (rider['isActive'] == true || rider['isActive'] == 1);
    final name = rider['fullName']?.toString().trim();
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: rider['profileImageUrl'] is String
            ? NetworkImage(rider['profileImageUrl'] as String)
            : null,
        child: rider['profileImageUrl'] is String
            ? null
            : const Icon(Icons.person_outline),
      ),
      title:
          Text(name?.isNotEmpty == true ? name! : 'راكب ${rider['riderId']}'),
      subtitle: Text(
        '${rider['phone'] ?? 'بدون هاتف'}  ·  ${rider['ridesCount'] ?? 0} رحلة\n'
        'الرصيد: ${rider['balance'] ?? '0.00'}',
        maxLines: 2,
      ),
      isThreeLine: true,
      trailing: _statusLabel(
        active
            ? 'نشط'
            : rider['accountStatus'] == 'suspended'
                ? 'موقوف'
                : 'غير نشط',
        active,
      ),
      onTap: () => _openRider(rider),
    );
  }

  Future<void> _selectRatingsPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _ratingsCustomRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة التقييمات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _ratingsPeriod = period;
        _ratingsCustomRange = selectedRange;
      });
      return;
    }
    setState(() => _ratingsPeriod = period);
  }

  DateTimeRange? _ratingsRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_ratingsPeriod) {
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
      case 'month':
        final monthStart = DateTime(now.year, now.month);
        return DateTimeRange(
            start: monthStart, end: DateTime(now.year, now.month + 1));
      case 'custom':
        final customRange = _ratingsCustomRange;
        if (customRange == null) return null;
        final start = DateTime(customRange.start.year, customRange.start.month,
            customRange.start.day);
        final end = DateTime(customRange.end.year, customRange.end.month,
                customRange.end.day)
            .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  Future<void> _selectRideHistoryPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _rideHistoryCustomRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة الرحلات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _rideHistoryPeriod = period;
        _rideHistoryCustomRange = selectedRange;
      });
      return;
    }
    setState(() => _rideHistoryPeriod = period);
  }

  Future<void> _selectCouponPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _couponCustomRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة الكوبونات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _couponPeriod = period;
        _couponCustomRange = selectedRange;
      });
      return;
    }
    setState(() => _couponPeriod = period);
  }

  DateTimeRange? _couponRange() {
    final now = DateTime.now();
    switch (_couponPeriod) {
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1),
        );
      case 'custom':
        final selectedRange = _couponCustomRange;
        if (selectedRange == null) return null;
        return DateTimeRange(
          start: DateTime(selectedRange.start.year, selectedRange.start.month,
              selectedRange.start.day),
          end: DateTime(selectedRange.end.year, selectedRange.end.month,
                  selectedRange.end.day)
              .add(const Duration(days: 1)),
        );
      default:
        return null;
    }
  }

  DateTime? _couponDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  bool _couponDateMatches(DateTimeRange? range, dynamic value) {
    if (range == null) return true;
    final date = _couponDate(value);
    return date != null &&
        !date.isBefore(range.start) &&
        date.isBefore(range.end);
  }

  bool _couponValidityOverlaps(
    Map<String, dynamic> coupon,
    DateTimeRange? range,
  ) {
    if (range == null) return true;
    final startsAt = _couponDate(coupon['startsAt']);
    final expiresAt = _couponDate(coupon['expiresAt']);
    return (startsAt == null || startsAt.isBefore(range.end)) &&
        (expiresAt == null || !expiresAt.isBefore(range.start));
  }

  DateTimeRange? _rideHistoryRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_rideHistoryPeriod) {
      case 'all':
        return null;
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
      case 'month':
        final monthStart = DateTime(now.year, now.month);
        return DateTimeRange(
            start: monthStart, end: DateTime(now.year, now.month + 1));
      case 'custom':
        final customRange = _rideHistoryCustomRange;
        if (customRange == null) return null;
        final start = DateTime(customRange.start.year, customRange.start.month,
            customRange.start.day);
        final end = DateTime(customRange.end.year, customRange.end.month,
                customRange.end.day)
            .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  DateTime? _rideHistoryDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  DateTime? _ratingDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  Future<void> _selectFinancialActivityPeriod(
    String period, {
    required bool activity,
  }) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final currentRange =
          activity ? _activityCustomRange : _settlementsCustomRange;
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            currentRange ?? DateTimeRange(start: today, end: today),
        helpText: activity ? 'اختر مدة النشاط' : 'اختر مدة التسويات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        if (activity) {
          _activityPeriod = period;
          _activityCustomRange = selectedRange;
        } else {
          _settlementsPeriod = period;
          _settlementsCustomRange = selectedRange;
        }
      });
      return;
    }
    setState(() {
      if (activity) {
        _activityPeriod = period;
      } else {
        _settlementsPeriod = period;
      }
    });
  }

  DateTimeRange? _recordPeriodRange(
    String period,
    DateTimeRange? customRange,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'day':
        return DateTimeRange(
            start: today, end: today.add(const Duration(days: 1)));
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
      case 'month':
        return DateTimeRange(
            start: DateTime(now.year, now.month),
            end: DateTime(now.year, now.month + 1));
      case 'custom':
        if (customRange == null) return null;
        final start = DateTime(customRange.start.year, customRange.start.month,
            customRange.start.day);
        final end = DateTime(customRange.end.year, customRange.end.month,
                customRange.end.day)
            .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  DateTime? _dateFromRecord(
    Map<String, dynamic> record,
    List<String> dateKeys,
  ) {
    for (final key in dateKeys) {
      final value = record[key];
      if (key == 'capturedAtMs') {
        final milliseconds = value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '');
        if (milliseconds != null) {
          return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
              .toLocal();
        }
      }
      final date = _rideHistoryDate(value);
      if (date != null) return date;
    }
    return null;
  }

  Widget _recordPeriodFilter({
    required String period,
    required DateTimeRange? customRange,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: period,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: const [
              DropdownMenuItem(value: 'day', child: Text('يوم')),
              DropdownMenuItem(value: 'week', child: Text('أسبوع')),
              DropdownMenuItem(value: 'month', child: Text('شهر')),
              DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
              DropdownMenuItem(value: 'all', child: Text('كل الفترات')),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
          if (period == 'custom' && customRange != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${intl.DateFormat('y/MM/dd').format(customRange.start)}'
                ' - ${intl.DateFormat('y/MM/dd').format(customRange.end)}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupCategoryFilter({
    required Map<String, String> categories,
    required Set<String> selectedCategories,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('كل التصنيفات'),
                selected: selectedCategories.isEmpty,
                onSelected: (_) => onChanged(null),
              ),
              for (final entry in categories.entries) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(entry.value),
                  selected: selectedCategories.contains(entry.key),
                  onSelected: (_) => onChanged(entry.key),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildRiderProfile() {
    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }
    final details = _details;
    final profile = details?['profile'];
    if (details == null || profile is! Map) {
      return Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'العودة للقائمة',
              onPressed: _handleDashboardBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          if (_error != null)
            _errorBanner(_error!)
          else
            _emptyState('تعذر تحميل بيانات الراكب'),
        ],
      );
    }
    final profileMap = Map<String, dynamic>.from(profile);
    final active = profileMap['accountStatus'] == 'active' &&
        (profileMap['isActive'] == true || profileMap['isActive'] == 1);
    final wallet = details['wallet'] is Map
        ? Map<String, dynamic>.from(details['wallet'] as Map)
        : <String, dynamic>{};
    final financialRecords = details['financialRecords'] is Map
        ? Map<String, dynamic>.from(details['financialRecords'] as Map)
        : <String, dynamic>{};
    final coupons = details['coupons'] is Map
        ? Map<String, dynamic>.from(details['coupons'] as Map)
        : <String, dynamic>{};

    return DefaultTabController(
      length: 9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'العودة للقائمة',
                  onPressed: _handleDashboardBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    profileMap['fullName']?.toString().trim().isNotEmpty == true
                        ? profileMap['fullName'].toString()
                        : 'ملف الراكب',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل البيانات',
                  onPressed: _editRider,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: active ? 'إيقاف الحساب' : 'تفعيل الحساب',
                  onPressed: _toggleStatus,
                  icon: Icon(active
                      ? Icons.block_outlined
                      : Icons.check_circle_outline),
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'الحساب'),
              Tab(text: 'الرحلات'),
              Tab(text: 'المحفظة'),
              Tab(text: 'التسويات'),
              Tab(text: 'التقييمات'),
              Tab(text: 'الكوبونات'),
              Tab(text: 'النشاط'),
              Tab(text: 'الشكاوى'),
              Tab(text: 'محادثات خدمة العملاء'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _accountTab(profileMap),
                _rideHistoryTab(
                  _records(details['rides']),
                  _records(details['chatMessages']),
                ),
                _walletTab(wallet, profileMap),
                _settlementsTab(financialRecords),
                _ratingsTab(
                  _records(details['ratings'])
                      .where((rating) =>
                          rating['targetUserId']?.toString() ==
                          profileMap['riderId']?.toString())
                      .toList(),
                  profileMap,
                ),
                _couponTab(coupons, profileMap),
                _activityTab(details),
                SupportHistoryTab(
                  client: _dio,
                  adminToken: widget.adminToken,
                  userId:
                      int.tryParse(profileMap['riderId']?.toString() ?? '') ??
                          0,
                  userRole: 'rider',
                  ticketsMode: true,
                  onSessionExpired: widget.onSessionExpired,
                ),
                SupportHistoryTab(
                  client: _dio,
                  adminToken: widget.adminToken,
                  userId:
                      int.tryParse(profileMap['riderId']?.toString() ?? '') ??
                          0,
                  userRole: 'rider',
                  ticketsMode: false,
                  onSessionExpired: widget.onSessionExpired,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _couponTab(
    Map<String, dynamic> coupons,
    Map<String, dynamic> profile,
  ) {
    final riderId = profile['riderId'];
    final range = _couponRange();
    final assigned = _records(coupons['assigned'])
        .where((coupon) => _couponBelongsToRider(coupon, riderId))
        .where((coupon) => _couponValidityOverlaps(coupon, range))
        .toList();
    final activeCoupons = assigned
        .where((coupon) => _riderCouponStatus(coupon) == 'مفعّل')
        .toList();
    final scheduledOrExpiredCoupons = assigned
        .where((coupon) =>
            _couponIsActive(coupon['isActive']) &&
            _riderCouponStatus(coupon) != 'مفعّل')
        .toList();
    final disabledCoupons = assigned
        .where((coupon) => !_couponIsActive(coupon['isActive']))
        .toList();
    final redemptions = _records(coupons['redemptions'])
        .where((record) => _couponDateMatches(range, record['redeemedAt']))
        .toList();
    final reservations = _records(coupons['reservations'])
        .where((record) => _couponDateMatches(range, record['reservedAt']))
        .toList();
    final hasRecords = activeCoupons.isNotEmpty ||
        scheduledOrExpiredCoupons.isNotEmpty ||
        disabledCoupons.isNotEmpty ||
        redemptions.isNotEmpty ||
        reservations.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'فترة الكوبونات',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _couponPeriod,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('الكل')),
                  DropdownMenuItem(value: 'month', child: Text('شهر')),
                  DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
                ],
                onChanged: (period) {
                  if (period != null) unawaited(_selectCouponPeriod(period));
                },
              ),
            ),
          ),
        ),
        if (_couponPeriod == 'custom' && _couponCustomRange != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_couponCustomRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_couponCustomRange!.end)}',
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: !hasRecords
              ? _emptyState(range == null
                  ? 'لا توجد كوبونات مرتبطة بهذا الراكب'
                  : 'لا توجد كوبونات ضمن الفترة المحددة')
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    if (activeCoupons.isNotEmpty) ...[
                      _couponSectionTitle('الكوبونات المفعّلة'),
                      ...activeCoupons.map(
                        (coupon) => _riderCouponTile(coupon, riderId),
                      ),
                    ],
                    if (scheduledOrExpiredCoupons.isNotEmpty) ...[
                      _couponSectionTitle('الكوبونات القادمة أو المنتهية'),
                      ...scheduledOrExpiredCoupons.map(
                        (coupon) => _riderCouponTile(coupon, riderId),
                      ),
                    ],
                    if (disabledCoupons.isNotEmpty) ...[
                      _couponSectionTitle('الكوبونات المعطّلة'),
                      ...disabledCoupons.map(
                        (coupon) => _riderCouponTile(coupon, riderId),
                      ),
                    ],
                    if (redemptions.isNotEmpty) ...[
                      _couponSectionTitle('سجل الاستخدام'),
                      ...redemptions.map(
                        (record) => _riderRedemptionTile(record, riderId),
                      ),
                    ],
                    if (reservations.isNotEmpty) ...[
                      _couponSectionTitle('الحجوزات'),
                      ...reservations.map(_riderReservationTile),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _couponSectionTitle(String title) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _riderCouponTile(Map<String, dynamic> coupon, dynamic riderId) {
    final startsAt = _couponDate(coupon['startsAt']);
    final expiresAt = _couponDate(coupon['expiresAt']);
    final status = _riderCouponStatus(coupon);
    return Card(
      key: ValueKey('rider-coupon-${coupon['couponId']}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${coupon['code']}',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Chip(
                  label: Text(status),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
              ],
            ),
            Text('الخصم: ${coupon['discountPercent']}%'),
            Text(
              'الصلاحية: ${startsAt == null ? 'غير محدد' : intl.DateFormat('y/MM/dd').format(startsAt)}'
              ' - ${expiresAt == null ? 'غير محدد' : intl.DateFormat('y/MM/dd').format(expiresAt)}',
            ),
            Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'تعديل الكوبون',
                  onPressed: () => _editRiderCoupon(coupon, riderId),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: _couponIsActive(coupon['isActive'])
                      ? 'تعطيل الكوبون'
                      : 'تفعيل الكوبون',
                  onPressed: () => _toggleRiderCoupon(coupon, riderId),
                  icon: Icon(_couponIsActive(coupon['isActive'])
                      ? Icons.block_outlined
                      : Icons.check_circle_outline),
                ),
                IconButton(
                  tooltip: 'حذف الكوبون',
                  onPressed: () => _deleteRiderCoupon(coupon, riderId),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _riderRedemptionTile(
    Map<String, dynamic> redemption,
    dynamic riderId,
  ) {
    final redeemedAt = _couponDate(redemption['redeemedAt']);
    final isOwnerCoupon =
        redemption['couponRiderId']?.toString() == riderId?.toString();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      child: ListTile(
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${redemption['couponCode'] ?? 'كوبون'}'),
            Chip(
              label: Text(_riderCouponStatus(redemption)),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
          ],
        ),
        subtitle: Text(
          '${isOwnerCoupon ? 'كوبون خاص بالراكب' : 'كوبون عام'}'
          ' · رحلة #${redemption['rideId'] ?? 'غير محددة'}\n'
          'الاستخدام: ${redeemedAt == null ? 'غير محدد' : intl.DateFormat('y/MM/dd HH:mm').format(redeemedAt)}'
          '${redemption['reversedAt'] == null ? '' : ' · استخدام معكوس'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _riderReservationTile(Map<String, dynamic> reservation) {
    final reservedAt = _couponDate(reservation['reservedAt']);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      child: ListTile(
        title: Text('${reservation['couponCode'] ?? 'كوبون'}'),
        subtitle: Text(
          'رحلة #${reservation['rideId'] ?? 'غير محددة'}'
          ' · الحجز: ${reservedAt == null ? 'غير محدد' : intl.DateFormat('y/MM/dd HH:mm').format(reservedAt)}',
        ),
      ),
    );
  }

  bool _couponIsActive(dynamic value) =>
      value == true || value == 1 || value == '1';

  String _riderCouponStatus(Map<String, dynamic> coupon) {
    if (!_couponIsActive(coupon['isActive'])) return 'معطّل';
    final now = DateTime.now();
    final startsAt = _couponDate(coupon['startsAt']);
    final expiresAt = _couponDate(coupon['expiresAt']);
    if (startsAt != null && startsAt.isAfter(now)) return 'قادم';
    if (expiresAt != null && !expiresAt.isAfter(now)) return 'منتهي';
    return 'مفعّل';
  }

  Widget _ratingsTab(
    List<Map<String, dynamic>> ratings,
    Map<String, dynamic> profile,
  ) {
    final ratingRange = _ratingsRange();
    final visibleRatings = ratingRange == null
        ? <Map<String, dynamic>>[]
        : ratings.where((rating) {
            final date = _ratingDate(rating['createdAt']);
            return date != null &&
                !date.isBefore(ratingRange.start) &&
                date.isBefore(ratingRange.end);
          }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _recordFields({
          'rating': profile['rating'],
          'reputationPoints': profile['reputationPoints'],
          'receivedRatingsCount': ratings.length,
        }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _ratingsPeriod,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'فترة التقييمات'),
          items: const [
            DropdownMenuItem(value: 'week', child: Text('أسبوع')),
            DropdownMenuItem(value: 'month', child: Text('شهر')),
            DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
          ],
          onChanged: (period) {
            if (period != null) unawaited(_selectRatingsPeriod(period));
          },
        ),
        if (_ratingsPeriod == 'custom' && _ratingsCustomRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_ratingsCustomRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_ratingsCustomRange!.end)}',
            ),
          ),
        const SizedBox(height: 12),
        Text('سجل التقييمات', style: Theme.of(context).textTheme.titleMedium),
        if (visibleRatings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('لا توجد تقييمات ضمن الفترة المحددة')),
          )
        else
          ...visibleRatings.map(_recordTile),
      ],
    );
  }

  Widget _walletTab(
    Map<String, dynamic> wallet,
    Map<String, dynamic> profile,
  ) {
    final transactions = _records(wallet['transactions']);
    final debtLimitOverride = profile['riderDebtLimit'];
    final effectiveDebtLimit = profile['effectiveRiderDebtLimit'] ?? '-30.00';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _walletSummary(
                  title: 'الرصيد الحالي',
                  value: '${wallet['balance'] ?? '0.00'} ج.م',
                  tooltip: 'تعديل الرصيد',
                  icon: Icons.account_balance_wallet_outlined,
                  onPressed: _adjustWallet,
                  filled: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _walletSummary(
                  title: 'حد الدين',
                  value: debtLimitOverride == null
                      ? 'الحد العام: $effectiveDebtLimit ج.م'
                      : 'حد مخصص: $effectiveDebtLimit ج.م',
                  tooltip: 'تعديل حد الدين',
                  icon: Icons.edit_outlined,
                  onPressed: () => _editRiderDebtLimit(profile),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
            child:
                _recordList(transactions, emptyMessage: 'لا توجد حركات محفظة')),
      ],
    );
  }

  Widget _walletSummary({
    required String title,
    required String value,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, maxLines: 1),
              ),
            ],
          ),
        ),
        if (filled)
          IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
          )
        else
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
      ],
    );
  }

  Widget _accountTab(Map<String, dynamic> profile) {
    final imageUrl = profile['profileImageUrl']?.toString();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundImage: imageUrl == null || imageUrl.isEmpty
                ? null
                : NetworkImage(imageUrl),
            child: imageUrl == null || imageUrl.isEmpty
                ? const Icon(Icons.person_outline, size: 40)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _recordFields(profile),
      ],
    );
  }

  Widget _activityTab(Map<String, dynamic> details) {
    final sections = <String, List<dynamic>>{
      'الإشعارات': _records(details['notifications']),
      'عروض السائقين': _records(details['offers']),
      'محادثات الرحلات': _records(details['chatMessages']),
      'سياسات الإلغاء': _records(details['cancellationPolicies']),
      'أجهزة الإشعارات': _records(details['devices']),
      'مسارات الموقع': _records(details['locationPoints']),
    };
    final location = details['location'];
    if (location is Map) {
      sections['الموقع الحالي'] = [Map<String, dynamic>.from(location)];
    }
    return Column(
      children: [
        _recordPeriodFilter(
          period: _activityPeriod,
          customRange: _activityCustomRange,
          label: 'فترة النشاط',
          onChanged: (period) => unawaited(_selectFinancialActivityPeriod(
            period,
            activity: true,
          )),
        ),
        _groupCategoryFilter(
          categories: {for (final key in sections.keys) key: key},
          selectedCategories: _activityCategories,
          onChanged: (category) => setState(() {
            if (category == null) {
              _activityCategories.clear();
            } else if (_activityCategories.contains(category)) {
              _activityCategories.remove(category);
            } else {
              _activityCategories.add(category);
            }
          }),
        ),
        Expanded(
          child: _groupedRecords(
            sections,
            period: _activityPeriod,
            range: _recordPeriodRange(_activityPeriod, _activityCustomRange),
            dateForRecord: _activityRecordDate,
            keepUndated: true,
            selectedCategories: _activityCategories,
          ),
        ),
      ],
    );
  }

  Widget _settlementsTab(Map<String, dynamic> financialRecords) {
    return Column(
      children: [
        _recordPeriodFilter(
          period: _settlementsPeriod,
          customRange: _settlementsCustomRange,
          label: 'فترة التسويات',
          onChanged: (period) => unawaited(_selectFinancialActivityPeriod(
            period,
            activity: false,
          )),
        ),
        _groupCategoryFilter(
          categories: const {
            'shortfalls': 'عجوزات الرحلات',
            'shortfallRecoveries': 'استردادات العجوزات',
            'cancellationFees': 'تسويات رسوم الإلغاء',
            'cancellationFeeRecoveries': 'تحصيل رسوم الإلغاء',
            'reversals': 'عكس التسوية',
            'ledgerEntries': 'دفتر عمولات ورسوم التطبيق',
          },
          selectedCategories: _settlementCategories,
          onChanged: (category) => setState(() {
            if (category == null) {
              _settlementCategories.clear();
            } else if (_settlementCategories.contains(category)) {
              _settlementCategories.remove(category);
            } else {
              _settlementCategories.add(category);
            }
          }),
        ),
        Expanded(
          child: _groupedRecords(
            financialRecords,
            period: _settlementsPeriod,
            range:
                _recordPeriodRange(_settlementsPeriod, _settlementsCustomRange),
            dateForRecord: _settlementRecordDate,
            keepUndated: false,
            selectedCategories: _settlementCategories,
          ),
        ),
      ],
    );
  }

  DateTime? _settlementRecordDate(
    String group,
    Map<String, dynamic> record,
  ) =>
      _dateFromRecord(record, const [
        'createdAt',
        'settledAt',
        'reversedAt',
        'recoveredAt',
        'updatedAt',
      ]);

  DateTime? _activityRecordDate(
    String group,
    Map<String, dynamic> record,
  ) {
    final keys = switch (group) {
      'عروض السائقين' => const ['offeredAt', 'respondedAt', 'expiresAt'],
      'سياسات الإلغاء' => const [
          'approachCheckedAt',
          'approachStartLocationAt',
          'initialEtaArrivalAt',
        ],
      'أجهزة الإشعارات' => const ['createdAt', 'updatedAt'],
      'مسارات الموقع' => const ['receivedAt', 'capturedAtMs'],
      'الموقع الحالي' => const ['capturedAt', 'updatedAt'],
      _ => const ['createdAt', 'deliveredAt', 'readAt', 'updatedAt'],
    };
    return _dateFromRecord(record, keys);
  }

  Widget _groupedRecords(
    Map<String, dynamic> groups, {
    required String period,
    required DateTimeRange? range,
    required DateTime? Function(String, Map<String, dynamic>) dateForRecord,
    required bool keepUndated,
    required Set<String> selectedCategories,
  }) {
    final entries = groups.entries
        .where((entry) =>
            selectedCategories.isEmpty ||
            selectedCategories.contains(entry.key))
        .map((entry) {
          final records = _records(entry.value).where((record) {
            if (period == 'all') return true;
            final date = dateForRecord(entry.key, record);
            if (date == null) return keepUndated;
            return range != null &&
                !date.isBefore(range.start) &&
                date.isBefore(range.end);
          }).toList();
          return MapEntry(entry.key, records);
        })
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    if (entries.isEmpty) return _emptyState('لا توجد سجلات ضمن الفترة المحددة');
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final entry in entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child:
                Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
          ),
          ..._recordTiles(entry.value),
        ],
      ],
    );
  }

  Widget _recordList(List<Map<String, dynamic>> records,
      {String emptyMessage = 'لا توجد سجلات'}) {
    if (records.isEmpty) return _emptyState(emptyMessage);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) => _recordTile(records[index]),
    );
  }

  Widget _rideHistoryTab(
    List<Map<String, dynamic>> rides,
    List<Map<String, dynamic>> chatMessages,
  ) {
    final rideRange = _rideHistoryRange();
    final visibleRides = rideRange == null
        ? rides
        : rides.where((ride) {
            final date = _rideHistoryDate(ride['createdAt']);
            return date != null &&
                !date.isBefore(rideRange.start) &&
                date.isBefore(rideRange.end);
          }).toList();
    final messagesByRideId = <String, List<Map<String, dynamic>>>{};
    for (final message in chatMessages) {
      final rideId = message['rideId']?.toString();
      if (rideId == null) continue;
      messagesByRideId.putIfAbsent(rideId, () => []).add(message);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'فترة الرحلات',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _rideHistoryPeriod,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('كل الفترات')),
                  DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                  DropdownMenuItem(value: 'month', child: Text('شهر')),
                  DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
                ],
                onChanged: (period) {
                  if (period != null) {
                    unawaited(_selectRideHistoryPeriod(period));
                  }
                },
              ),
            ),
          ),
        ),
        if (_rideHistoryPeriod == 'custom' && _rideHistoryCustomRange != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_rideHistoryCustomRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_rideHistoryCustomRange!.end)}',
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: visibleRides.isEmpty
              ? _emptyState(rides.isEmpty
                  ? 'لا توجد رحلات مسجلة'
                  : 'لا توجد رحلات ضمن الفترة المحددة')
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: visibleRides.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final ride = visibleRides[index];
                    final rideId = (ride['rideId'] ?? ride['id'])?.toString();
                    final messages = messagesByRideId[rideId] ?? [];
                    messages.sort(_compareChatMessages);
                    return _recordTile(
                      ride,
                      additionalChildren: [_rideConversation(messages)],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _rideConversation(List<Map<String, dynamic>> messages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Text(
            'محادثة الرحلة',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (messages.isEmpty)
          const ListTile(title: Text('لا توجد رسائل لهذه الرحلة'))
        else
          ...messages.map(_chatMessageTile),
      ],
    );
  }

  Widget _chatMessageTile(Map<String, dynamic> message) {
    final timestamps = <String>[
      if (message['createdAt'] != null)
        'الإرسال: ${_displayValue('createdAt', message['createdAt'])}',
      if (message['deliveredAt'] != null)
        'التسليم: ${_displayValue('deliveredAt', message['deliveredAt'])}',
      if (message['readAt'] != null)
        'القراءة: ${_displayValue('readAt', message['readAt'])}',
    ];
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(32, 0, 16, 0),
      title: Text(message['senderName']?.toString() ?? 'مستخدم'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message['messageBody']?.toString() ?? ''),
          if (timestamps.isNotEmpty)
            Text(
              timestamps.join('  ·  '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  int _compareChatMessages(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    DateTime? timestamp(dynamic value) => value is DateTime
        ? value
        : value == null
            ? null
            : DateTime.tryParse(value.toString());

    final leftDate = timestamp(left['createdAt']);
    final rightDate = timestamp(right['createdAt']);
    if (leftDate != null && rightDate != null) {
      final dateOrder = leftDate.compareTo(rightDate);
      if (dateOrder != 0) return dateOrder;
    }
    final leftId = int.tryParse(left['id']?.toString() ?? '');
    final rightId = int.tryParse(right['id']?.toString() ?? '');
    if (leftId != null && rightId != null) return leftId.compareTo(rightId);
    return (left['id']?.toString() ?? '')
        .compareTo(right['id']?.toString() ?? '');
  }

  List<Widget> _recordTiles(List<Map<String, dynamic>> records) => [
        for (final record in records) _recordTile(record),
      ];

  Widget _recordTile(
    Map<String, dynamic> record, {
    List<Widget> additionalChildren = const [],
  }) {
    final summary = [
      if (record['status'] != null) _displayValue('status', record['status']),
      if (record['transactionType'] != null)
        _displayValue('transactionType', record['transactionType']),
      if (record['stars'] != null) '★ ${record['stars']}',
    ].join('  ·  ');
    final amount = record['amount'];
    return ExpansionTile(
      title: Text(_recordTitle(record)),
      subtitle: summary.isEmpty ? null : Text(summary),
      trailing: amount == null
          ? null
          : Text('${_displayValue('amount', amount)} ج.م',
              style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _recordFields(record),
        ),
        ...additionalChildren,
      ],
    );
  }

  Widget _recordFields(Map<String, dynamic> record) {
    final entries =
        record.entries.where((entry) => entry.value != null).toList();
    if (entries.isEmpty) return const Text('لا توجد بيانات');
    return Column(
      children: entries
          .map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        _fieldLabel(entry.key),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _displayValue(entry.key, entry.value),
                        textDirection:
                            _isLtrValue(entry.value) ? TextDirection.ltr : null,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  String _recordTitle(Map<String, dynamic> record) {
    for (final key in [
      'rideId',
      'id',
      'code',
      'title',
      'entryType',
      'category'
    ]) {
      final value = record[key];
      if (value != null) {
        return key == 'rideId'
            ? 'الرحلة $value'
            : '${_fieldLabel(key)}: ${_displayValue(key, value)}';
      }
    }
    return 'سجل مرتبط';
  }

  String _fieldLabel(String key) =>
      const {
        'riderId': 'رقم الراكب',
        'id': 'المعرّف',
        'fullName': 'الاسم',
        'email': 'البريد',
        'address': 'العنوان',
        'profileImageUrl': 'رابط الصورة',
        'phone': 'الهاتف',
        'rating': 'التقييم',
        'userRating': 'تقييم الحساب',
        'reputationPoints': 'نقاط السمعة',
        'receivedRatingsCount': 'عدد التقييمات المستلمة',
        'balance': 'الرصيد',
        'riderDebtLimit': 'حد الدين',
        'effectiveRiderDebtLimit': 'الحد الفعلي',
        'isActive': 'مفعل',
        'accountStatus': 'الحالة',
        'userIsOnline': 'حالة الاتصال',
        'createdAt': 'تاريخ الإنشاء',
        'updatedAt': 'آخر تحديث',
        'rideId': 'رقم الرحلة',
        'driverId': 'رقم السائق',
        'driverName': 'السائق',
        'driverPhone': 'هاتف السائق',
        'licensePlate': 'لوحة المركبة',
        'pickupAddress': 'نقطة الانطلاق',
        'pickupLatitude': 'خط عرض الانطلاق',
        'pickupLongitude': 'خط طول الانطلاق',
        'dropoffAddress': 'الوجهة',
        'dropoffLatitude': 'خط عرض الوجهة',
        'dropoffLongitude': 'خط طول الوجهة',
        'status': 'الحالة',
        'driverOfferRound': 'جولة البحث عن سائق',
        'fare': 'الأجرة',
        'distance': 'المسافة',
        'duration': 'المدة',
        'paymentMethod': 'طريقة الدفع',
        'paymentStatus': 'حالة الدفع',
        'cancellationReason': 'سبب الإلغاء',
        'acceptedAt': 'تاريخ القبول',
        'arrivedAt': 'تاريخ الوصول',
        'startedAt': 'بدء الرحلة',
        'completedAt': 'إكمال الرحلة',
        'cancelledAt': 'إلغاء الرحلة',
        'traceDistanceKm': 'مسافة التتبع (كم)',
        'matchedDistanceKm': 'المسافة المعتمدة (كم)',
        'distanceCalculationMethod': 'طريقة حساب المسافة',
        'couponCode': 'رمز القسيمة',
        'couponDiscount': 'قيمة الخصم',
        'riderPayableAmount': 'المطلوب من الراكب',
        'cashReceived': 'النقد المستلم',
        'riderWalletAdjustment': 'تعديل المحفظة',
        'commissionAmount': 'العمولة',
        'driverNet': 'صافي السائق',
        'settledAt': 'تاريخ التسوية',
        'shortfallRideId': 'رحلة العجز',
        'settlementRideId': 'رحلة التسوية',
        'cancellationRideId': 'رحلة الإلغاء',
        'collectingDriverId': 'معرف السائق المحصّل',
        'commissionDueAmount': 'العمولة المستحقة',
        'commissionPaidAmount': 'العمولة المدفوعة',
        'driverPaidAmount': 'المبلغ المدفوع للسائق',
        'walletFundedAmount': 'الممول من المحفظة',
        'reversedAt': 'تاريخ العكس',
        'reversedBy': 'تم العكس بواسطة',
        'reason': 'السبب',
        'transactionType': 'نوع الحركة',
        'amount': 'المبلغ',
        'referenceId': 'المرجع',
        'description': 'الوصف',
        'raterUserId': 'معرف المقيّم',
        'raterName': 'المقيّم',
        'targetUserId': 'معرف الطرف المقيّم',
        'targetName': 'الطرف المقيّم',
        'stars': 'النجوم',
        'comment': 'التعليق',
        'pointsDelta': 'تغير النقاط',
        'code': 'رمز القسيمة',
        'discountPercent': 'نسبة الخصم',
        'startsAt': 'تبدأ',
        'expiresAt': 'تنتهي',
        'reservedAt': 'تاريخ الحجز',
        'redeemedAt': 'تاريخ الاستخدام',
        'readAt': 'تاريخ القراءة',
        'title': 'العنوان',
        'body': 'المحتوى',
        'messageBody': 'الرسالة',
        'senderName': 'المرسل',
        'senderUserId': 'معرف المرسل',
        'deliveredAt': 'تاريخ التسليم',
        'attemptNumber': 'رقم المحاولة',
        'offerRound': 'جولة العرض',
        'offeredAt': 'تاريخ العرض',
        'respondedAt': 'تاريخ الرد',
        'latitude': 'خط العرض',
        'longitude': 'خط الطول',
        'accuracyMeters': 'دقة الموقع بالمتر',
        'capturedAt': 'وقت الالتقاط',
        'capturedAtMs': 'وقت الالتقاط',
        'receivedAt': 'وقت الاستلام',
        'approachStartLatitude': 'خط عرض بداية الاقتراب',
        'approachStartLongitude': 'خط طول بداية الاقتراب',
        'approachStartAccuracyMeters': 'دقة موقع بداية الاقتراب',
        'approachStartLocationAt': 'وقت بداية الاقتراب',
        'initialEtaArrivalAt': 'وقت الوصول المتوقع',
        'approachCheckedAt': 'وقت التحقق من الاقتراب',
        'approachWaived': 'إعفاء رسوم الإلغاء',
        'speedMps': 'السرعة (م/ث)',
        'reversedAmount': 'المبلغ المعكوس',
        'reversalReason': 'سبب العكس',
        'recoveredAmount': 'المبلغ المسترد',
        'walletPaidAmount': 'المدفوع من المحفظة',
        'rideCount': 'عدد الرحلات',
      }[key] ??
      key;

  String _displayValue(String key, dynamic value) {
    const booleanFields = {
      'isActive',
      'userIsOnline',
      'approachWaived',
      'isOnline'
    };
    if (value is bool || booleanFields.contains(key)) {
      if (value == true || value == 1 || value.toString() == '1') return 'نعم';
      if (value == false || value == 0 || value.toString() == '0') return 'لا';
    }

    if (key == 'capturedAtMs' && value is num) {
      return _formatDate(DateTime.fromMillisecondsSinceEpoch(value.toInt()));
    }
    if (key.endsWith('At') || key == 'createdAt' || key == 'updatedAt') {
      final date = value is DateTime ? value : DateTime.tryParse('$value');
      if (date != null) return _formatDate(date);
    }

    final text = value.toString();
    const labels = {
      'active': 'نشط',
      'suspended': 'موقوف',
      'offline': 'غير متصل',
      'idle': 'متاح',
      'in_progress': 'قيد التنفيذ',
      'completed': 'مكتملة',
      'cancelled': 'ملغاة',
      'accepted': 'مقبولة',
      'arriving': 'في الطريق',
      'requested': 'مطلوبة',
      'offered': 'معروضة',
      'rejected': 'مرفوضة',
      'expired': 'منتهية',
      'standard': 'اقتصادي',
      'comfort': 'مميز',
      'scooter': 'سكوتر',
      'deposit': 'إيداع',
      'withdrawal': 'سحب',
      'payment': 'دفع',
      'refund': 'استرداد',
      'commission': 'عمولة',
      'cancellation_fee': 'رسوم إلغاء',
      'cash': 'نقدي',
      'wallet': 'محفظة',
      'card': 'بطاقة',
      'paid': 'مدفوع',
      'pending': 'معلق',
      'failed': 'فشل',
      'rider': 'راكب',
      'driver': 'سائق',
      'customer_service': 'خدمة العملاء',
      'promotion': 'عرض ترويجي',
      'guidance': 'إرشادات',
    };
    return labels[text] ?? text;
  }

  String _formatDate(DateTime date) =>
      intl.DateFormat('y/MM/dd  HH:mm').format(date.toLocal());

  bool _isLtrValue(dynamic value) =>
      value is num ||
      (value is String && RegExp(r'^[+\-\d\s.,:/]+$').hasMatch(value));

  List<Map<String, dynamic>> _records(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .toList()
      : <Map<String, dynamic>>[];

  Widget _statusLabel(String label, bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? Colors.green.withValues(alpha: .12)
              : Colors.red.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.w600,
            )),
      );

  Widget _errorBanner(String message) => Padding(
        padding: const EdgeInsets.all(16),
        child: MaterialBanner(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => unawaited(_loadRiders(reset: true)),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );

  Widget _emptyState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}

class _RiderEditDialog extends StatefulWidget {
  const _RiderEditDialog({required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<_RiderEditDialog> createState() => _RiderEditDialogState();
}

class _RiderEditDialogState extends State<_RiderEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: '${widget.profile['fullName'] ?? ''}');
    _emailController =
        TextEditingController(text: '${widget.profile['email'] ?? ''}');
    _addressController =
        TextEditingController(text: '${widget.profile['address'] ?? ''}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تعديل بيانات الراكب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(
                  controller: _emailController,
                  decoration:
                      const InputDecoration(labelText: 'البريد الإلكتروني')),
              TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'العنوان')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'fullName': _nameController.text,
              'email': _emailController.text,
              'address': _addressController.text,
            }),
            child: const Text('حفظ'),
          ),
        ],
      );
}

class _WalletAdjustmentDialog extends StatefulWidget {
  const _WalletAdjustmentDialog();

  @override
  State<_WalletAdjustmentDialog> createState() =>
      _WalletAdjustmentDialogState();
}

class _WalletAdjustmentDialogState extends State<_WalletAdjustmentDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _direction = 'credit';

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تعديل محفظة الراكب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'credit', label: Text('إضافة')),
                ButtonSegment(value: 'debit', label: Text('خصم')),
              ],
              selected: {_direction},
              onSelectionChanged: (values) =>
                  setState(() => _direction = values.first),
            ),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            TextField(
              controller: _descriptionController,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'سبب الحركة'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'direction': _direction,
              'amount': _amountController.text,
              'description': _descriptionController.text,
            }),
            child: const Text('تسجيل الحركة'),
          ),
        ],
      );
}

class _RiderDebtLimitDialog extends StatefulWidget {
  const _RiderDebtLimitDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_RiderDebtLimitDialog> createState() => _RiderDebtLimitDialogState();
}

class _RiderDebtLimitDialogState extends State<_RiderDebtLimitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limit;

  @override
  void initState() {
    super.initState();
    _limit = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حد دين الراكب'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'الحد (ج.م)',
              helperText: 'أدخل قيمة سالبة أو صفرًا',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              final amount = double.tryParse(text);
              if (!RegExp(r'^-?\d+(?:\.\d{1,2})?$').hasMatch(text) ||
                  amount == null ||
                  amount > 0 ||
                  amount < -99999999.99) {
                return 'أدخل حدًا صالحًا لا يتجاوز الصفر';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {'riderDebtLimit': null}),
          child: const Text('استخدام الحد العام'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {'riderDebtLimit': _limit.text.trim()});
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
