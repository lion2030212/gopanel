import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/admin_config.dart';
import '../core/admin_session.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    required this.onAuthenticated,
    this.initialMessage,
    super.key,
  });

  final ValueChanged<AdminSession> onAuthenticated;
  final String? initialMessage;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final Dio _dio = Dio(BaseOptions(baseUrl: adminApiBaseUrl));
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/admin/login',
        data: {
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
        },
      );
      if (!mounted) return;
      try {
        widget.onAuthenticated(
            AdminSession.fromLoginResponse(response.data ?? const {}));
      } on FormatException {
        setState(() => _message = 'تعذر بدء جلسة الإدارة');
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      setState(() {
        _message = data is Map ? data['message']?.toString() : null;
        _message ??= 'تعذر تسجيل الدخول';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('دخول الإدارة')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: 'كلمة المرور'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _login,
                  icon: const Icon(Icons.login),
                  label: Text(_isLoading ? 'جارٍ التحقق...' : 'دخول'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade700,
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
}
