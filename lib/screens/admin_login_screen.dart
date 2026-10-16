import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/admin_config.dart';
import '../core/admin_session.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    required this.onAuthenticated,
    this.initialMessage,
    this.client,
    super.key,
  });

  final ValueChanged<AdminSession> onAuthenticated;
  final String? initialMessage;
  final Dio? client;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  late final Dio _dio;
  late final bool _ownsDio;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  Timer? _lockoutTimer;
  bool _isLoading = false;
  int _remainingLockoutSeconds = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ownsDio = widget.client == null;
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    _message = widget.initialMessage;
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    if (_ownsDio) _dio.close(force: true);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startLockout(int seconds) {
    _lockoutTimer?.cancel();
    setState(() => _remainingLockoutSeconds = seconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remainingLockoutSeconds -= 1);
      if (_remainingLockoutSeconds <= 0) {
        timer.cancel();
        setState(() => _remainingLockoutSeconds = 0);
      }
    });
  }

  String get _lockoutCountdown {
    final minutes = _remainingLockoutSeconds ~/ 60;
    final seconds = _remainingLockoutSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _login() async {
    if (_isLoading || _remainingLockoutSeconds > 0) return;
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
      final retryAfterSeconds = data is Map
          ? int.tryParse(data['retryAfterSeconds']?.toString() ?? '')
          : null;
      setState(() {
        _message = data is Map ? data['message']?.toString() : null;
        _message ??= 'تعذر تسجيل الدخول';
      });
      if (retryAfterSeconds != null && retryAfterSeconds > 0) {
        _startLockout(retryAfterSeconds);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Center(
                    child: Container(
                      key: const Key('admin-login-heading-frame'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'دخول الادارة',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                  onPressed: _isLoading || _remainingLockoutSeconds > 0
                      ? null
                      : _login,
                  icon: const Icon(
                    Icons.arrow_forward,
                    textDirection: TextDirection.rtl,
                  ),
                  label: Text(
                    _isLoading
                        ? 'جارٍ التحقق...'
                        : _remainingLockoutSeconds > 0
                            ? 'دخول بعد $_lockoutCountdown'
                            : 'دخول',
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _remainingLockoutSeconds > 0
                        ? '$_message ($_lockoutCountdown)'
                        : _message!,
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
