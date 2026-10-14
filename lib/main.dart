import 'package:flutter/material.dart';

import 'core/admin_session.dart';
import 'screens/admin_login_screen.dart';
import 'screens/home_screen.dart';

void main() {
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
              onLogout: ([message]) => setState(() {
                _adminSession = null;
                _loginMessage = message;
              }),
            ),
    );
  }
}
