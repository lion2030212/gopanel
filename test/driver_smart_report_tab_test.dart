import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/widgets/driver_smart_report_tab.dart';

void main() {
  testWidgets('loads the report and requests the selected comparison period',
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
              'driver': {
                'driverId': 4,
                'isOnline': true,
                'driverStatus': 'idle',
                'accountStatus': 'active',
              },
              'current': {
                'range': {
                  'startAt': '2026-10-01 00:00:00',
                  'endAt': '2026-10-24 12:00:00',
                },
                'onlineSeconds': 7200,
                'offers': {
                  'accepted': 8,
                  'rejected': 1,
                  'expired': 1,
                  'cancelled': 0,
                  'pending': 0,
                  'total': 10,
                  'closed': 10,
                  'acceptanceRate': 0.8,
                  'rejectionRate': 0.1,
                  'averageResponseSeconds': 12,
                },
                'rides': {
                  'completed': 7,
                  'cancelled': 1,
                  'completionRate': 0.875,
                  'noShow': 0,
                  'averagePickupDelayMinutes': 5.5,
                  'pickupDelaySample': 7,
                  'averageRideDurationMinutes': 20,
                  'rideDurationSample': 7,
                  'averageRouteDistanceRatio': 1.1,
                  'routeSample': 5,
                },
                'ratings': {'average': 4.8, 'count': 6},
                'reports': {'linkedRiderTickets': 0, 'unresolved': 0},
              },
              'previous': {
                'onlineSeconds': 3600,
                'offers': {'acceptanceRate': 0.7},
                'rides': {'completed': 4},
                'ratings': {'average': 4.5},
              },
              'online': {
                'currentSeconds': 7200,
                'previousSeconds': 3600,
                'coverageStart': '2026-10-01 00:00:00',
                'includesActiveRideTime': true,
              },
              'comparison': {
                'onlineSecondsDelta': 3600,
                'completedRidesDelta': 3,
                'acceptanceRateDelta': 0.1,
              },
              'driverFiledTickets': 1,
              'recommendation': {
                'code': 'insufficient_data',
                'label': 'بيانات غير كافية للحكم',
                'advisory': true,
                'policy': 'provisional-v1',
                'reasons': ['تحتاج التوصية إلى عينات أكبر'],
              },
            },
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverSmartReportTab(
          client: client,
          adminToken: 'admin-token',
          driverId: 4,
          onSessionExpired: fail,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.first.path, '/api/admin/drivers/4/smart-report');
    expect(requests.first.queryParameters['period'], 'month');
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');
    expect(find.text('الملخص التنفيذي'), findsOneWidget);
    expect(find.text('بيانات غير كافية للحكم'), findsOneWidget);
    expect(find.text('2.0 ساعة'), findsOneWidget);

    await tester.tap(find.text('الأسبوع'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['period'], 'week');
    expect(find.text('تشمل الوقت أثناء الرحلة، ولا تعني الجاهزية لطلب جديد'),
        findsOneWidget);

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

    await tester.tap(find.byTooltip('مدة محددة'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
  });
}
