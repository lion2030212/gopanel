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
}
