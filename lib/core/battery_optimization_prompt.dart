import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationPrompt {
  static const _channel = MethodChannel('com.gofast.admin_panel/battery');
  static const _requestedKey = 'battery_optimization_prompt_requested';

  static Future<void> requestOnce() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_requestedKey) ?? false) return;

    final saved = await preferences.setBool(_requestedKey, true);
    if (!saved) throw StateError('تعذر حفظ حالة طلب صلاحية البطارية');
    try {
      await _channel.invokeMethod<void>('requestExemption');
    } catch (_) {
      await preferences.remove(_requestedKey);
      rethrow;
    }
  }
}
