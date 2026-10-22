import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../core/admin_api_client.dart';

class CouponManagementScreen extends StatefulWidget {
  const CouponManagementScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<CouponManagementScreen> createState() => _CouponManagementScreenState();
}

class _CouponManagementScreenState extends State<CouponManagementScreen> {
  static const _periods = <String, String>{
    'all': 'الكل',
    'week': 'أسبوع',
    'month': 'شهر',
    'custom': 'مدة محددة',
  };
  static const _statuses = <String, String>{
    'all': 'كل الحالات',
    'active': 'مفعّل الآن',
    'used': 'مستخدم',
    'disabled': 'معطّل',
    'upcoming': 'قادم',
    'expired': 'منتهي',
  };

  late final Dio _dio;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;
  String _period = 'all';
  String _status = 'all';
  DateTimeRange? _customRange;
  List<Map<String, dynamic>> _coupons = [];
  Map<String, int> _statusCounts = const <String, int>{};
  String? _error;
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _dio = widget.client ??
        createAdminApiClient(
          onSessionExpired: widget.onSessionExpired,
        );
    unawaited(_loadCoupons(reset: true));
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  DateTimeRange? get _validityRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'week':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today.add(const Duration(days: 1)),
        );
      case 'month':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today.add(const Duration(days: 1)),
        );
      case 'custom':
        final range = _customRange;
        if (range == null) return null;
        return DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day),
          end: DateTime(range.end.year, range.end.month, range.end.day)
              .add(const Duration(days: 1)),
        );
      default:
        return null;
    }
  }

  Future<void> _selectPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _customRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر فترة صلاحية الكوبونات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || range == null) return;
      setState(() {
        _customRange = range;
        _period = period;
      });
    } else {
      setState(() => _period = period);
    }
    await _loadCoupons(reset: true);
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    setState(() {});
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadCoupons(reset: true));
    });
  }

  Future<void> _loadCoupons({required bool reset}) async {
    final requestId = ++_requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'status': _status,
        'page': page,
        'limit': 30,
      };
      final search = _searchController.text.trim();
      if (search.isNotEmpty) query['search'] = search;
      final range = _validityRange;
      if (range != null) {
        query['startAt'] = range.start.toUtc().toIso8601String();
        query['endAt'] = range.end.toUtc().toIso8601String();
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/coupons',
        queryParameters: query,
        options: _requestOptions,
      );
      if (!mounted || requestId != _requestId) return;
      final data = response.data ?? const {};
      final rows = data['coupons'];
      final coupons = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      final total = (data['total'] as num?)?.toInt() ?? coupons.length;
      final rawCounts = data['counts'];
      final counts = <String, int>{};
      if (rawCounts is Map) {
        for (final entry in rawCounts.entries) {
          counts[entry.key.toString()] =
              int.tryParse(entry.value.toString()) ?? 0;
        }
      }
      setState(() {
        _coupons = reset ? coupons : [..._coupons, ...coupons];
        _statusCounts = counts;
        _page = page;
        _hasMore = _coupons.length < total;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      _handleRequestError(error, 'تعذر تحميل الكوبونات');
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openForm([Map<String, dynamic>? coupon]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: false,
      builder: (_) => CouponFormDialog(
        client: _dio,
        adminToken: widget.adminToken,
        coupon: coupon,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (values == null || !mounted) return;
    try {
      if (coupon == null) {
        await _dio.post('/api/admin/coupons',
            data: values, options: _requestOptions);
      } else {
        await _dio.patch('/api/admin/coupons/${coupon['couponId']}',
            data: values, options: _requestOptions);
      }
      await _loadCoupons(reset: true);
      if (mounted) {
        _showMessage(coupon == null ? 'تم إنشاء الكوبون' : 'تم تحديث الكوبون');
      }
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر حفظ الكوبون');
    }
  }

  Future<void> _toggleCoupon(Map<String, dynamic> coupon) async {
    final isActive = _asBool(coupon['isActive']);
    try {
      await _dio.patch(
        '/api/admin/coupons/${coupon['couponId']}',
        data: {'isActive': !isActive},
        options: _requestOptions,
      );
      await _loadCoupons(reset: true);
      if (mounted) {
        _showMessage(isActive ? 'تم تعطيل الكوبون' : 'تم تفعيل الكوبون');
      }
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تغيير حالة الكوبون');
    }
  }

  Future<void> _deleteCoupon(Map<String, dynamic> coupon) async {
    if (_asInt(coupon['reservationCount']) > 0 ||
        _asInt(coupon['redemptionCount']) > 0) {
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
      await _loadCoupons(reset: true);
      if (mounted) _showMessage('تم حذف الكوبون');
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر حذف الكوبون');
    }
  }

  Future<void> _showRedemptions(Map<String, dynamic> coupon) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/coupons/${coupon['couponId']}/redemptions',
        queryParameters: const {'page': 1, 'limit': 100},
        options: _requestOptions,
      );
      if (!mounted) return;
      final rows = response.data?['redemptions'];
      final redemptions = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      await showDialog<void>(
        context: context,
        builder: (context) => _RedemptionDialog(
          code: '${coupon['code']}',
          redemptions: redemptions,
          total:
              (response.data?['total'] as num?)?.toInt() ?? redemptions.length,
        ),
      );
    } on DioException catch (error) {
      _handleRequestError(error, 'تعذر تحميل سجل الاستخدام');
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('إدارة الكوبونات',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _searchController,
                            onChanged: _searchChanged,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'ابحث بالكود أو اسم الراكب',
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
                              isDense: true,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            initialValue: _period,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'فترة الصلاحية',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _periods.entries
                                .map((entry) => DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                unawaited(_selectPeriod(value));
                              }
                            },
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: _statuses.entries
                                .map((entry) => ButtonSegment<String>(
                                      value: entry.key,
                                      label: Text(
                                          '${entry.value} (${_statusCounts[entry.key] ?? 0})'),
                                    ))
                                .toList(),
                            selected: {_status},
                            onSelectionChanged: (selection) {
                              setState(() => _status = selection.first);
                              unawaited(_loadCoupons(reset: true));
                            },
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة كوبون'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!),
                        ),
                      ),
                    ),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: _coupons.isEmpty && _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _coupons.isEmpty
                            ? Center(
                                child: Text(_error ?? 'لا توجد كوبونات مطابقة'),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _loadCoupons(reset: true),
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 14, 20, 20),
                                  itemCount:
                                      _coupons.length + (_hasMore ? 1 : 0),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    if (index == _coupons.length) {
                                      return Center(
                                        child: TextButton.icon(
                                          onPressed: _loading
                                              ? null
                                              : () =>
                                                  _loadCoupons(reset: false),
                                          icon: const Icon(Icons.expand_more),
                                          label: const Text('تحميل المزيد'),
                                        ),
                                      );
                                    }
                                    return _couponTile(_coupons[index]);
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _couponTile(Map<String, dynamic> coupon) {
    final isActive = _asBool(coupon['isActive']);
    final redemptions = _asInt(coupon['redemptionCount']);
    final reservations = _asInt(coupon['reservationCount']);
    final startsAt = _dateValue(coupon['startsAt']);
    final expiresAt = _dateValue(coupon['expiresAt']);
    final status = _couponStatus(coupon, startsAt, expiresAt);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${coupon['code']}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                _statusChip(status),
                if (redemptions > 0)
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('مستخدم $redemptions مرة'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 18,
              runSpacing: 4,
              children: [
                _detail('الخصم', '${coupon['discountPercent']}%'),
                _detail(
                  'المستفيد',
                  coupon['riderId'] == null
                      ? 'جميع الركاب'
                      : '${coupon['riderName'] ?? 'راكب ${coupon['riderId']}'}',
                ),
                _detail('يبدأ', _formatDate(startsAt)),
                _detail('ينتهي', _formatDate(expiresAt)),
                _detail('حجوزات', '$reservations'),
                _detail('استخدامات', '$redemptions'),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.start,
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'سجل الاستخدام',
                  onPressed: () => _showRedemptions(coupon),
                  icon: const Icon(Icons.receipt_long_outlined),
                ),
                IconButton(
                  tooltip: 'تعديل الكوبون',
                  onPressed: () => _openForm(coupon),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: isActive ? 'تعطيل الكوبون' : 'تفعيل الكوبون',
                  onPressed: () => _toggleCoupon(coupon),
                  icon: Icon(isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline),
                ),
                IconButton(
                  tooltip: redemptions > 0 || reservations > 0
                      ? 'لا يمكن حذف كوبون له استخدامات'
                      : 'حذف الكوبون',
                  onPressed: () => _deleteCoupon(coupon),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Text('$label: $value');

  Widget _statusChip(String status) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLive = status == 'مفعّل';
    final background = status == 'معطّل'
        ? colorScheme.surfaceContainerHighest
        : isLive
            ? colorScheme.tertiaryContainer
            : colorScheme.secondaryContainer;
    return Chip(
      label: Text(status),
      visualDensity: VisualDensity.compact,
      backgroundColor: background,
      side: BorderSide.none,
    );
  }

  String _couponStatus(
      Map<String, dynamic> coupon, DateTime? startsAt, DateTime? expiresAt) {
    if (!_asBool(coupon['isActive'])) return 'معطّل';
    final now = DateTime.now();
    if (startsAt != null && startsAt.isAfter(now)) return 'قادم';
    if (expiresAt != null && !expiresAt.isAfter(now)) return 'منتهي';
    return 'مفعّل';
  }

  String _formatDate(DateTime? date) =>
      date == null ? 'غير محدد' : intl.DateFormat('yyyy/MM/dd').format(date);
}

class CouponFormDialog extends StatefulWidget {
  const CouponFormDialog({
    required this.client,
    required this.adminToken,
    required this.onSessionExpired,
    this.coupon,
    super.key,
  });

  final Dio client;
  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Map<String, dynamic>? coupon;

  @override
  State<CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<CouponFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _percentController;
  final TextEditingController _riderSearchController = TextEditingController();
  Timer? _searchTimer;
  String _scope = 'all';
  DateTime? _startsAt;
  DateTime? _expiresAt;
  Map<String, dynamic>? _selectedRider;
  List<Map<String, dynamic>> _riderResults = [];
  bool _searchingRiders = false;
  String? _riderSearchError;

  @override
  void initState() {
    super.initState();
    final coupon = widget.coupon;
    _codeController = TextEditingController(text: '${coupon?['code'] ?? ''}');
    _percentController = TextEditingController(
        text: '${coupon?['discountPercent'] ?? ''}'.replaceAll('.00', ''));
    final riderId = coupon?['riderId'];
    if (riderId != null) {
      _scope = 'rider';
      _selectedRider = {
        'riderId': riderId,
        'fullName': coupon?['riderName'] ?? 'راكب $riderId',
        'phone': coupon?['riderPhone'] ?? '',
      };
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _startsAt = _parseDate(coupon?['startsAt']) ?? today;
    _expiresAt =
        _parseDate(coupon?['expiresAt']) ?? today.add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _codeController.dispose();
    _percentController.dispose();
    _riderSearchController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  void _searchRidersChanged(String value) {
    _searchTimer?.cancel();
    _riderSearchError = null;
    if (value.trim().length < 2) {
      setState(() => _riderResults = []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 300), _searchRiders);
  }

  Future<void> _searchRiders() async {
    setState(() {
      _searchingRiders = true;
      _riderSearchError = null;
    });
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/riders',
        queryParameters: {
          'search': _riderSearchController.text.trim(),
          'limit': 10
        },
        options: _requestOptions,
      );
      if (!mounted) return;
      final rows = response.data?['riders'];
      setState(() {
        _riderResults = rows is List
            ? rows
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : [];
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
      } else {
        setState(() => _riderSearchError = 'تعذر البحث عن الركاب');
      }
    } finally {
      if (mounted) setState(() => _searchingRiders = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startsAt : _expiresAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'تاريخ بدء الكوبون' : 'تاريخ انتهاء الكوبون',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        _startsAt = DateTime(date.year, date.month, date.day);
      } else {
        _expiresAt = DateTime(date.year, date.month, date.day, 23, 59, 59);
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_scope == 'rider' && _selectedRider == null) {
      setState(() => _riderSearchError = 'ابحث عن الراكب واختره من النتائج');
      return;
    }
    final start = _startsAt!;
    final end = _expiresAt!;
    if (!end.isAfter(start)) {
      setState(
          () => _riderSearchError = 'تاريخ الانتهاء يجب أن يكون بعد البداية');
      return;
    }
    Navigator.of(context).pop({
      'code': _codeController.text.trim(),
      'riderId': _scope == 'all' ? null : _selectedRider!['riderId'],
      'discountPercent': _percentController.text.trim(),
      'startsAt': start.toIso8601String(),
      'expiresAt': end.toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.coupon == null ? 'إضافة كوبون' : 'تعديل الكوبون'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'كود الكوبون',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل كود الكوبون'
                        : value.trim().length > 64
                            ? 'الحد الأقصى 64 حرفًا'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _percentController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'نسبة الخصم',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final percent = double.tryParse(value?.trim() ?? '');
                      return percent == null || percent <= 0 || percent > 100
                          ? 'أدخل نسبة من 0 إلى 100'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: DropdownButtonFormField<String>(
                      initialValue: _scope,
                      alignment: AlignmentDirectional.centerStart,
                      decoration: const InputDecoration(
                        labelText: 'المستفيد',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'جميع الركاب',
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.start,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'rider',
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'راكب محدد',
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _scope = value ?? 'all';
                        if (_scope == 'all') _selectedRider = null;
                      }),
                    ),
                  ),
                  if (_scope == 'rider') ...[
                    const SizedBox(height: 10),
                    if (_selectedRider != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                            '${_selectedRider!['fullName'] ?? 'راكب ${_selectedRider!['riderId']}'}'),
                        subtitle: Text('${_selectedRider!['phone'] ?? ''}'),
                        trailing: IconButton(
                          tooltip: 'تغيير الراكب',
                          onPressed: () => setState(() {
                            _selectedRider = null;
                            _riderResults = [];
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      )
                    else ...[
                      TextField(
                        controller: _riderSearchController,
                        onChanged: _searchRidersChanged,
                        decoration: InputDecoration(
                          labelText: 'ابحث باسم الراكب أو هاتفه',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchingRiders
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_riderResults.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _riderResults.length,
                            itemBuilder: (context, index) {
                              final rider = _riderResults[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                    '${rider['fullName'] ?? 'راكب ${rider['riderId']}'}'),
                                subtitle: Text('${rider['phone'] ?? ''}'),
                                onTap: () => setState(() {
                                  _selectedRider = rider;
                                  _riderResults = [];
                                }),
                              );
                            },
                          ),
                        ),
                    ],
                    if (_riderSearchError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_riderSearchError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                  ],
                  const SizedBox(height: 12),
                  _dateButton(
                    label: 'تاريخ البداية',
                    date: _startsAt,
                    onPressed: () => _pickDate(start: true),
                  ),
                  _dateButton(
                    label: 'تاريخ الانتهاء',
                    date: _expiresAt,
                    onPressed: () => _pickDate(start: false),
                  ),
                  if (_scope != 'rider' && _riderSearchError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_riderSearchError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onPressed,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_month_outlined),
        title: Text(label),
        subtitle: Text(date == null
            ? 'اختر التاريخ'
            : intl.DateFormat('yyyy/MM/dd').format(date)),
        trailing: IconButton(
          tooltip: 'اختيار $label',
          onPressed: onPressed,
          icon: const Icon(Icons.edit_calendar_outlined),
        ),
      );
}

class _RedemptionDialog extends StatelessWidget {
  const _RedemptionDialog({
    required this.code,
    required this.redemptions,
    required this.total,
  });

  final String code;
  final List<Map<String, dynamic>> redemptions;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('سجل استخدام $code · $total'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: redemptions.isEmpty
              ? const Center(child: Text('لا توجد استخدامات مسجلة'))
              : ListView.separated(
                  itemCount: redemptions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final redemption = redemptions[index];
                    final redeemedAt =
                        DateTime.tryParse('${redemption['redeemedAt'] ?? ''}');
                    final reversed = redemption['reversedAt'] != null;
                    return ListTile(
                      leading: Icon(reversed
                          ? Icons.undo_outlined
                          : Icons.check_circle_outline),
                      title: Text(
                          '${redemption['riderName'] ?? 'راكب ${redemption['riderId']}'}'),
                      subtitle: Text(
                        '${redemption['riderPhone'] ?? ''}\n'
                        '${redeemedAt == null ? 'وقت غير محدد' : intl.DateFormat('yyyy/MM/dd HH:mm').format(redeemedAt)}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('رحلة #${redemption['rideId']}'),
                          if (reversed) const Text('مُعكوس'),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

bool _asBool(dynamic value) => value == true || value == 1 || value == '1';

int _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _dateValue(dynamic value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse('$value');
}
