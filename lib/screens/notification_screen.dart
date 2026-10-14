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
    super.dispose();
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
            'phone': _phoneController.text.trim(),
          },
        },
        options: Options(headers: {'Authorization': 'Bearer ${widget.adminToken}'}),
      );
      if (!mounted) return;
      final data = response.data ?? const {};
      setState(() {
        _message = 'تم حفظ التنبيه لـ ${data['recipients'] ?? 0} مستلم، '
            'وأُرسل إلى ${data['delivered'] ?? 0} جهاز';
        _messageIsError = false;
      });
      _titleController.clear();
      _bodyController.clear();
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
                      color: _messageIsError ? Colors.red.shade700 : Colors.green.shade700,
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
            DropdownMenuItem(value: 'customer_service', child: Text('خدمة العملاء')),
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
          onChanged: (value) => setState(() => _audience = value ?? _audience),
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
            onChanged: (value) => setState(() => _recipientRole = value ?? _recipientRole),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم هاتف المستخدم'),
          ),
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
          onPressed: _isLoading ? null : _sendNotification,
          icon: const Icon(Icons.send),
          label: Text(_isLoading ? 'جارٍ الإرسال...' : 'إرسال التنبيه'),
        ),
      ],
    );
  }
}