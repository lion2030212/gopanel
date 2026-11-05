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
    'gofast_admin_alerts',
    'تنبيهات الإدارة',
    description: 'تنبيهات الأمان والكوبونات والشكاوى الجديدة',
    importance: Importance.high,
  );

  final Dio _client;
  final AdminSession _adminSession;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;
  String? _registeredFid;
  bool _started = false;

  Future<void> start() async {
    if (_started ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _adminSession.role != 'manager') {
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
      _tokenSubscription = messaging.onRegistered.listen((fid) {
        unawaited(_registerFid(fid));
      });
      await messaging.register();
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

  Future<void> _registerFid(String fid) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _registerFidOnce(fid);
        return;
      } on DioException catch (error) {
        debugPrint(
          'تعذر تسجيل جهاز المدير للإشعارات '
          '(محاولة $attempt، HTTP ${error.response?.statusCode ?? 'غير متاح'}): '
          '${error.response?.data ?? error.message}',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  Future<void> _registerFidOnce(String fid) async {
    await _client.post<void>(
      '/api/admin/notifications/device-token',
      data: {'fid': fid},
      options: Options(
        headers: {'Authorization': 'Bearer ${_adminSession.token}'},
      ),
    );
    _registeredFid = fid;
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
            'gofast_admin_alerts',
            'تنبيهات الإدارة',
            channelDescription: 'تنبيهات الأمان والكوبونات والشكاوى الجديدة',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
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
    final fid = _registeredFid;
    if (fid != null) {
      try {
        await _client.delete<void>(
          '/api/admin/notifications/device-token',
          data: {'fid': fid},
          options: Options(
            headers: {'Authorization': 'Bearer ${_adminSession.token}'},
          ),
        );
      } on DioException catch (error) {
        debugPrint('تعذر حذف رمز إشعارات المدير: ${error.message}');
      }
      _registeredFid = null;
    }
    try {
      await FirebaseMessaging.instance.unregister();
    } on FirebaseException catch (error) {
      debugPrint('تعذر إلغاء تسجيل إشعارات المدير: ${error.code}');
    } catch (error) {
      debugPrint('تعذر إلغاء تسجيل إشعارات المدير: $error');
    }
  }

  void dispose() {
    unawaited(_messageSubscription?.cancel());
    unawaited(_tokenSubscription?.cancel());
  }
}
