import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/admin_config.dart';
import '../widgets/dashboard_navigation.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({
    required this.adminToken,
    required this.onSessionExpired,
    required this.currentAdminId,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final String currentAdminId;
  final Dio? client;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  late final Dio _dio;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _roles = [];
  Map<String, dynamic>? _selectedStaff;
  bool _loading = true;
  bool _uploadingPhoto = false;
  String? _error;
  String _searchQuery = '';
  final ImagePicker _imagePicker = ImagePicker();
  DashboardBackHandler? _dashboardBackHandler;

  Options get _options => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  @override
  void initState() {
    super.initState();
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    unawaited(_load());
  }

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
  void dispose() {
    _dashboardBackHandler?.unregister(this);
    _searchController.dispose();
    super.dispose();
  }

  bool _handleDashboardBack() {
    if (_selectedStaff == null) return false;
    setState(() => _selectedStaff = null);
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/staff',
        options: _options,
      );
      final data = response.data ?? const {};
      setState(() {
        _staff = _mapsFrom(data['staff']);
        _roles = _mapsFrom(data['roles']);
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_message(error, 'جلسة الإدارة غير صالحة'));
      } else {
        setState(() {
          _error = _message(error, 'تعذر تحميل بيانات الموظفين');
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _mapsFrom(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['message'] is String
        ? data['message'] as String
        : fallback;
  }

  void _handleError(DioException error, String fallback) {
    if (error.response?.statusCode == 401) {
      widget.onSessionExpired(_message(error, 'جلسة الإدارة غير صالحة'));
    } else {
      _showMessage(_message(error, fallback));
    }
  }

  Future<void> _openForm({
    Map<String, dynamic>? staff,
    bool canEdit = true,
  }) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _StaffFormDialog(
          roles: _roles,
          staff: staff,
          canEdit: staff == null || canEdit,
        ),
      ),
    );
    if (values == null) return;
    try {
      Map<String, dynamic>? createdStaff;
      if (staff == null) {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/admin/staff',
          data: values,
          options: _options,
        );
        final result = response.data?['staff'];
        if (result is Map) createdStaff = Map<String, dynamic>.from(result);
      } else {
        await _dio.patch('/api/admin/staff/${staff['id']}',
            data: values, options: _options);
      }
      await _load();
      if (mounted) {
        final staffId = staff?['id'] ?? createdStaff?['id'];
        if (staffId != null && (staff == null || _selectedStaff != null)) {
          final matches = _staff
              .where((item) => item['id']?.toString() == staffId.toString());
          setState(() {
            _selectedStaff = matches.isNotEmpty
                ? matches.first
                : {
                    ...?createdStaff,
                    ...?(_selectedStaff),
                    ...values,
                    'id': staffId,
                    'isActive': true,
                  };
          });
        }
        _showMessage(staff == null ? 'تم إنشاء الحساب' : 'تم تحديث الحساب');
      }
    } on DioException catch (error) {
      _handleError(error, 'تعذر حفظ بيانات الموظف');
    }
  }

  Future<void> _refreshSelectedStaff() async {
    final staffId = _selectedStaff?['id'];
    await _load();
    if (!mounted || staffId == null) return;
    final matches =
        _staff.where((item) => item['id']?.toString() == staffId.toString());
    if (matches.isNotEmpty) setState(() => _selectedStaff = matches.first);
  }

  Future<void> _pickAndUploadPhoto() async {
    final staff = _selectedStaff;
    if (staff == null || !_canEditStaff(staff)) return;
    setState(() => _uploadingPhoto = true);
    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (selected == null) return;
      final formData = FormData.fromMap({
        'photo': MultipartFile.fromBytes(
          await selected.readAsBytes(),
          filename: selected.name,
          contentType: MultipartFile.lookupMediaType(selected.name),
        ),
      });
      await _dio.put(
        '/api/admin/staff/${staff['id']}/photo',
        data: formData,
        options: _options,
      );
      await _refreshSelectedStaff();
      if (mounted) _showMessage('تم تحديث صورة الموظف');
    } on DioException catch (error) {
      _handleError(error, 'تعذر رفع صورة الموظف');
    } catch (_) {
      if (mounted) _showMessage('تعذر اختيار الصورة');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removeStaffPhoto() async {
    final staff = _selectedStaff;
    if (staff == null || !_canEditStaff(staff)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف صورة الموظف؟'),
          content: const Text('يمكن إضافة صورة جديدة لاحقاً.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف الصورة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _dio.delete(
        '/api/admin/staff/${staff['id']}/photo',
        options: _options,
      );
      await _refreshSelectedStaff();
      if (mounted) _showMessage('تم حذف الصورة');
    } on DioException catch (error) {
      _handleError(error, 'تعذر حذف صورة الموظف');
    }
  }

  bool _canEditStaff(Map<String, dynamic> staff) {
    final active = staff['isActive'] == true || staff['isActive'] == 1;
    final isCurrent = widget.currentAdminId == 'staff-${staff['id']}';
    return active && !isCurrent;
  }

  ImageProvider? _staffImageProvider(Object? imageUrl) {
    if (imageUrl == null || imageUrl.toString().isEmpty) return null;
    final value = imageUrl.toString();
    final uri = Uri.tryParse(value);
    final resolved = uri?.hasScheme == true
        ? value
        : Uri.parse(adminApiBaseUrl).resolve(value).toString();
    return NetworkImage(resolved);
  }

  Future<void> _resetPassword(Map<String, dynamic> staff) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _StaffPasswordDialog(),
      ),
    );
    if (password == null) return;
    try {
      await _dio.patch('/api/admin/staff/${staff['id']}/password',
          data: {'password': password}, options: _options);
      if (mounted) _showMessage('تم تغيير كلمة المرور');
    } on DioException catch (error) {
      _handleError(error, 'تعذر تغيير كلمة المرور');
    }
  }

  Future<void> _deactivate(Map<String, dynamic> staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعطيل حساب الموظف؟'),
          content: Text(
              'سيُمنع ${staff['username']} من تسجيل الدخول، مع الاحتفاظ بسجل إجراءاته.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تعطيل الحساب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _dio.delete('/api/admin/staff/${staff['id']}', options: _options);
      await _load();
      if (_selectedStaff?['id']?.toString() == staff['id']?.toString()) {
        setState(() => _selectedStaff = {...staff, 'isActive': false});
      }
      if (mounted) _showMessage('تم تعطيل الحساب');
    } on DioException catch (error) {
      _handleError(error, 'تعذر تعطيل الحساب');
    }
  }

  Future<void> _activate(Map<String, dynamic> staff) async {
    try {
      await _dio.post('/api/admin/staff/${staff['id']}/activate',
          options: _options);
      await _load();
      if (_selectedStaff?['id']?.toString() == staff['id']?.toString()) {
        setState(() => _selectedStaff = {...staff, 'isActive': true});
      }
      if (mounted) _showMessage('تمت إعادة تفعيل الحساب');
    } on DioException catch (error) {
      _handleError(error, 'تعذر تفعيل الحساب');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textAlign: TextAlign.center)),
    );
  }

  String _roleName(Map<String, dynamic> staff) =>
      staff['roleName']?.toString() ?? staff['role']?.toString() ?? '';

  List<Map<String, dynamic>> get _visibleStaff {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _staff;
    return _staff.where((staff) {
      final values = [
        staff['fullName'],
        staff['username'],
        staff['phone'],
        staff['email'],
        staff['jobTitle'],
        _roleName(staff),
      ];
      return values.any(
          (value) => value?.toString().toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Widget _buildStaffList() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('إدارة الموظفين',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _roles.isEmpty ? null : () => _openForm(),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('إضافة موظف'),
                    ),
                    IconButton(
                      tooltip: 'تحديث',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'ابحث بالاسم أو اسم المستخدم أو الهاتف أو البريد',
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading && _staff.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null && _staff.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          else if (_staff.isEmpty)
            const Expanded(child: Center(child: Text('لا توجد حسابات موظفين')))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _visibleStaff.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final staff = _visibleStaff[index];
                    final active =
                        staff['isActive'] == true || staff['isActive'] == 1;
                    final isCurrent =
                        widget.currentAdminId == 'staff-${staff['id']}';
                    final fullName = staff['fullName']?.toString().trim();
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: () => setState(() =>
                            _selectedStaff = Map<String, dynamic>.from(staff)),
                        leading: CircleAvatar(
                          backgroundImage:
                              _staffImageProvider(staff['profileImageUrl']),
                          child: Icon(active
                              ? Icons.badge_outlined
                              : Icons.person_off_outlined),
                        ),
                        title: Text(fullName?.isNotEmpty == true
                            ? fullName!
                            : '${staff['username'] ?? ''}'),
                        subtitle: Text(
                            '${staff['username'] ?? ''} · ${_roleName(staff)}${active ? '' : ' · معطّل'}'),
                        trailing: isCurrent
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'إجراءات الموظف',
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      unawaited(_openForm(staff: staff));
                                      break;
                                    case 'password':
                                      unawaited(_resetPassword(staff));
                                      break;
                                    case 'deactivate':
                                      unawaited(_deactivate(staff));
                                      break;
                                    case 'activate':
                                      unawaited(_activate(staff));
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (active)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل البيانات والرتبة'),
                                    ),
                                  if (active)
                                    const PopupMenuItem(
                                      value: 'password',
                                      child: Text('إعادة تعيين كلمة المرور'),
                                    ),
                                  if (active)
                                    const PopupMenuItem(
                                      value: 'deactivate',
                                      child: Text('تعطيل الحساب'),
                                    ),
                                  if (!active)
                                    const PopupMenuItem(
                                      value: 'activate',
                                      child: Text('إعادة تفعيل الحساب'),
                                    ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _staffInformation(String label, Object? value) => ListTile(
        title: Text(label),
        subtitle: Text(value?.toString().trim().isNotEmpty == true
            ? value.toString()
            : 'غير محدد'),
      );

  Widget _buildStaffProfile(Map<String, dynamic> staff) {
    final active = staff['isActive'] == true || staff['isActive'] == 1;
    final canEdit = _canEditStaff(staff);
    final imageUrl = staff['profileImageUrl'];
    final name = staff['fullName']?.toString().trim();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
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
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  CircleAvatar(
                    backgroundImage: _staffImageProvider(imageUrl),
                    child: _staffImageProvider(imageUrl) == null
                        ? const Icon(Icons.badge_outlined)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name?.isNotEmpty == true ? name! : 'ملف الموظف',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${staff['username'] ?? ''} · ${_roleName(staff)}${active ? '' : ' · معطّل'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'إعادة تعيين كلمة المرور',
                      onPressed: () => unawaited(_resetPassword(staff)),
                      icon: const Icon(Icons.password_outlined),
                    ),
                  if (widget.currentAdminId != 'staff-${staff['id']}')
                    IconButton(
                      tooltip: active ? 'تعطيل الحساب' : 'إعادة تفعيل الحساب',
                      onPressed: () => unawaited(
                          active ? _deactivate(staff) : _activate(staff)),
                      icon: Icon(active
                          ? Icons.block_outlined
                          : Icons.check_circle_outline),
                    ),
                ],
              ),
            ),
              if (canEdit)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'تعديل البيانات',
                      onPressed: () => unawaited(_openForm(staff: staff)),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'تسجيل الدخول'),
                Tab(text: 'البيانات الشخصية'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _staffInformation('اسم المستخدم', staff['username']),
                      _staffInformation('الرتبة الوظيفية', _roleName(staff)),
                      _staffInformation(
                        'حالة الحساب',
                        active ? 'نشط' : 'معطّل',
                      ),
                      _staffInformation('تاريخ الإنشاء', staff['createdAt']),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 48,
                          backgroundImage: _staffImageProvider(imageUrl),
                          child: _staffImageProvider(imageUrl) == null
                              ? const Icon(Icons.person_outline, size: 48)
                              : null,
                        ),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  _uploadingPhoto ? null : _pickAndUploadPhoto,
                              icon: _uploadingPhoto
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.photo_outlined),
                              label: Text(imageUrl == null
                                  ? 'إضافة صورة'
                                  : 'استبدال الصورة'),
                            ),
                            if (imageUrl != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'حذف الصورة',
                                onPressed:
                                    _uploadingPhoto ? null : _removeStaffPhoto,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _staffInformation('الاسم الكامل', staff['fullName']),
                      _staffInformation('رقم الهاتف', staff['phone']),
                      _staffInformation('البريد الإلكتروني', staff['email']),
                      _staffInformation('المسمى الوظيفي', staff['jobTitle']),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = _selectedStaff;
    return staff == null ? _buildStaffList() : _buildStaffProfile(staff);
  }
}

class _StaffFormDialog extends StatefulWidget {
  const _StaffFormDialog({
    required this.roles,
    required this.canEdit,
    this.staff,
  });

  final List<Map<String, dynamic>> roles;
  final Map<String, dynamic>? staff;
  final bool canEdit;

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();
  late final TabController _tabController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _jobTitleController;
  late String _role;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _usernameController =
        TextEditingController(text: widget.staff?['username']?.toString());
    _passwordController = TextEditingController();
    _fullNameController =
        TextEditingController(text: widget.staff?['fullName']?.toString());
    _phoneController =
        TextEditingController(text: widget.staff?['phone']?.toString());
    _emailController =
        TextEditingController(text: widget.staff?['email']?.toString());
    _jobTitleController =
        TextEditingController(text: widget.staff?['jobTitle']?.toString());
    _role = widget.staff?['role']?.toString() ??
        widget.roles.first['role'].toString();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_loginFormKey.currentState!.validate()) {
      _tabController.animateTo(0);
      return;
    }
    final profileForm = _profileFormKey.currentState;
    if (profileForm == null) {
      _tabController.animateTo(1);
      return;
    }
    if (!profileForm.validate()) {
      _tabController.animateTo(1);
      return;
    }
    Navigator.pop(context, {
      'username': _usernameController.text.trim(),
      'role': _role,
      if (widget.staff == null) 'password': _passwordController.text,
      'fullName': _fullNameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      'jobTitle': _jobTitleController.text.trim().isEmpty
          ? null
          : _jobTitleController.text.trim(),
    });
  }

  Widget _buildLoginTab() => Form(
        key: _loginFormKey,
        child: ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            TextFormField(
              controller: _usernameController,
              enabled: widget.canEdit,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              validator: (value) => value == null || value.trim().length < 3
                  ? 'أدخل 3 أحرف على الأقل'
                  : null,
            ),
            if (widget.staff == null)
              TextFormField(
                controller: _passwordController,
                enabled: widget.canEdit,
                obscureText: true,
                maxLength: 256,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور (8 أحرف على الأقل)',
                ),
                validator: (value) => value == null || value.length < 8
                    ? 'كلمة المرور يجب أن تكون 8 أحرف على الأقل'
                    : null,
              ),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'الرتبة الوظيفية'),
              items: widget.roles
                  .map((role) => DropdownMenuItem<String>(
                        value: role['role'].toString(),
                        child: Text(role['name']?.toString() ??
                            role['role'].toString()),
                      ))
                  .toList(),
              onChanged: widget.canEdit
                  ? (value) {
                      if (value != null) setState(() => _role = value);
                    }
                  : null,
            ),
          ],
        ),
      );

  Widget _buildProfileTab() => Form(
        key: _profileFormKey,
        child: ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            TextFormField(
              controller: _fullNameController,
              enabled: widget.canEdit,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'الاسم الكامل مطلوب'
                  : null,
            ),
            TextFormField(
              controller: _phoneController,
              enabled: widget.canEdit,
              keyboardType: TextInputType.phone,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
            TextFormField(
              controller: _emailController,
              enabled: widget.canEdit,
              keyboardType: TextInputType.emailAddress,
              maxLength: 254,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
            ),
            TextFormField(
              controller: _jobTitleController,
              enabled: widget.canEdit,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'المسمى الوظيفي'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dialogHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(260.0, 420.0);
    return AlertDialog(
      title: Text(widget.staff == null ? 'إضافة موظف' : 'ملف الموظف'),
      content: SizedBox(
        width: 560,
        height: dialogHeight,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'تسجيل الدخول'),
                Tab(text: 'البيانات الشخصية'),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: _tabController.index,
                children: [_buildLoginTab(), _buildProfileTab()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.canEdit ? 'إلغاء' : 'إغلاق'),
        ),
        if (widget.canEdit)
          FilledButton(
            onPressed: _submit,
            child: const Text('حفظ'),
          ),
      ],
    );
  }
}

class _StaffPasswordDialog extends StatefulWidget {
  const _StaffPasswordDialog();

  @override
  State<_StaffPasswordDialog> createState() => _StaffPasswordDialogState();
}

class _StaffPasswordDialogState extends State<_StaffPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إعادة تعيين كلمة المرور'),
        content: TextField(
          key: const ValueKey('staffPasswordReset'),
          controller: _passwordController,
          obscureText: true,
          maxLength: 256,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'كلمة مرور جديدة (8 أحرف على الأقل)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _passwordController.text.length < 8
                ? null
                : () => Navigator.pop(context, _passwordController.text),
            child: const Text('تغيير كلمة المرور'),
          ),
        ],
      );
}
