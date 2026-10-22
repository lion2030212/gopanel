import 'package:admin_panel/screens/rider_management_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searches rider rides and fetches GPS only after selection',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.path == '/api/admin/riders' && options.method == 'GET') {
          handler.resolve(Response(requestOptions: options, data: {
            'riders': [
              {
                'riderId': 12,
                'fullName': 'أحمد راكب',
                'phone': '+201000000000'
              },
            ],
            'total': 1,
          }));
          return;
        }
        if (options.path == '/api/admin/riders/12' && options.method == 'GET') {
          handler.resolve(Response(requestOptions: options, data: {
            'profile': {
              'riderId': 12,
              'fullName': 'أحمد راكب',
              'phone': '+201000000000',
            },
            'rides': [
              {
                'rideId': 41,
                'status': 'completed',
                'driverName': 'محمد سائق',
                'driverPhone': '+201011111111',
                'distance': '12.5',
                'duration': 24,
                'arrivedAt': '2026-10-21T10:00:00.000Z',
                'startedAt': '2026-10-21T10:04:00.000Z',
              },
              {
                'rideId': 42,
                'status': 'completed',
                'driverName': 'علي سائق',
                'driverPhone': '+201022222222',
              },
            ],
            'wallet': {'transactions': []},
            'ratings': [],
            'offers': [],
            'cancellationPolicies': [],
            'financialRecords': {},
            'coupons': {},
            'notifications': [],
            'devices': [],
            'location': null,
            'chatMessages': [],
          }));
          return;
        }
        if (options.path == '/api/admin/riders/12/rides/41/route') {
          handler.resolve(Response(requestOptions: options, data: {
            'success': true,
            'rideId': 41,
            'points': [],
          }));
          return;
        }
        handler.resolve(
            Response(requestOptions: options, data: {'success': true}));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RiderManagementScreen(
          adminToken: 'admin-token',
          onSessionExpired: (_) {},
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أحمد راكب'));
    await tester.pumpAndSettle();

    final routeTab = find.text('مسار الرحلة');
    await tester.ensureVisible(routeTab);
    await tester.tap(routeTab);
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsOneWidget);
    expect(find.text('الرحلة 42'), findsOneWidget);
    expect(
      requests.any((request) => request.path.endsWith('/route')),
      isFalse,
    );

    await tester.enterText(
      find.byType(TextField).last,
      'محمد سائق',
    );
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsOneWidget);
    expect(find.text('الرحلة 42'), findsNothing);

    await tester.tap(find.text('الرحلة 41'));
    await tester.pumpAndSettle();
    expect(
      requests.any(
          (request) => request.path == '/api/admin/riders/12/rides/41/route'),
      isTrue,
    );
    expect(find.text('لا توجد نقاط GPS مسجلة لهذه الرحلة'), findsOneWidget);
  });
}
