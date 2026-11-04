import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/widgets/rider_smart_report_tab.dart';

void main() {
  testWidgets('loads rider indicators and requests selected report periods',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'report': {
              'rider': {
                'riderId': 12,
                'accountStatus': 'active',
                'isActive': true,
                'createdAt': '2026-01-01',
              },
              'ranges': {'period': 'month'},
              'current': {
                'range': {
                  'startAt': '2026-11-01 00:00:00',
                  'endAt': '2026-11-04 12:00:00',
                },
                'rides': {
                  'completed': 8,
                  'cancelled': 2,
                  'requested': 11,
                  'completionRate': 0.8,
                },
                'ratings': {'count': 4, 'average': 4.5, 'lowCount': 0},
                'support': {'submitted': 2, 'unresolved': 1},
                'financial': {
                  'shortfallDue': 6,
                  'cancellationFeeDue': 8,
                  'adminFineDue': 2,
                  'totalDue': 16,
                },
              },
              'previous': {
                'range': {
                  'startAt': '2026-10-01 00:00:00',
                  'endAt': '2026-10-04 12:00:00',
                },
                'rides': {'completed': 4},
                'ratings': {'count': 2, 'average': 4.0},
              },
              'comparison': {
                'completedRidesDelta': 4,
                'ratingAverageDelta': 0.5,
              },
              'recommendation': {
                'code': 'review',
                'label': 'يحتاج متابعة مالية',
                'advisory': true,
                'policy': 'provisional-v1',
                'reasons': ['يوجد التزام مالي قائم بقيمة 16.00'],
              },
            },
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RiderSmartReportTab(
          client: client,
          adminToken: 'admin-token',
          riderId: 12,
          onSessionExpired: fail,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.first.path, '/api/admin/riders/12/smart-report');
    expect(requests.first.queryParameters['period'], 'month');
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');
    expect(find.text('النقاط الإيجابية'), findsOneWidget);

    await tester.tap(find.text('الأسبوع'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['period'], 'week');

    await tester.tap(find.byTooltip('مدة محددة'));
    await tester.pumpAndSettle();
    expect(find.text('اختر مدة التقرير'), findsOneWidget);
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());
    String dateParameter(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    expect(requests, hasLength(3));
    expect(requests.last.queryParameters['period'], 'custom');
    expect(requests.last.queryParameters['startAt'], dateParameter(today));
    expect(requests.last.queryParameters['endAt'], dateParameter(today));

    await tester.scrollUntilVisible(find.text('مؤشرات تحتاج انتباه'), 400);
    expect(find.text('مؤشرات تحتاج انتباه'), findsOneWidget);
    expect(find.text('يحتاج متابعة مالية'), findsOneWidget);
    expect(find.text('16.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('لا تتوفر نسبة موثوقة للإلغاء إلى الراكب أو الكابتن'),
      400,
    );
    expect(find.text('لا تتوفر نسبة موثوقة للإلغاء إلى الراكب أو الكابتن'),
        findsOneWidget);
  });
}
