import 'package:admin_panel/widgets/staff_smart_report_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads staff metrics and requests selected comparison periods',
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
              'staff': {
                'staffId': 7,
                'fullName': 'ليلى حسن',
                'jobTitle': 'موظف',
                'accountStatus': 'active',
              },
              'current': {
                'range': {
                  'startAt': '2026-11-01 00:00:00',
                  'endAt': '2026-11-04 10:00:00',
                },
                'conversations': {'closed': 5, 'replies': 6},
                'tickets': {
                  'resolved': 2,
                  'replies': 3,
                  'averageResolutionMinutes': 18,
                  'categories': {'payment': 2},
                },
                'ratings': {'average': 4.5, 'count': 2},
                'sessions': {
                  'durationSeconds': 7200,
                  'count': 1,
                  'coverageStart': '2026-10-10 08:00:00',
                },
                'notifications': {
                  'campaigns': 2,
                  'acceptedRecipients': 8,
                  'acceptedDevices': 10,
                  'readNotifications': 6,
                  'failedRecipients': 1,
                },
              },
              'previous': {
                'conversations': {'closed': 3, 'replies': 2},
                'tickets': {
                  'resolved': 4,
                  'replies': 1,
                  'averageResolutionMinutes': 24,
                  'categories': {'technical': 2},
                },
                'ratings': {'average': 3.0, 'count': 1},
                'sessions': {'durationSeconds': 3600, 'count': 1},
                'notifications': {
                  'campaigns': 1,
                  'acceptedRecipients': 3,
                  'acceptedDevices': 4,
                  'readNotifications': 2,
                  'failedRecipients': 0,
                },
              },
              'advisory': {
                'label': 'ملخص اتجاهات الفترة',
                'summary': 'تُظهر المؤشرات حجم العمل والتغذية الراجعة المسجلة، ولا تمثل حكمًا منفردًا على الأداء.',
                'reasons': ['المحادثات المغلقة: 5 مقابل 3 في الفترة السابقة.'],
              },
              'comparison': {
                'closedConversationsDelta': 2,
                'resolvedTicketsDelta': -2,
                'repliesDelta': 5,
                'ratingsCountDelta': 1,
                'averageRatingDelta': 1.5,
                'sessionDurationSecondsDelta': 3600,
                'campaignsDelta': 1,
              },
            },
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffSmartReportTab(
          client: client,
          adminToken: 'admin-token',
          staffId: 7,
          onSessionExpired: fail,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.first.path, '/api/admin/staff/7/smart-report');
    expect(requests.first.queryParameters['period'], 'day');
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');
    expect(find.text('الملخص التنفيذي والتوصية'), findsOneWidget);
    expect(find.text('ملخص اتجاهات الفترة'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('مدة التواجد التقديرية والمقارنة'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('2 ساعة و 0 دقيقة'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('النقاط الإيجابية'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('النقاط الإيجابية'), findsOneWidget);
    expect(find.text('محادثات مغلقة'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('السابقة 3 · التغير +2'), findsOneWidget);
    expect(find.text('متوسط التقييم'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('الملاحظات التشغيلية'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('الملاحظات التشغيلية'), findsOneWidget);
    expect(find.text('الردود على المحادثات'), findsOneWidget);
    expect(find.textContaining('الدفع: 2'), findsOneWidget);
    expect(find.text('الأجهزة التي قبلت الإشعار'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الأسبوع'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['period'], 'week');

    await tester.tap(find.text('اليوم'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['period'], 'day');

    await tester.tap(find.byTooltip('مدة محددة'));
    await tester.pumpAndSettle();
    expect(find.text('اختر مدة التقرير'), findsOneWidget);
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['period'], 'custom');
    expect(requests.last.queryParameters['startAt'], isNotNull);
    expect(requests.last.queryParameters['endAt'], isNotNull);
  });
}