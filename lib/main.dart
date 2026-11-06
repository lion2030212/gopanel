import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/admin_chat_foreground_service.dart';
import 'core/admin_firebase_photo_storage.dart';
import 'core/admin_session.dart';
import 'core/admin_session_storage.dart';
import 'core/battery_optimization_prompt.dart';
import 'screens/admin_login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdminChatForegroundService.initialize();
  if (kIsWeb) {
    try {
      await AdminFirebasePhotoStorage.initialize();
    } on FirebaseException catch (error) {
      debugPrint('Firebase Web initialization failed: ${error.message}');
    } catch (error) {
      debugPrint('Firebase Web initialization failed: $error');
    }
  }
  runApp(const AdminPanelApp());
}

class AdminPanelApp extends StatefulWidget {
  const AdminPanelApp({super.key});

  @override
  State<AdminPanelApp> createState() => _AdminPanelAppState();
}

class _AdminPanelAppState extends State<AdminPanelApp> {
  AdminSession? _adminSession;
  String? _loginMessage;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _requestBatteryOptimization();
  }

  Future<void> _restoreSession() async {
    try {
      _adminSession = await AdminSessionStorage().read();
      final session = _adminSession;
      if (session != null) {
        unawaited(AdminChatForegroundService.start(session));
      }
    } on FormatException catch (error) {
      debugPrint('Stored admin session is invalid: $error');
      try {
        await AdminSessionStorage().clear();
      } catch (clearError) {
        debugPrint('Unable to clear invalid admin session: $clearError');
      }
      _loginMessage = 'انتهت صلاحية بيانات الجلسة، يرجى تسجيل الدخول مجددًا';
    } catch (error) {
      debugPrint('Unable to restore admin session: $error');
      _loginMessage = 'تعذر استعادة الجلسة، يرجى تسجيل الدخول مجددًا';
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await BatteryOptimizationPrompt.requestOnce();
    } on PlatformException catch (error) {
      debugPrint('Battery optimization request failed: ${error.message}');
    } on MissingPluginException catch (error) {
      debugPrint('Battery optimization request is unavailable: $error');
    } catch (error) {
      debugPrint('Battery optimization request failed: $error');
    }
  }

  Future<void> _authenticate(AdminSession session) async {
    try {
      await AdminSessionStorage().write(session);
      unawaited(AdminChatForegroundService.start(session));
      if (!mounted) return;
      setState(() {
        _adminSession = session;
        _loginMessage = null;
      });
    } catch (error) {
      debugPrint('Unable to save admin session: $error');
      if (mounted) {
        setState(() => _loginMessage = 'تعذر حفظ الجلسة، يرجى المحاولة مجددًا');
      }
    }
  }

  Future<void> _logout(String? message) async {
    if (!mounted || _adminSession == null) return;
    var logoutMessage = message;
    try {
      await AdminSessionStorage().clear();
    } catch (error) {
      debugPrint('Unable to clear admin session: $error');
      logoutMessage ??= 'تعذر حذف بيانات الجلسة المحفوظة';
    }
    if (!mounted) return;
    setState(() {
      _adminSession = null;
      _loginMessage = logoutMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'GoFast Panel',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: _isInitializing
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              )
            : _adminSession == null
                ? AdminLoginScreen(
                    initialMessage: _loginMessage,
                    onAuthenticated: _authenticate,
                  )
                : HomeScreen(
                    adminSession: _adminSession!,
                    onLogout: _logout,
                  ),
      ),
    );
  }
}
