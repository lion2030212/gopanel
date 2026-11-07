import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'admin_session.dart';

class AdminPushNotifications {
  AdminPushNotifications({
    required Dio client,
    required AdminSession adminSession,
  })  : _client = client,
        _adminSession = adminSession;

  static const _channel = AndroidNotificationChannel(
    'gofast_general_notifications',
    'رسائل GoFast',
    description: 'تنبيهات عامة من GoFast',
    importance: Importance.high,
  );

  final Dio _client;
  final AdminSession _adminSession;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;
  String? _registeredToken;
  bool _started = false;

  Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('مدير لوحة التحكم لم يمنح إذن الإشعارات');
        return;
      }

      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final androidNotifications =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidNotifications?.createNotificationChannel(_channel);

      _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForegroundNotification(message));
      });
      // FCM's send-to-device API expects registration tokens, not installation IDs.
      // ignore: deprecated_member_use
      _tokenSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('لم يصدر Firebase رمز تسجيل FCM لجهاز المدير');
        return;
      }
      await _registerToken(token);
    } on FirebaseException catch (error) {
      _started = false;
      debugPrint('تعذر تهيئة إشعارات المدير: ${error.code} ${error.message}');
    } on DioException catch (error) {
      _started = false;
      debugPrint('تعذر تسجيل جهاز المدير للإشعارات: ${error.message}');
    } catch (error) {
      _started = false;
      debugPrint('تعذر تهيئة إشعارات المدير: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _registerTokenOnce(token);
        return;
      } on DioException catch (error) {
        debugPrint(
          'تعذر تسجيل جهاز المدير للإشعارات '
          '(محاولة $attempt، HTTP ${error.response?.statusCode ?? 'غير متاح'}): '
          '${error.response?.data ?? error.message}',
        );
        if (error.response?.statusCode == 401) return;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  Future<void> _registerTokenOnce(String token) async {
    await _client.post<void>(
      '/api/admin/notifications/device-token',
      data: {'token': token},
      options: Options(
        headers: {'Authorization': 'Bearer ${_adminSession.token}'},
      ),
    );
    _registeredToken = token;
    debugPrint('تم تسجيل جهاز لوحة التحكم لاستقبال تنبيهات المدير');
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title is! String || body is! String) return;
    try {
      await _localNotifications.show(
        id: message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'gofast_general_notifications',
            'رسائل GoFast',
            channelDescription: 'تنبيهات عامة من GoFast',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
        ),
        payload: message.data['event']?.toString(),
      );
    } catch (error) {
      debugPrint('تعذر عرض تنبيه المدير أثناء استخدام التطبيق: $error');
    }
  }

  Future<void> unregisterDevice() async {
    if (!_started) return;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    final token = _registeredToken;
    if (token != null) {
      try {
        await _client.delete<void>(
          '/api/admin/notifications/device-token',
          data: {'token': token},
          options: Options(
            headers: {'Authorization': 'Bearer ${_adminSession.token}'},
          ),
        );
      } on DioException catch (error) {
        debugPrint('تعذر حذف رمز إشعارات المدير: ${error.message}');
      }
      _registeredToken = null;
    }
  }

  void dispose() {
    unawaited(_messageSubscription?.cancel());
    unawaited(_tokenSubscription?.cancel());
  }
}
