import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/admin_config.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    required this.adminToken,
    required this.onSessionExpired,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final Dio? client;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late final Dio _dio;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final List<Map<String, dynamic>> _selectedRecipients = [];
  List<Map<String, dynamic>> _recipientSuggestions = [];
  Timer? _recipientSearchTimer;
  int _recipientSearchRequest = 0;
  bool _isSearchingRecipients = false;
  String? _recipientSearchError;
  String _category = 'customer_service';
  String _audience = 'all';
  String _recipientRole = 'rider';
  bool _isLoading = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _phoneController.dispose();
    _recipientSearchTimer?.cancel();
    super.dispose();
  }

  void _onRecipientPhoneChanged(String value) {
    _recipientSearchRequest++;
    if (RegExp(r'[,;\n]').hasMatch(value)) {
      final entries = value
          .split(RegExp(r'[,;\n]+'))
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      final validEntries = entries
          .where((entry) => RegExp(r'^\+?[0-9]{4,24}$').hasMatch(entry))
          .toSet();
      setState(() {
        for (final phone in validEntries) {
          if (!_selectedRecipients
              .any((recipient) => recipient['phone'] == phone)) {
            _selectedRecipients.add({
              'fullName': '',
              'phone': phone,
              'role': _recipientRole,
            });
          }
        }
        _phoneController.clear();
        _recipientSuggestions = [];
        _recipientSearchError = validEntries.length == entries.length
            ? null
            : 'تحقق من أرقام الهاتف المدخلة';
      });
      _recipientSearchTimer?.cancel();
      return;
    }

    final prefix = value.trim();
    _recipientSearchTimer?.cancel();
    final digits = prefix.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 3 || !RegExp(r'^\+?[0-9]+$').hasMatch(prefix)) {
      setState(() {
        _recipientSuggestions = [];
        _isSearchingRecipients = false;
        _recipientSearchError = null;
      });
      return;
    }

    setState(() {
      _recipientSuggestions = [];
      _isSearchingRecipients = true;
      _recipientSearchError = null;
    });
    _recipientSearchTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_searchRecipients(prefix));
    });
  }

  Future<void> _searchRecipients(String phonePrefix) async {
    final requestId = ++_recipientSearchRequest;
    setState(() {
      _isSearchingRecipients = true;
      _recipientSearchError = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/notifications/recipients',
        queryParameters: {'role': _recipientRole, 'phonePrefix': phonePrefix},
        options: Options(
          headers: {'Authorization': 'Bearer ${widget.adminToken}'},
        ),
      );
      if (!mounted || requestId != _recipientSearchRequest) return;
      final rows = response.data?['recipients'];
      final suggestions = rows is List
          ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((recipient) => !_selectedRecipients.any(
                    (selected) => selected['phone'] == recipient['phone'],
                  ))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _recipientSuggestions = suggestions;
        _isSearchingRecipients = false;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _recipientSearchRequest) return;
      if (error.response?.statusCode == 401) {
        final data = error.response?.data;
        final message = data is Map ? data['message']?.toString() : null;
        widget.onSessionExpired(message ?? 'جلسة الإدارة غير صالحة');
      } else {
        setState(() {
          _recipientSearchError = 'تعذر البحث عن المستخدمين';
          _isSearchingRecipients = false;
        });
      }
    }
  }

  void _addRecipient(Map<String, dynamic> recipient) {
    final phone = recipient['phone']?.toString();
    if (phone == null || phone.isEmpty) return;
    setState(() {
      if (!_selectedRecipients.any((selected) => selected['phone'] == phone)) {
        _selectedRecipients.add(recipient);
      }
      _recipientSuggestions = [];
      _recipientSearchError = null;
      _phoneController.clear();
    });
  }

  void _removeRecipient(String phone) {
    setState(() {
      _selectedRecipients
          .removeWhere((recipient) => recipient['phone'] == phone);
    });
  }

  void _changeRecipientRole(String? role) {
    if (role == null || role == _recipientRole) return;
    _recipientSearchTimer?.cancel();
    _recipientSearchRequest++;
    setState(() {
      _recipientRole = role;
      _selectedRecipients.clear();
      _recipientSuggestions = [];
      _recipientSearchError = null;
      _phoneController.clear();
    });
  }

  Future<void> _sendNotification() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/admin/notifications',
        data: {
          'category': _category,
          'title': _titleController.text.trim(),
          'body': _bodyController.text.trim(),
          'audience': _audience,
          if (_audience == 'user') ...{
            'role': _recipientRole,
            'phones': _selectedRecipients
                .map((recipient) => recipient['phone'].toString())
                .toList(),
          },
        },
        options:
            Options(headers: {'Authorization': 'Bearer ${widget.adminToken}'}),
      );
      if (!mounted) return;
      final data = response.data ?? const {};
      final recipients = (data['recipients'] as num?)?.toInt() ?? 0;
      final savedRecipients = (data['savedRecipients'] as num?)?.toInt() ?? 0;
      final delivered = (data['delivered'] as num?)?.toInt() ?? 0;
      final recipientsWithoutDevices =
          (data['recipientsWithoutDevices'] as num?)?.toInt() ?? 0;
      final recipientsFailed = (data['recipientsFailed'] as num?)?.toInt() ?? 0;
      final recipientsWithFailures =
          (data['recipientsWithFailures'] as num?)?.toInt() ?? 0;
      final failedDevices = (data['failedDevices'] as num?)?.toInt() ?? 0;
      final unmatchedRecipients =
          (data['unmatchedRecipients'] as num?)?.toInt() ?? 0;
      final rawFailureCodes = data['failureCodes'];
      final failureDetails = rawFailureCodes is Map
          ? rawFailureCodes.entries
              .take(3)
              .map((entry) => '${entry.key} (${entry.value})')
              .join('، ')
          : '';
      final details = <String>[
        if (unmatchedRecipients > 0)
          'لم يتم العثور على $unmatchedRecipients رقم نشط',
        if (recipientsWithoutDevices > 0)
          'بلا جهاز مسجل: $recipientsWithoutDevices',
        if (failedDevices > 0) 'فشل الإرسال إلى $failedDevices جهاز',
        if (recipientsFailed > 0 && failedDevices == 0)
          'تعذر الإرسال إلى $recipientsFailed مستلم',
        if (recipientsWithFailures > 0 &&
            recipientsFailed == 0 &&
            failedDevices == 0)
          'تعذر الإرسال إلى بعض الأجهزة',
        if (failureDetails.isNotEmpty) 'تفاصيل الخطأ: $failureDetails',
      ];
      final message = recipients == 0
          ? 'لا يوجد مستلمون، ولم يُحفظ التنبيه'
          : delivered == 0
              ? 'لم يصل التنبيه لأي جهاز، لذلك لم يُحفظ. ${details.join('؛ ')}'
              : 'تم حفظ التنبيه لـ $savedRecipients من $recipients مستلم، '
                  'وأُرسل إلى $delivered جهاز'
                  '${details.isEmpty ? '' : '. ${details.join('؛ ')}'}';
      setState(() {
        _message = message;
        _messageIsError = delivered == 0;
      });
      if (delivered > 0) {
        _titleController.clear();
        _bodyController.clear();
        _phoneController.clear();
        setState(() {
          _selectedRecipients.clear();
          _recipientSuggestions = [];
          _recipientSearchError = null;
        });
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        final data = error.response?.data;
        final message = data is Map ? data['message']?.toString() : null;
        widget.onSessionExpired(message ?? 'جلسة الإدارة غير صالحة');
        return;
      }
      _setError(error, 'تعذر إرسال التنبيه');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(DioException error, String fallback) {
    final data = error.response?.data;
    final message = data is Map ? data['message']?.toString() : null;
    if (!mounted) return;
    setState(() {
      _message = message ?? fallback;
      _messageIsError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 76, 24, 24),
              children: [
                _buildComposer(),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _messageIsError
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'نوع التنبيه'),
          items: const [
            DropdownMenuItem(
                value: 'customer_service', child: Text('خدمة العملاء')),
            DropdownMenuItem(value: 'promotion', child: Text('عرض ترويجي')),
            DropdownMenuItem(value: 'guidance', child: Text('توجيه')),
          ],
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _audience,
          decoration: const InputDecoration(labelText: 'المستلمون'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('الركاب والسائقون')),
            DropdownMenuItem(value: 'rider', child: Text('الركاب')),
            DropdownMenuItem(value: 'driver', child: Text('السائقون')),
            DropdownMenuItem(value: 'user', child: Text('مستخدم محدد')),
          ],
          onChanged: (value) {
            final audience = value ?? _audience;
            if (audience == _audience) return;
            _recipientSearchTimer?.cancel();
            _recipientSearchRequest++;
            _phoneController.clear();
            setState(() {
              _audience = audience;
              _selectedRecipients.clear();
              _recipientSuggestions = [];
              _recipientSearchError = null;
            });
          },
        ),
        if (_audience == 'user') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _recipientRole,
            decoration: const InputDecoration(labelText: 'دور المستخدم'),
            items: const [
              DropdownMenuItem(value: 'rider', child: Text('راكب')),
              DropdownMenuItem(value: 'driver', child: Text('سائق')),
            ],
            onChanged: _changeRecipientRole,
          ),
          const SizedBox(height: 12),
          _buildRecipientPicker(),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'العنوان'),
        ),
        TextField(
          controller: _bodyController,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'نص التنبيه'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed:
              _isLoading || (_audience == 'user' && _selectedRecipients.isEmpty)
                  ? null
                  : _sendNotification,
          icon: const Icon(Icons.send),
          label: Text(_isLoading ? 'جارٍ الإرسال...' : 'إرسال التنبيه'),
        ),
      ],
    );
  }

  Widget _buildRecipientPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.text,
          textDirection: TextDirection.ltr,
          maxLines: 2,
          onChanged: _onRecipientPhoneChanged,
          decoration: const InputDecoration(
            labelText: 'أرقام هواتف المستخدمين',
          ),
        ),
        if (_selectedRecipients.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedRecipients.map((recipient) {
              final phone = recipient['phone'].toString();
              final name = recipient['fullName']?.toString() ?? '';
              return InputChip(
                key: ValueKey('notification-recipient-$phone'),
                label: Text(name.isEmpty ? phone : '$name · $phone'),
                onDeleted: () => _removeRecipient(phone),
              );
            }).toList(),
          ),
        ],
        if (_isSearchingRecipients) const LinearProgressIndicator(),
        if (_recipientSuggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _recipientSuggestions.length,
              itemBuilder: (context, index) {
                final recipient = _recipientSuggestions[index];
                return ListTile(
                  dense: true,
                  title: Text(recipient['fullName']?.toString() ?? 'مستخدم'),
                  subtitle: Text(
                    recipient['phone']?.toString() ?? '',
                    textDirection: TextDirection.ltr,
                  ),
                  onTap: () => _addRecipient(recipient),
                );
              },
            ),
          ),
        if (_phoneController.text.trim().length >= 2 &&
            !_isSearchingRecipients &&
            _recipientSuggestions.isEmpty &&
            _recipientSearchError == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('لا توجد حسابات نشطة مطابقة'),
          ),
        if (_recipientSearchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _recipientSearchError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
