import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'admin_session.dart';

class AdminSessionStorage {
  static const _sessionKey = 'admin_session';

  Future<AdminSession?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final serializedSession = preferences.getString(_sessionKey);
    if (serializedSession == null) return null;

    final decoded = jsonDecode(serializedSession);
    if (decoded is! Map) {
      throw const FormatException('بيانات الجلسة غير مكتملة');
    }
    return AdminSession.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> write(AdminSession session) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _sessionKey,
      jsonEncode(session.toJson()),
    );
    if (!saved) throw StateError('تعذر حفظ جلسة الإدارة');
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
  }
}
