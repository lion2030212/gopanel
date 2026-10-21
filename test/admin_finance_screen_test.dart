import 'package:admin_panel/screens/admin_finance_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> overviewResponse() => {
        'success': true,
        'totals': {
          'completedTrips': 1240,
          'riderPaid': 12400,
          'driverNet': 9300,
          'commission': 3100,
          'commissionCollected': 2800,
        },
        'comparison': {
          'completedTrips': 1107,
          'riderPaid': 11000,
          'driverNet': 8250,
          'commission': 2750,
          'commissionCollected': 2500,
        },
        'growth': {'completedTrips': 12, 'commission': 12.7},
        'chart': {
          'period': '24h',
          'buckets': [
            {
              'bucket': '2026-10-21 08:00:00',
              'completed': 5,
              'cancelled': 1,
              'all': 7,
            },
          ],
        },
      };

  Map<String, dynamic> reportsResponse() => {
        'success': true,
        'totals': {
          'riderPaid': 12400,
          'driverNet': 9300,
          'commission': 3100,
          'commissionCollected': 2800,
          'riderWalletAdded': 400,
          'riderWalletDeducted': 75,
          'cancellationFeesCollected': 125,
        },
        'riderWalletAdjustments': {
          'items': [
            {
              'id': 1,
              'direction': 'credit',
              'amount': 400,
              'riderName': 'أحمد',
              'description': 'دعم رصيد',
              'adminId': 'staff-3',
              'createdAt': '2026-10-21T08:00:00.000Z',
            },
          ],
          'page': 1,
          'limit': 20,
          'total': 1,
        },
        'commissionEvents': [
          {
            'id': 2,
            'eventType': 'debt_recovery',
            'collectedAmount': 100,
            'debtAmount': 0,
            'createdAt': '2026-10-21T08:00:00.000Z',
          },
        ],
      };

  Dio clientFor(
    List<RequestOptions> requests, {
    bool fail = false,
  }) {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (fail) {
          handler.reject(DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 500,
            ),
          ));
          return;
        }
        final data = options.path.endsWith('/overview')
            ? overviewResponse()
            : reportsResponse();
        handler.resolve(Response(
          requestOptions: options,
          data: data,
          statusCode: 200,
        ));
      },
    ));
    return client;
  }

  testWidgets('loads overview metrics, interactive chart, and wallet reports',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = clientFor(requests);

    await tester.pumpWidget(MaterialApp(
      home: AdminFinanceScreen(
        adminToken: 'manager-token',
        onSessionExpired: (_) {},
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('الإدارة المالية'), findsOneWidget);
    expect(find.text('الرحلات المكتملة'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);
    expect(find.textContaining('+12.0%'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('حركة الطلب'), findsOneWidget);
    expect(requests, hasLength(2));
    expect(requests.first.headers['Authorization'], 'Bearer manager-token');

    await tester.tap(find.text('التقارير المالية'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('إجمالي مدفوعات الركاب'), findsOneWidget);
    expect(find.text('حركات محفظة الركاب'), findsOneWidget);
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.textContaining('staff-3'), findsOneWidget);
    expect(find.text('سداد دين من محفظة السائق'), findsOneWidget);
  });

  testWidgets('period selection reloads both financial endpoints', (tester) async {
    final requests = <RequestOptions>[];
    final client = clientFor(requests);

    await tester.pumpWidget(MaterialApp(
      home: AdminFinanceScreen(
        adminToken: 'manager-token',
        onSessionExpired: (_) {},
        client: client,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هذا الأسبوع'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(4));
    expect(requests[2].queryParameters['period'], 'week');
    expect(requests[3].queryParameters['period'], 'week');
  });

  testWidgets('finance dashboard lays out on a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <RequestOptions>[];
    final client = clientFor(requests);

    await tester.pumpWidget(MaterialApp(
      home: AdminFinanceScreen(
        adminToken: 'manager-token',
        onSessionExpired: (_) {},
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byTooltip('تحديث التقارير')).dy,
      greaterThan(tester.getBottomLeft(find.byType(AppBar)).dy),
    );
    expect(find.text('الرحلات المكتملة'), findsOneWidget);
  });

  testWidgets('shows recoverable error when finance APIs fail', (tester) async {
    final requests = <RequestOptions>[];
    final client = clientFor(requests, fail: true);
    await tester.pumpWidget(MaterialApp(
      home: AdminFinanceScreen(
        adminToken: 'manager-token',
        onSessionExpired: (_) {},
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل التقارير المالية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}