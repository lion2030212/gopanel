import 'package:admin_panel/screens/rider_management_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
            'status': 'completed',
            'arrivedAt': '2026-10-21T10:00:00.000Z',
            'startedAt': '2026-10-21T10:04:00.000Z',
            'distance': '12.5',
            'duration': 24,
            'traceDistanceKm': '12.1',
            'waitSeconds': 120,
            'points': [
              {
                'latitude': 29.99,
                'longitude': 31,
                'capturedAtMs': -120000,
                'phase': 'approach',
              },
              {
                'latitude': 29.995,
                'longitude': 31,
                'capturedAtMs': -60000,
                'phase': 'approach',
              },
              {
                'latitude': 30,
                'longitude': 31,
                'capturedAtMs': 0,
                'speedMps': 8,
              },
              {
                'latitude': 30.005,
                'longitude': 31,
                'capturedAtMs': 60000,
                'speedMps': 0.2,
              },
              {
                'latitude': 30.0051,
                'longitude': 31,
                'capturedAtMs': 180000,
                'speedMps': 0.2,
              },
              {
                'latitude': 30.01,
                'longitude': 31,
                'capturedAtMs': 240000,
                'speedMps': 8,
              },
            ],
            'waitPoints': [
              {
                'latitude': 29.995,
                'longitude': 31,
                'phase': 'pickup',
                'waitSeconds': 60,
                'capturedAtMs': -30000,
              },
              {
                'latitude': 30.005,
                'longitude': 31,
                'phase': 'trip',
                'waitSeconds': 30,
                'capturedAtMs': 90000,
              },
              {
                'latitude': 30.0051,
                'longitude': 31,
                'phase': 'trip',
                'waitSeconds': 30,
                'capturedAtMs': 120000,
              },
            ],
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
    expect(find.text('انتظار التسوية الفعلي'), findsOneWidget);
    expect(find.text('2 دقيقة'), findsOneWidget);
    expect(find.text('12.50 كم'), findsOneWidget);
    expect(find.text('24 دقيقة'), findsOneWidget);
    expect(find.text('من قبول الطلب للوصول'), findsOneWidget);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(
      map.polylines.map((line) => line.polylineId.value).toSet(),
      {'ride-approach-route', 'ride-route'},
    );
    final actualWaitMarkers = map.markers
        .where((marker) => marker.markerId.value.startsWith('route-wait-'))
        .toList();
    expect(
      actualWaitMarkers.map((marker) => marker.markerId.value).toSet(),
      {'route-wait-pickup-0', 'route-wait-trip-1'},
    );
    expect(
      actualWaitMarkers
          .singleWhere((marker) => marker.markerId.value.contains('pickup'))
          .infoWindow
          .snippet,
      '1 دقيقة',
    );
    expect(
      actualWaitMarkers
          .singleWhere((marker) => marker.markerId.value.contains('trip'))
          .infoWindow
          .snippet,
      '1 دقيقة',
    );
    expect(
      map.polylines
          .singleWhere(
            (line) => line.polylineId.value == 'ride-approach-route',
          )
          .color,
      Colors.amber,
    );
  });

  testWidgets('refreshes active ride metrics only while the route tab is open',
      (tester) async {
    final requests = <RequestOptions>[];
    var routeRequestCount = 0;
    final startedAt = DateTime.now().subtract(
      const Duration(minutes: 2, seconds: 10),
    );
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
                'status': 'in_progress',
                'driverName': 'محمد سائق',
                'distance': '18.0',
                'duration': 30,
                'traceDistanceKm': '2.25',
                'startedAt': startedAt.toIso8601String(),
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
          routeRequestCount++;
          handler.resolve(Response(requestOptions: options, data: {
            'success': true,
            'rideId': 41,
            'status': 'in_progress',
            'startedAt': startedAt.toIso8601String(),
            'traceDistanceKm': routeRequestCount == 1 ? '2.25' : '3.75',
            'waitSeconds': 0,
            'points': [
              {
                'latitude': 29.99,
                'longitude': 31,
                'capturedAtMs': 0,
                'phase': 'trip',
              },
              {
                'latitude': 30,
                'longitude': 31,
                'capturedAtMs': 60000,
                'phase': 'trip',
              },
            ],
            'waitPoints': [],
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
    await tester.tap(find.text('الرحلة 41'));
    await tester.pumpAndSettle();

    expect(routeRequestCount, 1);
    expect(find.text('2.25 كم'), findsOneWidget);
    expect(find.textContaining('2 دقيقة'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(routeRequestCount, 2);
    expect(find.text('3.75 كم'), findsOneWidget);

    final accountTab = find.text('الحساب').first;
    await tester.ensureVisible(accountTab);
    await tester.tap(accountTab);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(routeRequestCount, 2);
    expect(
      requests.where((request) => request.path.endsWith('/route')).length,
      2,
    );
  });
}
