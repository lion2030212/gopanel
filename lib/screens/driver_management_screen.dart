import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../core/admin_config.dart';
import '../widgets/dashboard_navigation.dart';
import '../widgets/support_history_tab.dart';

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  late final Dio _dio;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listController = ScrollController();
  Timer? _searchTimer;
  List<Map<String, dynamic>> _drivers = [];
  Map<String, dynamic>? _details;
  String _status = 'all';
  String? _error;
  bool _loading = false;
  bool _loadingDetails = false;
  bool _hasMore = false;
  int _page = 1;
  int _requestId = 0;
  int _detailRequestId = 0;
  String _rideHistoryPeriod = 'week';
  DateTimeRange? _rideHistoryCustomRange;
  String _walletPeriod = 'day';
  DateTimeRange? _walletCustomRange;
  String _transactionsPeriod = 'week';
  DateTimeRange? _transactionsCustomRange;
  final Set<String> _transactionCategories = {};
  String _ratingsPeriod = 'week';
  DateTimeRange? _ratingsCustomRange;
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
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    unawaited(_loadDrivers(reset: true));
  }

  @override
  void dispose() {
    _dashboardBackHandler?.unregister(this);
    _searchTimer?.cancel();
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadDrivers(reset: true));
    });
  }

  Future<void> _loadDrivers({required bool reset}) async {
    final requestId = ++_requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/drivers',
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
      final rows = data['drivers'];
      final drivers = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      final total = (data['total'] as num?)?.toInt() ?? drivers.length;
      setState(() {
        _drivers = reset ? drivers : [..._drivers, ...drivers];
        _page = page;
        _hasMore = _drivers.length < total;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(
            () => _error = _messageFrom(error, 'تعذر تحميل قائمة الكباتن'));
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openDriver(Map<String, dynamic> driver) async {
    final id = driver['driverId'];
    if (id == null) return;
    final requestId = ++_detailRequestId;
    setState(() {
      _details = null;
      _loadingDetails = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/drivers/$id',
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
          _error = _messageFrom(error, 'تعذر تحميل ملف السائق');
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

  Future<void> _createDriver() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _DriverFormDialog(),
    );
    if (values == null) return;
    try {
      await _dio.post('/api/admin/drivers',
          data: values, options: _requestOptions);
      if (!mounted) return;
      _showMessage('تمت إضافة السائق بنجاح');
      await _loadDrivers(reset: true);
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر إضافة السائق');
    }
  }

  Future<void> _editDriver() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _DriverFormDialog(initialData: Map<String, dynamic>.from(profile)),
    );
    if (values == null) return;
    try {
      await _dio.patch(
        '/api/admin/drivers/${profile['driverId']}',
        data: values,
        options: _requestOptions,
      );
      await _openDriver({'driverId': profile['driverId']});
      if (mounted) _showMessage('تم تحديث بيانات السائق');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تعديل بيانات السائق');
    }
  }

  Future<void> _toggleStatus() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final currentlyActive = profile['accountStatus'] == 'active' &&
        (profile['isActive'] == true || profile['isActive'] == 1);
    final nextStatus = currentlyActive ? 'suspended' : 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(currentlyActive ? 'إيقاف حساب السائق؟' : 'تفعيل حساب السائق؟'),
        content: Text(currentlyActive
            ? 'سيبقى سجل الرحلات والمعاملات محفوظاً.'
            : 'سيتمكن السائق من استخدام الحساب وفق آلية الدخول الحالية.'),
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
      await _dio.patch(
        '/api/admin/drivers/${profile['driverId']}/status',
        data: {'status': nextStatus},
        options: _requestOptions,
      );
      await _openDriver({'driverId': profile['driverId']});
      if (mounted) {
        _showMessage(
            nextStatus == 'active' ? 'تم تفعيل الحساب' : 'تم إيقاف الحساب');
      }
      unawaited(_loadDrivers(reset: true));
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحديث حالة الحساب');
    }
  }

  Future<void> _adjustWallet() async {
    final profile = _details?['profile'];
    if (profile is! Map) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _WalletAdjustmentDialog(),
    );
    if (values == null) return;
    try {
      await _dio.post(
        '/api/admin/drivers/${profile['driverId']}/wallet-adjustments',
        data: values,
        options: _requestOptions,
      );
      await _openDriver({'driverId': profile['driverId']});
      if (mounted) _showMessage('تم تسجيل حركة المحفظة');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تعديل المحفظة');
    }
  }

  Future<void> _editDriverDebtLimit(Map<String, dynamic> profile) async {
    final initialValue = profile['driverDebtLimit'] ??
        profile['effectiveDriverDebtLimit'] ??
        '-300.00';
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DriverDebtLimitDialog(initialValue: '$initialValue'),
    );
    if (values == null) return;
    try {
      await _dio.patch(
        '/api/admin/drivers/${profile['driverId']}',
        data: values,
        options: _requestOptions,
      );
      await _openDriver({'driverId': profile['driverId']});
      if (mounted) _showMessage('تم تحديث حد مديونية السائق');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحديث حد المديونية');
    }
  }

  Future<void> _selectWalletPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _walletCustomRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة المعاملات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _walletPeriod = period;
        _walletCustomRange = selectedRange;
      });
      return;
    }
    setState(() => _walletPeriod = period);
  }

  DateTimeRange? _walletTransactionRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_walletPeriod) {
      case 'day':
        return DateTimeRange(
            start: today, end: today.add(const Duration(days: 1)));
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
        final customRange = _walletCustomRange;
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

  DateTime? _walletTransactionDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  Future<void> _selectTransactionsPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _transactionsCustomRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة المعاملات والتحويلات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
      setState(() {
        _transactionsPeriod = period;
        _transactionsCustomRange = selectedRange;
      });
      return;
    }
    setState(() => _transactionsPeriod = period);
  }

  DateTimeRange? _transactionsRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_transactionsPeriod) {
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
        final customRange = _transactionsCustomRange;
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

  DateTime? _financialRecordDate(Map<String, dynamic> record) {
    for (final key in const [
      'createdAt',
      'settledAt',
      'reversedAt',
      'recoveredAt',
      'updatedAt',
    ]) {
      final date = _walletTransactionDate(record[key]);
      if (date != null) return date;
    }
    return null;
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

  Future<void> _deactivateDriverFromList(Map<String, dynamic> driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السائق بأمان؟'),
        content: const Text(
            'سيتم تعطيل الحساب مع الإبقاء على الرحلات والسجلات المالية.'),
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
      await _dio.patch(
        '/api/admin/drivers/${driver['driverId']}/status',
        data: {'status': 'suspended'},
        options: _requestOptions,
      );
      await _loadDrivers(reset: true);
      _showMessage('تم تعطيل الحساب مع حفظ السجلات');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تعطيل الحساب');
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
                  ? _buildDriverList()
                  : _buildDriverProfile(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriverList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('إدارة الكباتن',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              FilledButton.icon(
                onPressed: _createDriver,
                icon: const Icon(Icons.add),
                label: const Text('إضافة سائق'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchController,
            onChanged: _searchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText:
                  'ابحث برقم السائق أو الاسم أو الهاتف أو اللوحة أو رقم الرحلة',
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('الكل')),
              ButtonSegment(value: 'active', label: Text('نشط')),
              ButtonSegment(value: 'inactive', label: Text('غير نشط')),
              ButtonSegment(value: 'suspended', label: Text('محظور / موقوف')),
            ],
            selected: {_status},
            onSelectionChanged: (selection) {
              setState(() => _status = selection.first);
              unawaited(_loadDrivers(reset: true));
            },
          ),
        ),
        if (_error != null) _errorBanner(_error!),
        Expanded(
          child: _loading && _drivers.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _drivers.isEmpty
                  ? _emptyState('لا يوجد سائقون مطابقون للبحث')
                  : RefreshIndicator(
                      onRefresh: () => _loadDrivers(reset: true),
                      child: ListView.separated(
                        controller: _listController,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: _drivers.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _drivers.length) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: _loading
                                    ? null
                                    : () => _loadDrivers(reset: false),
                                icon: const Icon(Icons.expand_more),
                                label: Text(_loading
                                    ? 'جارٍ التحميل...'
                                    : 'تحميل المزيد'),
                              ),
                            );
                          }
                          return _driverRow(_drivers[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _driverRow(Map<String, dynamic> driver) {
    final active = driver['accountStatus'] == 'active' &&
        (driver['isActive'] == true || driver['isActive'] == 1);
    final name = driver['fullName']?.toString().trim();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: CircleAvatar(
        backgroundImage: _imageProvider(driver['profileImageUrl']),
        child: driver['profileImageUrl'] == null
            ? const Icon(Icons.person_outline)
            : null,
      ),
      title: Text(name?.isNotEmpty == true ? name! : 'بدون اسم',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${driver['phone'] ?? 'بدون هاتف'}  ·  ${driver['licensePlate'] ?? 'بدون لوحة'}\n'
        'آخر رحلة: ${driver['latestRideId'] ?? 'لا توجد'}'
        '${driver['currentRideId'] == null ? '' : '  ·  الحالية: ${driver['currentRideId']}'}',
        maxLines: 2,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _statusLabel(
                  active
                      ? 'نشط'
                      : driver['accountStatus'] == 'suspended'
                          ? 'موقوف'
                          : 'غير نشط',
                  active),
              const SizedBox(height: 4),
              Text(
                  driver['isOnline'] == true || driver['isOnline'] == 1
                      ? 'متصل'
                      : 'غير متصل',
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          IconButton(
            tooltip: 'حذف آمن: تعطيل الحساب',
            onPressed: active ? () => _deactivateDriverFromList(driver) : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      onTap: () => _openDriver(driver),
    );
  }

  Widget _buildDriverProfile() {
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
                  onPressed: () => setState(() => _details = null),
                  icon: const Icon(Icons.arrow_forward))),
          if (_error != null)
            _errorBanner(_error!)
          else
            _emptyState('تعذر تحميل بيانات السائق'),
        ],
      );
    }
    final accountActive = profile['accountStatus'] == 'active' &&
        (profile['isActive'] == true || profile['isActive'] == 1);
    final rides = _asList(details['rides']);
    final wallet = details['wallet'] is Map
        ? Map<String, dynamic>.from(details['wallet'] as Map)
        : <String, dynamic>{};
    final transactions = _asList(wallet['transactions']);
    final ratings = _asList(details['ratings']);
    final financialRecords = details['financialRecords'] is Map
        ? Map<String, dynamic>.from(details['financialRecords'] as Map)
        : <String, dynamic>{};

    return DefaultTabController(
      length: 8,
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
                    icon: const Icon(Icons.arrow_back)),
                Expanded(
                  child: Text(
                    profile['fullName']?.toString().trim().isNotEmpty == true
                        ? profile['fullName'].toString()
                        : 'ملف السائق',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                    tooltip: 'تعديل البيانات',
                    onPressed: _editDriver,
                    icon: const Icon(Icons.edit_outlined)),
                IconButton(
                  tooltip: accountActive ? 'إيقاف الحساب' : 'تفعيل الحساب',
                  onPressed: _toggleStatus,
                  icon: Icon(accountActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline),
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'البيانات الشخصية'),
              Tab(text: 'المركبة'),
              Tab(text: 'سجل الرحلات'),
              Tab(text: 'المحفظة'),
              Tab(text: 'المعاملات والتحويلات'),
              Tab(text: 'التقييمات'),
              Tab(text: 'الشكاوى'),
              Tab(text: 'محادثات خدمة العملاء'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _personalTab(Map<String, dynamic>.from(profile)),
                _vehicleTab(Map<String, dynamic>.from(profile)),
                _rideHistoryTab(rides, _asList(details['chatMessages'])),
                _walletTab(
                  wallet,
                  rides,
                  transactions,
                  Map<String, dynamic>.from(profile),
                ),
                _transactionsTab(financialRecords),
                _ratingsTab(ratings, Map<String, dynamic>.from(profile)),
                SupportHistoryTab(
                  client: _dio,
                  adminToken: widget.adminToken,
                  userId:
                      int.tryParse(profile['userId']?.toString() ?? '') ?? 0,
                  userRole: 'driver',
                  ticketsMode: true,
                  onSessionExpired: widget.onSessionExpired,
                ),
                SupportHistoryTab(
                  client: _dio,
                  adminToken: widget.adminToken,
                  userId:
                      int.tryParse(profile['userId']?.toString() ?? '') ?? 0,
                  userRole: 'driver',
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

  Widget _personalTab(Map<String, dynamic> profile) {
    final imageUrl = profile['profileImageUrl'];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundImage: _imageProvider(imageUrl),
            child: imageUrl == null
                ? const Icon(Icons.person_outline, size: 40)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _recordFields(profile),
      ],
    );
  }

  Widget _vehicleTab(Map<String, dynamic> profile) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8)),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_car_outlined, size: 40),
              SizedBox(height: 8),
              Text('لا توجد صورة مركبة في قاعدة البيانات')
            ],
          ),
        ),
        const SizedBox(height: 16),
        _recordFields({
          'driverId': profile['driverId'],
          'carModel': profile['carModel'],
          'carColor': profile['carColor'],
          'licensePlate': profile['licensePlate'],
          'vehicleCategory': profile['vehicleCategory'],
          'driverRating': profile['driverRating'],
          'isOnline': profile['isOnline'],
          'driverStatus': profile['driverStatus'],
          'latitude': profile['latitude'],
          'longitude': profile['longitude'],
          'locationAccuracyMeters': profile['locationAccuracyMeters'],
          'lastLocationUpdate': profile['lastLocationUpdate'],
          'driverCreatedAt': profile['driverCreatedAt'],
          'driverUpdatedAt': profile['driverUpdatedAt'],
        }),
        const Divider(height: 28),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('مستندات المركبة غير متاحة'),
          subtitle: Text(
              'قاعدة البيانات الحالية لا تحتوي على صور أو سجلات تحقق للمركبة.'),
        ),
      ],
    );
  }

  Widget _walletTab(
    Map<String, dynamic> wallet,
    List<Map<String, dynamic>> rides,
    List<Map<String, dynamic>> transactions,
    Map<String, dynamic> profile,
  ) {
    final commissions = rides.fold<double>(
        0, (sum, ride) => sum + (_number(ride['commissionAmount']) ?? 0));
    final earnings = rides.fold<double>(
        0, (sum, ride) => sum + (_number(ride['driverNet']) ?? 0));
    final transactionRange = _walletTransactionRange();
    final visibleTransactions = transactionRange == null
        ? <Map<String, dynamic>>[]
        : transactions.where((transaction) {
            final date = _walletTransactionDate(transaction['createdAt']);
            return date != null &&
                !date.isBefore(transactionRange.start) &&
                date.isBefore(transactionRange.end);
          }).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('الرصيد الحالي', '${wallet['balance'] ?? 0} ج.م',
                Icons.account_balance_wallet_outlined),
            _stat('صافي مستحقات الرحلات', '${earnings.toStringAsFixed(2)} ج.م',
                Icons.payments_outlined),
            _stat('العمولات المسجلة', '${commissions.toStringAsFixed(2)} ج.م',
                Icons.receipt_long_outlined),
            SizedBox(
              width: 220,
              child: _driverDebtLimitControl(profile),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: _adjustWallet,
            icon: const Icon(Icons.add_card),
            label: const Text('إضافة / خصم رصيد'),
          ),
        ),
        const SizedBox(height: 16),
        _recordFields({'عدد الرحلات المسجلة': rides.length}),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _walletPeriod,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'فترة المعاملات'),
          items: const [
            DropdownMenuItem(value: 'day', child: Text('يوم')),
            DropdownMenuItem(value: 'week', child: Text('أسبوع')),
            DropdownMenuItem(value: 'month', child: Text('شهر')),
            DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
          ],
          onChanged: (period) {
            if (period != null) unawaited(_selectWalletPeriod(period));
          },
        ),
        if (_walletPeriod == 'custom' && _walletCustomRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_walletCustomRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_walletCustomRange!.end)}',
            ),
          ),
        const SizedBox(height: 12),
        Text('حركات المحفظة', style: Theme.of(context).textTheme.titleMedium),
        if (visibleTransactions.isEmpty)
          const ListTile(title: Text('لا توجد معاملات ضمن الفترة المحددة'))
        else
          ...visibleTransactions.map(_recordTile),
      ],
    );
  }

  Widget _driverDebtLimitControl(Map<String, dynamic> profile) {
    final override = profile['driverDebtLimit'];
    final effectiveLimit = profile['effectiveDriverDebtLimit'] ?? '-300.00';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.speed_outlined),
      title: const Text('حد مديونية المحفظة'),
      subtitle: Text(override == null
          ? 'الحد العام: $effectiveLimit ج.م'
          : 'حد مخصص: $effectiveLimit ج.م'),
      trailing: IconButton(
        tooltip: 'تعديل حد المديونية',
        onPressed: () => _editDriverDebtLimit(profile),
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _transactionsTab(
    Map<String, dynamic> financialRecords,
  ) {
    const sectionLabels = {
      'appLedger': 'دفتر عمولات ورسوم التطبيق',
      'shortfalls': 'عجوزات الرحلات',
      'shortfallRecoveries': 'استردادات العجوزات',
      'cancellationFees': 'تسويات رسوم الإلغاء',
      'cancellationFeeRecoveries': 'تحصيل رسوم الإلغاء',
    };
    final range = _transactionsRange();
    final visibleSections = financialRecords.entries
        .map((entry) {
          final records = entry.value is List
              ? (entry.value as List)
                  .whereType<Map>()
                  .map((record) => Map<String, dynamic>.from(record))
                  .where((record) {
                  if (_transactionsPeriod == 'all') return true;
                  final date = _financialRecordDate(record);
                  return date != null &&
                      range != null &&
                      !date.isBefore(range.start) &&
                      date.isBefore(range.end);
                }).toList()
              : <Map<String, dynamic>>[];
          return MapEntry(entry.key, records);
        })
        .where((entry) =>
            (_transactionCategories.isEmpty ||
                _transactionCategories.contains(entry.key)) &&
            entry.value.isNotEmpty)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('سجل مالي فقط'),
          subtitle:
              Text('لا توجد في النظام طلبات سحب معلقة أو إجراءات قبول ورفض.'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _transactionsPeriod,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'فترة المعاملات'),
          items: const [
            DropdownMenuItem(value: 'day', child: Text('يوم')),
            DropdownMenuItem(value: 'week', child: Text('أسبوع')),
            DropdownMenuItem(value: 'month', child: Text('شهر')),
            DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
            DropdownMenuItem(value: 'all', child: Text('كل الفترات')),
          ],
          onChanged: (period) {
            if (period != null) unawaited(_selectTransactionsPeriod(period));
          },
        ),
        if (_transactionsPeriod == 'custom' && _transactionsCustomRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_transactionsCustomRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_transactionsCustomRange!.end)}',
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('كل التصنيفات'),
                selected: _transactionCategories.isEmpty,
                onSelected: (_) =>
                    setState(() => _transactionCategories.clear()),
              ),
              for (final entry in sectionLabels.entries) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(entry.value),
                  selected: _transactionCategories.contains(entry.key),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _transactionCategories.add(entry.key);
                    } else {
                      _transactionCategories.remove(entry.key);
                    }
                  }),
                ),
              ],
            ],
          ),
        ),
        if (visibleSections.isEmpty)
          const ListTile(title: Text('لا توجد معاملات ضمن الفترة المحددة')),
        for (final entry in visibleSections) ...[
          const Divider(height: 28),
          Text(sectionLabels[entry.key] ?? entry.key,
              style: Theme.of(context).textTheme.titleMedium),
          ...entry.value.map(_recordTile),
        ],
      ],
    );
  }

  Widget _ratingsTab(
      List<Map<String, dynamic>> ratings, Map<String, dynamic> profile) {
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
          'userRating': profile['userRating'],
          'driverRating': profile['driverRating'],
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
              child: Center(child: Text('لا توجد تقييمات ضمن الفترة المحددة')))
        else
          ...visibleRatings
              .map((rating) => _recordTile(rating, preferRideId: true)),
      ],
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

  Widget _recordTile(
    Map<String, dynamic> record, {
    bool preferRideId = false,
    List<Widget> additionalChildren = const [],
  }) {
    final title = preferRideId && record['rideId'] != null
        ? 'الرحلة ${record['rideId']}'
        : record['id'] != null
            ? 'رقم ${record['id']}'
            : record['rideId'] != null
                ? 'الرحلة ${record['rideId']}'
                : record['referenceId'] != null
                    ? 'مرجع ${record['referenceId']}'
                    : 'سجل مالي';
    final summary = [
      record['status'],
      record['transactionType'],
      record['stars'] == null ? null : '⭐ ${record['stars']}'
    ]
        .where((value) => value != null && value.toString().isNotEmpty)
        .join('  ·  ');
    return ExpansionTile(
      title: Text(title),
      subtitle: summary.isEmpty ? null : Text(summary),
      trailing: record['amount'] != null
          ? Text('${record['amount']} ج.م',
              style: const TextStyle(fontWeight: FontWeight.w700))
          : null,
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _recordFields(record)),
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
                        child: Text(_label(entry.key),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_displayValue(entry.key, entry.value),
                            textDirection: _isLtrValue(entry.value)
                                ? TextDirection.ltr
                                : null)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return SizedBox(
      width: 220,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon),
        title: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(label),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _statusLabel(String label, bool active) {
    final color = active ? Colors.green.shade700 : Colors.red.shade700;
    return Text(label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }

  Widget _errorBanner(String message) => MaterialBanner(
        content: Text(message),
        leading: const Icon(Icons.error_outline),
        actions: [
          TextButton(
              onPressed: () => _loadDrivers(reset: true),
              child: const Text('إعادة المحاولة'))
        ],
      );

  Widget _emptyState(String message) => Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center)),
      );

  ImageProvider<Object>? _imageProvider(dynamic value) {
    final url = value?.toString();
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  List<Map<String, dynamic>> _asList(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : <Map<String, dynamic>>[];

  double? _number(dynamic value) =>
      value == null ? null : double.tryParse(value.toString());

  bool _isLtrValue(dynamic value) =>
      value is num ||
      (value is String && RegExp(r'^[+\-\d\s.,:/]+$').hasMatch(value));

  String _displayValue(String key, dynamic value) {
    const booleanFields = {'isActive', 'isOnline', 'userIsOnline'};
    if (value is bool || booleanFields.contains(key)) {
      if (value == true || value == 1 || value.toString() == '1') return 'نعم';
      if (value == false || value == 0 || value.toString() == '0') return 'لا';
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
    };
    return labels[text] ?? text;
  }

  String _label(String key) {
    const labels = {
      'userId': 'رقم المستخدم',
      'driverId': 'رقم السائق',
      'fullName': 'الاسم',
      'email': 'البريد الإلكتروني',
      'address': 'العنوان',
      'profileImageUrl': 'رابط الصورة',
      'phone': 'رقم الهاتف',
      'userRating': 'تقييم الحساب',
      'driverRating': 'تقييم السائق',
      'reputationPoints': 'نقاط السمعة',
      'balance': 'الرصيد',
      'riderDebtLimit': 'حد الدين',
      'driverDebtLimit': 'حد مديونية السائق',
      'effectiveDriverDebtLimit': 'حد المديونية الفعلي',
      'isActive': 'الحساب مفعّل',
      'accountStatus': 'حالة الحساب',
      'isOnline': 'متصل',
      'userIsOnline': 'اتصال المستخدم',
      'driverStatus': 'حالة السائق',
      'carModel': 'طراز المركبة',
      'carColor': 'لون المركبة',
      'licensePlate': 'رقم اللوحة',
      'vehicleCategory': 'فئة المركبة',
      'latitude': 'خط العرض',
      'longitude': 'خط الطول',
      'locationAccuracyMeters': 'دقة الموقع (م)',
      'lastLocationUpdate': 'آخر تحديث للموقع',
      'userCreatedAt': 'تاريخ إنشاء الحساب',
      'userUpdatedAt': 'تحديث الحساب',
      'driverCreatedAt': 'تاريخ تسجيل السائق',
      'driverUpdatedAt': 'تحديث بيانات السائق',
      'id': 'المعرّف',
      'rideId': 'رقم الرحلة',
      'riderId': 'رقم الراكب',
      'riderName': 'اسم الراكب',
      'riderPhone': 'هاتف الراكب',
      'pickupAddress': 'نقطة الانطلاق',
      'pickupLatitude': 'خط عرض الانطلاق',
      'pickupLongitude': 'خط طول الانطلاق',
      'dropoffAddress': 'نقطة الوصول',
      'dropoffLatitude': 'خط عرض الوصول',
      'dropoffLongitude': 'خط طول الوصول',
      'status': 'الحالة',
      'driverOfferRound': 'جولة العرض',
      'fare': 'الأجرة',
      'distance': 'المسافة',
      'duration': 'المدة',
      'paymentMethod': 'طريقة الدفع',
      'paymentStatus': 'حالة الدفع',
      'createdAt': 'تاريخ الإنشاء',
      'acceptedAt': 'تاريخ القبول',
      'arrivedAt': 'تاريخ الوصول',
      'startedAt': 'بدء الرحلة',
      'completedAt': 'إكمال الرحلة',
      'cancelledAt': 'إلغاء الرحلة',
      'cancellationReason': 'سبب الإلغاء',
      'driverPenaltyPoints': 'نقاط مخالفة السائق',
      'traceStartedAt': 'بدء تتبع المسار',
      'traceDistanceKm': 'مسافة التتبع (كم)',
      'traceFinalizedAt': 'إنهاء التتبع',
      'matchedDistanceKm': 'المسافة المعتمدة (كم)',
      'distanceCalculationMethod': 'طريقة حساب المسافة',
      'traceMatchedAt': 'مطابقة المسار',
      'baseFare': 'الأجرة الأساسية',
      'perKmRate': 'سعر الكيلومتر',
      'waitingPerMinute': 'سعر الانتظار للدقيقة',
      'cancellationFee': 'رسوم الإلغاء',
      'minimumFare': 'الحد الأدنى للأجرة',
      'commissionPercent': 'نسبة العمولة',
      'couponCode': 'رمز الخصم',
      'couponPercent': 'نسبة الخصم',
      'couponDiscount': 'قيمة الخصم',
      'riderPayableAmount': 'المبلغ المستحق على الراكب',
      'waitSeconds': 'الانتظار (ثانية)',
      'cashReceived': 'النقد المستلم',
      'riderWalletAdjustment': 'تعديل محفظة الراكب',
      'commissionAmount': 'قيمة العمولة',
      'driverNet': 'صافي السائق',
      'settledAt': 'تاريخ التسوية',
      'amount': 'المبلغ',
      'recoveredAmount': 'المبلغ المسترد',
      'commissionDueAmount': 'العمولة المستحقة',
      'commissionPaidAmount': 'العمولة المدفوعة',
      'walletPaidAmount': 'المدفوع من المحفظة',
      'driverPaidAmount': 'المبلغ المدفوع للسائق',
      'walletFundedAmount': 'الممول من المحفظة',
      'transactionType': 'نوع الحركة',
      'referenceId': 'المرجع',
      'description': 'مسمى الحركة',
      'stars': 'النجوم',
      'comment': 'التعليق',
      'raterUserId': 'معرف المقيّم',
      'raterName': 'المقيّم',
      'targetUserId': 'معرف الطرف المقيّم',
      'targetName': 'الطرف المقيّم',
      'pointsDelta': 'تغير النقاط',
      'entryType': 'نوع القيد',
      'shortfallRideId': 'رحلة العجز',
      'settlementRideId': 'رحلة التسوية',
      'cancellationRideId': 'رحلة الإلغاء',
      'collectingDriverId': 'السائق المحصّل',
      'receivedRatingsCount': 'عدد التقييمات المسجلة',
    };
    return labels[key] ??
        key.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match[1]}');
  }
}

class _DriverFormDialog extends StatefulWidget {
  const _DriverFormDialog({this.initialData});

  final Map<String, dynamic>? initialData;

  @override
  State<_DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends State<_DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  String _vehicleCategory = 'standard';

  bool get _isEdit => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? const <String, dynamic>{};
    _controllers = {
      'fullName':
          TextEditingController(text: data['fullName']?.toString() ?? ''),
      'phone': TextEditingController(text: data['phone']?.toString() ?? ''),
      'email': TextEditingController(text: data['email']?.toString() ?? ''),
      'address': TextEditingController(text: data['address']?.toString() ?? ''),
      'carModel':
          TextEditingController(text: data['carModel']?.toString() ?? ''),
      'carColor':
          TextEditingController(text: data['carColor']?.toString() ?? ''),
      'licensePlate':
          TextEditingController(text: data['licensePlate']?.toString() ?? ''),
    };
    _vehicleCategory = data['vehicleCategory']?.toString() ?? 'standard';
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل بيانات السائق' : 'إضافة سائق جديد'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('fullName', 'اسم السائق', required: true),
                if (!_isEdit)
                  _field('phone', 'رقم الهاتف',
                      required: true, keyboardType: TextInputType.phone),
                _field('email', 'البريد الإلكتروني'),
                _field('address', 'العنوان'),
                _field('carModel', 'طراز المركبة', required: true),
                _field('carColor', 'لون المركبة', required: true),
                _field('licensePlate', 'رقم اللوحة', required: true),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleCategory,
                  decoration: const InputDecoration(labelText: 'فئة المركبة'),
                  items: const [
                    DropdownMenuItem(value: 'standard', child: Text('اقتصادي')),
                    DropdownMenuItem(value: 'comfort', child: Text('مميز')),
                    DropdownMenuItem(value: 'scooter', child: Text('سكوتر')),
                  ],
                  onChanged: (value) => setState(
                      () => _vehicleCategory = value ?? _vehicleCategory),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: _submit, child: Text(_isEdit ? 'حفظ' : 'إنشاء')),
      ],
    );
  }

  Widget _field(String key, String label,
      {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextFormField(
        controller: _controllers[key],
        keyboardType: keyboardType,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        validator: required
            ? (value) =>
                value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final values = <String, dynamic>{
      for (final entry in _controllers.entries)
        if (!_isEdit || entry.key != 'phone')
          entry.key: entry.value.text.trim(),
      'vehicleCategory': _vehicleCategory,
    };
    if (_isEdit) values.remove('phone');
    Navigator.pop(context, values);
  }
}

class _WalletAdjustmentDialog extends StatefulWidget {
  const _WalletAdjustmentDialog();

  @override
  State<_WalletAdjustmentDialog> createState() =>
      _WalletAdjustmentDialogState();
}

class _WalletAdjustmentDialogState extends State<_WalletAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _direction = 'credit';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل رصيد المحفظة'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'credit',
                      label: Text('إضافة'),
                      icon: Icon(Icons.add)),
                  ButtonSegment(
                      value: 'debit',
                      label: Text('خصم'),
                      icon: Icon(Icons.remove)),
                ],
                selected: {_direction},
                onSelectionChanged: (value) =>
                    setState(() => _direction = value.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'المبلغ', suffixText: 'ج.م'),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  return amount == null || amount <= 0
                      ? 'أدخل مبلغاً أكبر من صفر'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'مسمى الحركة'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'مسمى الحركة مطلوب'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('تأكيد الحركة')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'direction': _direction,
      'amount': _amount.text.trim(),
      'description': _description.text.trim(),
    });
  }
}

class _DriverDebtLimitDialog extends StatefulWidget {
  const _DriverDebtLimitDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_DriverDebtLimitDialog> createState() => _DriverDebtLimitDialogState();
}

class _DriverDebtLimitDialogState extends State<_DriverDebtLimitDialog> {
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
      title: const Text('حد مديونية المحفظة'),
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
          onPressed: () => Navigator.pop(context, {'driverDebtLimit': null}),
          child: const Text('استخدام الحد العام'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {'driverDebtLimit': _limit.text.trim()});
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
