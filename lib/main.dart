import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/admin_firebase_photo_storage.dart';
import 'core/admin_session.dart';
import 'screens/admin_login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  void _logout(String? message) {
    if (!mounted || _adminSession == null) return;
    setState(() {
      _adminSession = null;
      _loginMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoFast Admin Panel',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _adminSession == null
          ? AdminLoginScreen(
              initialMessage: _loginMessage,
              onAuthenticated: (session) => setState(() {
                _adminSession = session;
                _loginMessage = null;
              }),
            )
          : HomeScreen(
              adminSession: _adminSession!,
              onLogout: _logout,
            ),
    );
  }
}
