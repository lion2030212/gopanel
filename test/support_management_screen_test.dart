import 'dart:async';

import 'package:admin_panel/screens/support_management_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('conversation list shows ride state and quick reply sends',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sentMessages = <String>[];
    final conversations = [
      {
        'id': 11,
        'userId': 8,
        'userRole': 'rider',
        'status': 'active',
        'customerName': 'سامي علي',
        'customerPhone': '0500000000',
        'rideId': 63,
        'rideStatus': 'arriving',
        'unreadCount': 0,
      },
      {
        'id': 12,
        'userId': 9,
        'userRole': 'driver',
        'status': 'active',
        'customerName': 'عمر حسن',
        'customerPhone': '0500000001',
        'rideId': null,
        'rideStatus': null,
        'unreadCount': 0,
      },
    ];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'POST') {
          sentMessages.add(options.data['message'] as String);
          handler.resolve(Response(
            requestOptions: options,
            data: {'success': true},
          ));
          return;
        }
        if (options.path == '/api/admin/support/conversations') {
          handler.resolve(Response(
            requestOptions: options,
            data: {'conversations': conversations},
          ));
          return;
        }
        final id = int.parse(options.path.split('/').last);
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'conversation': conversations.firstWhere(
              (conversation) => conversation['id'] == id,
            ),
            'messages': [],
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: SupportManagementScreen(
        adminToken: 'admin-token',
        onSessionExpired: fail,
        ticketsMode: false,
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('رحلة نشطة #63 · السائق في الطريق'), findsOneWidget);
    expect(find.text('لا توجد رحلة نشطة'), findsOneWidget);

    await tester.tap(find.text('سامي علي').first);
    await tester.pumpAndSettle();

    expect(find.text('رحلة نشطة #63 · السائق في الطريق'), findsNWidgets(2));
    final greeting = find.byKey(const ValueKey('support-quick-reply-1'));
    await tester.tap(greeting);
    await tester.pumpAndSettle();

    expect(sentMessages, ['مرحبًا سامي، كيف يمكنني مساعدتك اليوم؟']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching conversations clears and ignores stale details',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final conversations = [
      {
        'id': 11,
        'userId': 8,
        'userRole': 'rider',
        'status': 'active',
        'customerName': 'سامي علي',
        'customerPhone': '0500000000',
        'unreadCount': 0,
      },
      {
        'id': 12,
        'userId': 9,
        'userRole': 'driver',
        'status': 'active',
        'customerName': 'عمر حسن',
        'customerPhone': '0500000001',
        'unreadCount': 0,
      },
    ];
    final detailGates = {
      11: Completer<void>(),
      12: Completer<void>(),
    };
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/api/admin/support/conversations') {
          handler.resolve(Response(
            requestOptions: options,
            data: {'conversations': conversations},
          ));
          return;
        }
        final id = int.parse(options.path.split('/').last);
        detailGates[id]!.future.then((_) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'conversation': conversations.firstWhere(
                (conversation) => conversation['id'] == id,
              ),
              'messages': [
                {'body': id == 11 ? 'رسالة سامي القديمة' : 'رسالة عمر الجديدة'}
              ],
            },
          ));
        });
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: SupportManagementScreen(
        adminToken: 'admin-token',
        onSessionExpired: fail,
        ticketsMode: false,
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('سامي علي').first);
    await tester.pump();
    await tester.tap(find.text('عمر حسن').first);
    await tester.pump();

    expect(find.text('رسالة سامي القديمة'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    detailGates[12]!.complete();
    await tester.pumpAndSettle();
    expect(find.text('رسالة عمر الجديدة'), findsOneWidget);

    detailGates[11]!.complete();
    await tester.pumpAndSettle();
    expect(find.text('رسالة عمر الجديدة'), findsOneWidget);
    expect(find.text('رسالة سامي القديمة'), findsNothing);

    await tester.tap(find.text('سامي علي').first);
    await tester.pumpAndSettle();
    expect(find.text('رسالة سامي القديمة'), findsOneWidget);
    expect(find.text('رسالة عمر الجديدة'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long conversation opens with its latest message visible',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final conversation = {
      'id': 11,
      'userId': 8,
      'userRole': 'rider',
      'status': 'active',
      'customerName': 'سامي علي',
      'customerPhone': '0500000000',
      'unreadCount': 0,
    };
    final messages = List.generate(
      60,
      (index) => {'body': 'رسالة طويلة $index'},
    );
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/api/admin/support/conversations') {
          handler.resolve(Response(
            requestOptions: options,
            data: {'conversations': [conversation]},
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'conversation': conversation,
            'messages': messages,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: SupportManagementScreen(
        adminToken: 'admin-token',
        onSessionExpired: fail,
        ticketsMode: false,
        client: client,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سامي علي').first);
    await tester.pumpAndSettle();

    expect(find.text('رسالة طويلة 59'), findsOneWidget);
    expect(tester.getRect(find.text('رسالة طويلة 59')).overlaps(
      tester.getRect(find.byType(ListView).at(1)),
    ), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('admin replies show sent, delivered, and read checks in both modes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messages = [
      {
        'id': 101,
        'senderType': 'admin',
        'body': 'رد مرسل',
        'sentAt': '2026-10-19T10:00:00Z',
        'deliveredAt': null,
        'readAt': null,
      },
      {
        'id': 102,
        'senderType': 'admin',
        'body': 'رد مستلم',
        'sentAt': '2026-10-19T10:01:00Z',
        'deliveredAt': '2026-10-19T10:02:00Z',
        'readAt': null,
      },
      {
        'id': 103,
        'senderType': 'admin',
        'body': 'رد مقروء',
        'sentAt': '2026-10-19T10:03:00Z',
        'deliveredAt': '2026-10-19T10:03:30Z',
        'readAt': '2026-10-19T10:04:00Z',
      },
      {
        'id': 104,
        'senderType': 'customer',
        'body': 'رسالة العميل',
        'sentAt': '2026-10-19T10:05:00Z',
        'deliveredAt': '2026-10-19T10:05:30Z',
        'readAt': '2026-10-19T10:06:00Z',
      },
    ];

    for (final ticketsMode in [false, true]) {
      final itemId = ticketsMode ? 44 : 11;
      final item = {
        'id': itemId,
        'userId': 8,
        'userRole': 'rider',
        'status': ticketsMode ? 'open' : 'active',
        'customerName': 'سامي علي',
        'customerPhone': '0500000000',
        'unreadCount': 0,
      };
      final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      client.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final collectionPath = ticketsMode
              ? '/api/admin/support/tickets'
              : '/api/admin/support/conversations';
          if (options.path == collectionPath) {
            handler.resolve(Response(
              requestOptions: options,
              data: {ticketsMode ? 'tickets' : 'conversations': [item]},
            ));
            return;
          }
          handler.resolve(Response(
            requestOptions: options,
            data: {
              ticketsMode ? 'ticket' : 'conversation': {
                ...item,
                'details': 'تفاصيل الشكوى',
                'rideId': null,
              },
              'messages': messages,
            },
          ));
        },
      ));

      await tester.pumpWidget(MaterialApp(
        home: SupportManagementScreen(
          adminToken: 'admin-token',
          onSessionExpired: fail,
          ticketsMode: ticketsMode,
          client: client,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ticketsMode ? 'تذكرة #44' : 'سامي علي').first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.done), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsNWidgets(2));
      expect(find.byTooltip('تم الإرسال'), findsOneWidget);
      expect(find.byTooltip('تم الاستلام'), findsOneWidget);
      expect(find.byTooltip('تم العرض'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
