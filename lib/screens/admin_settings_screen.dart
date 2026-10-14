import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/admin_config.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const _categories = <String, String>{
    'standard': 'عادي',
    'comfort': 'مريح',
    'scooter': 'سكوتر',
  };
  static const _pricingFields = <String, String>{
    'baseFare': 'الأجرة الأساسية',
    'perKmRate': 'حساب الكيلومتر',
    'waitingPerMinute': 'الانتظار لكل دقيقة',
    'cancellationFee': 'رسوم الإلغاء',
    'minimumFare': 'الحد الأدنى للرحلة',
    'commissionPercent': 'عمولة التطبيق (%)',
  };
  static const _searchFields = <String, String>{
    'nearRadiusMeters': 'نطاق أولوية القرب (متر)',
    'maxDistanceKm': 'أقصى مسافة للبحث (كم)',
  };
  static const _walletFields = <String, String>{
    'driverDebtLimit': 'حد دين السائق',
    'riderDebtLimit': 'حد دين الراكب',
  };
  static const _versionFields = <String, String>{
    'minimumRiderBuild': 'أدنى رقم بناء لتطبيق الراكب',
    'minimumDriverBuild': 'أدنى رقم بناء لتطبيق السائق',
  };
  static final _storedBuildNumberPattern = RegExp(r'^(\d{1,8})(?:\.0+)?$');

  late final Dio _dio;
  final _pricingControllers = <String, Map<String, TextEditingController>>{};
  final _searchControllers = <String, TextEditingController>{};
  final _walletControllers = <String, TextEditingController>{};
  final _versionControllers = <String, TextEditingController>{};
  String _selectedCategory = 'standard';
  String? _message;
  bool _messageIsError = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    for (final category in _categories.keys) {
      _pricingControllers[category] = {
        for (final field in _pricingFields.keys) field: TextEditingController(),
      };
    }
    _searchControllers.addAll({
      for (final field in _searchFields.keys) field: TextEditingController(),
    });
    _walletControllers.addAll({
      for (final field in _walletFields.keys) field: TextEditingController(),
    });
    _versionControllers.addAll({
      for (final field in _versionFields.keys) field: TextEditingController(),
    });
    _loadSettings();
  }

  @override
  void dispose() {
    for (final controllers in _pricingControllers.values) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    for (final controller in _walletControllers.values) {
      controller.dispose();
    }
    for (final controller in _versionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/settings',
        options: _requestOptions,
      );
      final settings = response.data?['settings'];
      if (settings is! Map) throw const FormatException();
      _applySettings(Map<String, dynamic>.from(settings));
      if (!mounted) return;
      setState(() {
        _hasLoaded = true;
        _message = null;
      });
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        _showMessage(_messageFrom(error, 'تعذر تحميل إعدادات الإدارة'), true);
      }
    } on FormatException {
      _showMessage('استجابة إعدادات الإدارة غير مكتملة', true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applySettings(Map<String, dynamic> settings) {
    final pricing = _asMap(settings['pricing']);
    for (final category in _categories.keys) {
      final values = _asMap(pricing[category]);
      for (final field in _pricingFields.keys) {
        _pricingControllers[category]![field]!.text =
            values[field]?.toString() ?? '';
      }
    }
    final search = _asMap(settings['search']);
    for (final field in _searchFields.keys) {
      _searchControllers[field]!.text = search[field]?.toString() ?? '';
    }
    final wallet = _asMap(settings['wallet']);
    for (final field in _walletFields.keys) {
      _walletControllers[field]!.text = wallet[field]?.toString() ?? '';
    }
    final versions = _asMap(settings['versions']);
    for (final field in _versionFields.keys) {
      final storedValue = versions[field]?.toString() ?? '';
      final match = _storedBuildNumberPattern.firstMatch(storedValue);
      _versionControllers[field]!.text = match?.group(1) ?? storedValue;
    }
  }

  Future<void> _savePricing() => _save(
        '/api/admin/settings/pricing/$_selectedCategory',
        _pricingControllers[_selectedCategory]!,
        'تم حفظ أسعار فئة ${_categories[_selectedCategory]}',
        isNonNegative: true,
      );

  Future<void> _saveSearch() => _save(
        '/api/admin/settings/search',
        _searchControllers,
        'تم حفظ إعدادات البحث',
        isPositive: true,
      );

  Future<void> _saveWallet() => _save(
        '/api/admin/settings/wallet',
        _walletControllers,
        'تم حفظ حدود المحافظ',
        isNonPositive: true,
      );

  Future<void> _saveVersions() => _save(
        '/api/admin/settings/versions',
        _versionControllers,
        'تم حفظ حدود الإصدارات',
        isBuildNumber: true,
      );

  Future<void> _save(
    String path,
    Map<String, TextEditingController> controllers,
    String successMessage, {
    bool isNonNegative = false,
    bool isPositive = false,
    bool isNonPositive = false,
    bool isBuildNumber = false,
  }) async {
    final values = <String, String>{};
    for (final entry in controllers.entries) {
      final text = entry.value.text.trim();
      final value = double.tryParse(text);
      if (value == null ||
          !value.isFinite ||
          (isNonNegative && value < 0) ||
          (isPositive && value <= 0) ||
          (isNonPositive && value > 0) ||
          (isBuildNumber && !RegExp(r'^\d{1,8}$').hasMatch(text)) ||
          (entry.key == 'commissionPercent' && value > 100)) {
        _showMessage('تحقق من القيم المدخلة قبل الحفظ', true);
        return;
      }
      values[entry.key] = text;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      await _dio.patch<Map<String, dynamic>>(
        path,
        data: values,
        options: _requestOptions,
      );
      if (mounted) _showMessage(successMessage, false);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_messageFrom(error, 'جلسة الإدارة غير صالحة'));
      } else {
        _showMessage(_messageFrom(error, 'تعذر حفظ الإعدادات'), true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _messageFrom(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map ? data['message']?.toString() ?? fallback : fallback;
  }

  Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  void _showMessage(String message, bool isError) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: DefaultTabController(
              length: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.tune, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'الإدارة والتحكم',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تحديث الإعدادات',
                          onPressed:
                              _isLoading || _isSaving ? null : _loadSettings,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(
                          icon: Icon(Icons.price_change_outlined),
                          text: 'الأسعار'),
                      Tab(icon: Icon(Icons.manage_search), text: 'البحث'),
                      Tab(
                          icon: Icon(Icons.account_balance_wallet_outlined),
                          text: 'المحفظة'),
                      Tab(
                          icon: Icon(Icons.system_update_alt),
                          text: 'الإصدارات'),
                    ],
                  ),
                  if (_isLoading) const LinearProgressIndicator(minHeight: 2),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError
                              ? Theme.of(context).colorScheme.error
                              : Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: !_hasLoaded
                        ? Center(
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: _loadSettings,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة'),
                                  ),
                          )
                        : TabBarView(
                            children: [
                              _buildPricingTab(context),
                              _buildSearchTab(context),
                              _buildWalletTab(context),
                              _buildVersionsTab(context),
                            ],
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

  Widget _buildPricingTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(labelText: 'فئة المركبة'),
          items: [
            for (final entry in _categories.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _isSaving
              ? null
              : (value) =>
                  setState(() => _selectedCategory = value ?? 'standard'),
        ),
        const SizedBox(height: 16),
        _buildFields(
            context, _pricingFields, _pricingControllers[_selectedCategory]!),
        const SizedBox(height: 20),
        _buildSaveButton(
          label: 'حفظ أسعار الفئة',
          onPressed: _isSaving ? null : _savePricing,
        ),
      ],
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildFields(context, _searchFields, _searchControllers),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('شروط البحث الحالية',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              const Text('يشترط أن يكون السائق متصلاً وخاملاً وموقعه حديثاً.'),
              const SizedBox(height: 6),
              const Text(
                  'تُطابق فئة المركبة المطلوبة، وتُستبعد العروض السابقة والجارية.'),
              const SizedBox(height: 6),
              const Text(
                  'داخل النطاق القريب تُقدَّم السمعة ثم المسافة، وخارجه تُقدَّم المسافة ثم السمعة.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSaveButton(
          label: 'حفظ إعدادات البحث',
          onPressed: _isSaving ? null : _saveSearch,
        ),
      ],
    );
  }

  Widget _buildWalletTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildFields(context, _walletFields, _walletControllers),
        const SizedBox(height: 12),
        Text(
          'تُستخدم هذه القيم كحدود دين عامة عند عدم وجود حد فردي للحساب. تعديلها لا يغيّر الأرصدة الحالية.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _buildSaveButton(
          label: 'حفظ حدود المحافظ',
          onPressed: _isSaving ? null : _saveWallet,
        ),
      ],
    );
  }

  Widget _buildVersionsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildFields(
          context,
          _versionFields,
          _versionControllers,
          integerOnly: true,
        ),
        const SizedBox(height: 20),
        _buildSaveButton(
          label: 'حفظ حدود الإصدارات',
          onPressed: _isSaving ? null : _saveVersions,
        ),
      ],
    );
  }

  Widget _buildFields(BuildContext context, Map<String, String> labels,
      Map<String, TextEditingController> controllers,
      {bool integerOnly = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth > 620
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final entry in labels.entries)
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  key: ValueKey(entry.key),
                  controller: controllers[entry.key],
                  enabled: !_isSaving && !_isLoading,
                  keyboardType: integerOnly
                      ? TextInputType.number
                      : const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: entry.value),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSaveButton(
      {required String label, required VoidCallback? onPressed}) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(label),
      ),
    );
  }
}
