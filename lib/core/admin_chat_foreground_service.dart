import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;

import 'admin_config.dart';
import 'admin_session.dart';

const _sessionTokenKey = 'admin_chat_session_token';

class AdminChatForegroundService {
  static bool _initialized = false;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static void initialize() {
    if (!_isAndroid || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'admin_chat_foreground_service',
        channelName: 'خدمة المحادثات',
        channelDescription: 'اتصال خدمة العملاء في الخلفية',
        playSound: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  static Future<void> start(AdminSession session) async {
    if (!_isAndroid) return;
    initialize();
    try {
      await FlutterForegroundTask.saveData(
        key: _sessionTokenKey,
        value: session.token,
      );
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (await FlutterForegroundTask.isRunningService) {
        final result = await FlutterForegroundTask.restartService();
        if (result is ServiceRequestFailure) {
          debugPrint(
              'تعذر إعادة تشغيل خدمة محادثات لوحة التحكم: ${result.error}');
          FlutterForegroundTask.sendDataToTask({'token': session.token});
        }
        return;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: 1978,
        serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: 'GoFast | خدمة العملاء',
        notificationText: 'اتصال المحادثات نشط في الخلفية',
        callback: startAdminChatTask,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('تعذر تشغيل خدمة محادثات لوحة التحكم: ${result.error}');
      }
    } catch (error) {
      debugPrint('تعذر تهيئة خدمة محادثات لوحة التحكم: $error');
    }
  }

  static Future<void> setAppInForeground(bool isForeground) async {
    if (!_isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask({
          'appInForeground': isForeground,
        });
      }
    } catch (error) {
      debugPrint('تعذر تحديث حالة واجهة خدمة المحادثات: $error');
    }
  }
}

@pragma('vm:entry-point')
void startAdminChatTask() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(AdminChatTaskHandler());
}

class AdminChatTaskHandler extends TaskHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _messageNotifications =
      FlutterLocalNotificationsPlugin();
  socket_io_client.Socket? _socket;
  bool _appInForeground = true;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initializeMessageNotifications();
    final token = await FlutterForegroundTask.getData<String>(
      key: _sessionTokenKey,
    );
    if (token != null && token.isNotEmpty) _connect(token);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _socket?.dispose();
    await _audioPlayer.dispose();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final appInForeground = data['appInForeground'];
    if (appInForeground is bool) {
      _appInForeground = appInForeground;
    }
    final token = data['token']?.toString();
    if (token != null && token.isNotEmpty) _connect(token);
  }

  void _connect(String token) {
    _socket?.dispose();
    final socket = socket_io_client.io(
      '$adminApiBaseUrl/admin',
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    socket.on('support:conversation:message', (payload) {
      if (payload is! Map) return;
      final message = payload['message'];
      if (message is Map && message['senderType'] == 'customer') {
        if (!_appInForeground) {
          unawaited(_showMessageNotification(payload, message));
          unawaited(_playReceivedSound());
        }
      }
    });
    socket.on('admin_session_invalidated', (_) {
      socket.dispose();
      if (identical(_socket, socket)) _socket = null;
    });
    socket.connect();
  }

  Future<void> _playReceivedSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/receive.mp3'));
    } catch (error) {
      debugPrint('تعذر تشغيل صوت استقبال المحادثة: $error');
    }
  }

  Future<void> _initializeMessageNotifications() async {
    try {
      await _messageNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final androidNotifications =
          _messageNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidNotifications?.createNotificationChannel(
        const AndroidNotificationChannel(
          'admin_support_messages',
          'رسائل خدمة العملاء',
          description: 'رسائل المحادثات الواردة إلى لوحة التحكم',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
        ),
      );
    } catch (error) {
      debugPrint('تعذر تهيئة إشعارات محادثات لوحة التحكم: $error');
    }
  }

  Future<void> _showMessageNotification(
    Map<dynamic, dynamic> payload,
    Map<dynamic, dynamic> message,
  ) async {
    final body = message['body']?.toString().trim();
    final conversationId = payload['conversationId']?.toString();
    final messageId = message['id'];
    try {
      await _messageNotifications.show(
        id: messageId is num
            ? messageId.toInt()
            : messageId?.toString().hashCode ??
                DateTime.now().millisecondsSinceEpoch,
        title: 'رسالة جديدة من العميل',
        body: body == null || body.isEmpty ? 'وصلتك رسالة جديدة' : body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'admin_support_messages',
            'رسائل خدمة العملاء',
            channelDescription: 'رسائل المحادثات الواردة إلى لوحة التحكم',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: false,
            icon: 'ic_notification',
          ),
        ),
        payload: conversationId,
      );
    } catch (error) {
      debugPrint('تعذر عرض إشعار رسالة المحادثة: $error');
    }
  }
}
