// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:admin_panel/core/driver_marker_presentation.dart';
import 'package:admin_panel/core/ride_route_presentation.dart';
import 'package:admin_panel/screens/notification_screen.dart';
import 'package:admin_panel/screens/coupon_management_screen.dart';
import 'package:admin_panel/screens/driver_management_screen.dart';
import 'package:admin_panel/screens/rider_management_screen.dart';
import 'package:admin_panel/screens/ride_history_screen.dart';
import 'package:admin_panel/screens/staff_management_screen.dart';
import 'package:admin_panel/widgets/admin_drawer.dart';
import 'package:admin_panel/widgets/dashboard_navigation.dart';
import 'package:admin_panel/widgets/map_marker_details_card.dart';
import 'package:admin_panel/widgets/map_stats_overlay.dart';
import 'package:admin_panel/widgets/support_history_tab.dart';
import 'package:admin_panel/screens/support_management_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('map stats show live counts in a vertical circular stack',
      (tester) async {
    var onlineDrivers = 3;

    Widget buildOverlay() => MaterialApp(
          home: Scaffold(
            body: MapStatsOverlay(
              onlineDrivers: onlineDrivers,
              offlineDrivers: 2,
              riders: 7,
              activeRides: 4,
            ),
          ),
        );

    await tester.pumpWidget(buildOverlay());

    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    final labels = [
      'سائقون أونلاين',
      'سائقون أوفلاين',
      'ركاب بالخريطة',
      'رحلات نشطة',
    ];
    final labelTops =
        labels.map((label) => tester.getTopLeft(find.text(label)).dy).toList();
    expect(labelTops, orderedEquals([...labelTops]..sort()));

    onlineDrivers = 8;
    await tester.pumpWidget(buildOverlay());
    expect(find.text('8'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('coupon management filters validity and creates a public coupon',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.method == 'POST') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {'success': true, 'couponId': 41},
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'coupons': [
              {
                'couponId': 4,
                'code': 'GOFAST10',
                'riderId': null,
                'discountPercent': '10.00',
                'startsAt': '2026-10-13 00:00:00',
                'expiresAt': '2026-12-01 23:59:59',
                'isActive': 1,
                'reservationCount': 0,
                'redemptionCount': 0,
              },
            ],
            'total': 1,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CouponManagementScreen(
          adminToken: 'admin-token',
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('إدارة الكوبونات'), findsOneWidget);
    expect(find.text('GOFAST10'), findsOneWidget);
    expect(find.textContaining('جميع الركاب'), findsOneWidget);
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');
    final addButtonWrap = find.ancestor(
      of: find.text('إضافة كوبون'),
      matching: find.byType(Wrap),
    );
    expect(addButtonWrap, findsOneWidget);
    expect(
      find.descendant(
        of: addButtonWrap,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);

    await tester.tap(find.text('مستخدم'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['status'], 'used');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسبوع').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['startAt'], isNotNull);
    expect(requests.last.queryParameters['endAt'], isNotNull);

    await tester.tap(find.text('إضافة كوبون'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    final beneficiaryOption = tester.widget<Text>(
      find.text('جميع الركاب').last,
    );
    expect(beneficiaryOption.textAlign, TextAlign.end);
    await tester.tap(find.text('جميع الركاب').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'NEW2026');
    await tester.enterText(find.byType(TextFormField).at(1), '20');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final createRequest =
        requests.firstWhere((request) => request.method == 'POST');
    expect(createRequest.data['code'], 'NEW2026');
    expect(createRequest.data['riderId'], isNull);
    expect(createRequest.data['discountPercent'], '20');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'rider coupon tab filters records and limits coupon actions to owner',
      (tester) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    final previousMonth = DateTime(now.year, now.month - 1, 15);
    var currentCouponActive = true;
    var currentCouponCode = 'OWN-CURRENT';
    var currentCouponDiscount = '10.00';
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.path == '/api/admin/riders' && options.method == 'GET') {
          handler.resolve(Response(requestOptions: options, data: {
            'riders': [
              {'riderId': 12, 'fullName': 'أحمد راكب'},
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
              'isActive': 1,
              'accountStatus': 'active',
            },
            'rides': [],
            'wallet': {'balance': '0.00', 'transactions': []},
            'ratings': [],
            'financialRecords': {},
            'coupons': {
              'assigned': [
                {
                  'couponId': 21,
                  'riderId': 12,
                  'code': currentCouponCode,
                  'discountPercent': currentCouponDiscount,
                  'startsAt': monthStart.toIso8601String(),
                  'expiresAt': monthEnd.toIso8601String(),
                  'isActive': currentCouponActive ? 1 : 0,
                  'reservationCount': 0,
                  'redemptionCount': 0,
                },
                {
                  'couponId': 22,
                  'riderId': 12,
                  'code': 'OWN-DISABLED',
                  'discountPercent': '15.00',
                  'startsAt': monthStart.toIso8601String(),
                  'expiresAt': monthEnd.toIso8601String(),
                  'isActive': 0,
                  'reservationCount': 1,
                  'redemptionCount': 0,
                },
                {
                  'couponId': 23,
                  'riderId': 12,
                  'code': 'OWN-OLD',
                  'discountPercent': '5.00',
                  'startsAt': previousMonth.toIso8601String(),
                  'expiresAt': DateTime(now.year, now.month, 1)
                      .subtract(const Duration(seconds: 1))
                      .toIso8601String(),
                  'isActive': 1,
                  'reservationCount': 0,
                  'redemptionCount': 0,
                },
              ],
              'reservations': [
                {
                  'id': 31,
                  'couponId': 22,
                  'couponCode': 'OWN-DISABLED',
                  'rideId': 55,
                  'reservedAt': now.toIso8601String(),
                },
              ],
              'redemptions': [
                {
                  'id': 41,
                  'couponId': 99,
                  'couponCode': 'PUBLIC-USED',
                  'couponRiderId': null,
                  'rideId': 56,
                  'redeemedAt': now.toIso8601String(),
                  'isActive': 1,
                  'startsAt': monthStart.toIso8601String(),
                  'expiresAt': monthEnd.toIso8601String(),
                },
                {
                  'id': 42,
                  'couponId': 98,
                  'couponCode': 'PUBLIC-OLD',
                  'couponRiderId': null,
                  'rideId': 57,
                  'redeemedAt': previousMonth.toIso8601String(),
                },
              ],
            },
            'notifications': [],
            'offers': [],
            'cancellationPolicies': [],
            'devices': [],
            'location': null,
            'chatMessages': [],
            'locationPoints': [],
          }));
          return;
        }
        if (options.path == '/api/admin/coupons/21' &&
            options.method == 'PATCH') {
          if (options.data.containsKey('isActive')) {
            currentCouponActive = options.data['isActive'] as bool;
          } else {
            currentCouponCode = options.data['code'] as String;
            currentCouponDiscount = options.data['discountPercent'] as String;
          }
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {'success': true},
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RiderManagementScreen(
          adminToken: 'admin-token',
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أحمد راكب'));
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(IconButton, Icons.arrow_back), findsOneWidget);
    expect(find.text('الكوبونات'), findsOneWidget);
    final couponsTab = find.byType(Tab).at(5);
    await tester.ensureVisible(couponsTab);
    await tester.tap(couponsTab);
    await tester.pumpAndSettle();

    expect(find.text('OWN-CURRENT'), findsOneWidget);
    expect(find.text('OWN-OLD'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('OWN-DISABLED'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('OWN-DISABLED'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PUBLIC-USED'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PUBLIC-USED'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PUBLIC-OLD'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PUBLIC-OLD'), findsOneWidget);
    final publicCard = find.ancestor(
      of: find.text('PUBLIC-USED'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
          of: publicCard, matching: find.byTooltip('تعديل الكوبون')),
      findsNothing,
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('rider-coupon-21')),
      matching: find.byTooltip('تعديل الكوبون'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'OWN-EDITED');
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    final editRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' && request.path == '/api/admin/coupons/21');
    expect(editRequest.data['code'], 'OWN-EDITED');
    expect(editRequest.data['riderId'], 12);
    expect(editRequest.data['discountPercent'], '30');
    expect(find.text('OWN-EDITED'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('OWN-EDITED'), findsOneWidget);
    expect(find.text('OWN-OLD'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('PUBLIC-USED'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PUBLIC-USED'), findsOneWidget);
    expect(find.text('PUBLIC-OLD'), findsNothing);

    await tester.tap(find.byTooltip('تعطيل الكوبون').first);
    await tester.pumpAndSettle();
    final toggleRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' && request.path == '/api/admin/coupons/21');
    expect(toggleRequest.data, {'isActive': false});
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('الكوبونات المعطّلة'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('rider-coupon-22')),
      matching: find.byTooltip('حذف الكوبون'),
    ));
    await tester.pumpAndSettle();
    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${now.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${now.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق').last);
    await tester.pumpAndSettle();
    expect(find.text('OWN-EDITED'), findsOneWidget);
    expect(find.text('PUBLIC-USED'), findsOneWidget);
    expect(find.text('PUBLIC-OLD'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard home route responds to live marker updates',
      (tester) async {
    final markerStatus = ValueNotifier('متصل');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          homeBuilder: (_) => ValueListenableBuilder<String>(
            valueListenable: markerStatus,
            builder: (_, status, __) => Text(status),
          ),
          routes: const {},
          onRouteChanged: (_) {},
        ),
      ),
    ));

    expect(find.text('متصل'), findsOneWidget);
    markerStatus.value = 'في رحلة';
    await tester.pump();
    expect(find.text('في رحلة'), findsOneWidget);
  });

  testWidgets('support history scopes owner and applies period filters',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final data = options.path == '/api/admin/support/history/tickets'
            ? {
                'tickets': [
                  {
                    'id': 44,
                    'userId': 12,
                    'userRole': 'driver',
                    'customerName': 'سائق الاختبار',
                    'customerPhone': '0500000000',
                    'supportEmployeeName': 'موظف الدعم',
                    'supportEmployeePhone': '0550000000',
                    'supportEmployeeRole': 'employee',
                    'category': 'other',
                    'status': 'open',
                    'details': 'نص البلاغ',
                    'createdAt': '2026-10-02 09:00:00',
                  },
                ],
                'total': 1,
              }
            : {
                'ticket': {
                  'id': 44,
                  'userRole': 'driver',
                  'customerName': 'سائق الاختبار',
                  'customerPhone': '0500000000',
                  'supportEmployeeName': 'موظف الدعم',
                  'supportEmployeePhone': '0550000000',
                  'supportEmployeeRole': 'employee',
                  'details': 'نص البلاغ',
                },
                'messages': [],
              };
        handler.resolve(Response(requestOptions: options, data: data));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupportHistoryTab(
          client: client,
          adminToken: 'admin-token',
          userId: 12,
          userRole: 'driver',
          ticketsMode: true,
          onSessionExpired: fail,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('شكوى #44'), findsOneWidget);
    expect(
      find.text('صاحب السجل: سائق الاختبار · 0500000000 · سائق'),
      findsOneWidget,
    );
    expect(
      find.text('موظف الدعم: موظف الدعم · 0550000000 · موظف'),
      findsOneWidget,
    );
    expect(requests.first.queryParameters['userId'], 12);
    expect(requests.first.queryParameters['userRole'], 'driver');
    expect(requests.first.queryParameters.containsKey('startAt'), isFalse);
    expect(
      tester.widget<ListTile>(find.byType(ListTile).first).tileColor,
      isNull,
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسبوع').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['startAt'], isNotNull);
    expect(requests.last.queryParameters['endAt'], isNotNull);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    final monthRange = requests.last.queryParameters;
    expect(DateTime.parse(monthRange['startAt'] as String).day, 1);
    expect(DateTime.parse(monthRange['endAt'] as String).day, 1);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    final customRange = requests.last.queryParameters;
    final customStart = DateTime.parse(customRange['startAt'] as String);
    final customEnd = DateTime.parse(customRange['endAt'] as String);
    expect(customEnd.difference(customStart), const Duration(days: 1));

    await tester.tap(find.text('شكوى #44'));
    await tester.pumpAndSettle();
    expect(find.text('نص البلاغ'), findsOneWidget);
    expect(requests.last.path, '/api/admin/support/tickets/44');
    expect(find.byType(AlertDialog), findsNothing);
    final detailDirection = tester.widget<Directionality>(
      find.byKey(const ValueKey('support-history-detail-44')),
    );
    expect(detailDirection.textDirection, TextDirection.rtl);

    await tester.tap(find.text('شكوى #44'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-history-detail-44')),
      findsNothing,
    );
  });

  testWidgets(
      'support conversation history shows rider identity without an employee',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.path == '/api/admin/support/history/conversations'
            ? {
                'conversations': [
                  {
                    'id': 19,
                    'userId': 12,
                    'userRole': 'rider',
                    'customerName': 'راكب الاختبار',
                    'customerPhone': '0511111111',
                    'status': 'closed',
                    'createdAt': '2026-10-02 09:00:00',
                  },
                ],
                'total': 1,
              }
            : {
                'conversation': {
                  'id': 19,
                  'userRole': 'rider',
                  'customerName': 'راكب الاختبار',
                  'customerPhone': '0511111111',
                },
                'messages': [],
              };
        handler.resolve(Response(requestOptions: options, data: data));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupportHistoryTab(
          client: client,
          adminToken: 'admin-token',
          userId: 12,
          userRole: 'rider',
          ticketsMode: false,
          onSessionExpired: fail,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const riderIdentity = 'صاحب السجل: راكب الاختبار · 0511111111 · راكب';
    expect(find.text(riderIdentity), findsOneWidget);
    expect(find.textContaining('موظف الدعم:'), findsNothing);

    await tester.tap(find.text('محادثة خدمة العملاء').first);
    await tester.pumpAndSettle();
    expect(find.text(riderIdentity), findsNWidgets(2));
    expect(find.textContaining('موظف الدعم:'), findsNothing);
  });

  testWidgets('general support list highlights driver-origin rows only',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'tickets': [
              {
                'id': 44,
                'userId': 12,
                'userRole': 'driver',
                'category': 'other',
                'status': 'open',
                'details': 'شكوى سائق',
              },
              {
                'id': 45,
                'userId': 13,
                'userRole': 'rider',
                'category': 'other',
                'status': 'open',
                'details': 'شكوى راكب',
              },
            ],
            'total': 2,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: SupportManagementScreen(
        adminToken: 'admin-token',
        onSessionExpired: fail,
        ticketsMode: true,
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    final driverTile = tester.widget<ListTile>(find.ancestor(
      of: find.text('تذكرة #44'),
      matching: find.byType(ListTile),
    ));
    final riderTile = tester.widget<ListTile>(find.ancestor(
      of: find.text('تذكرة #45'),
      matching: find.byType(ListTile),
    ));
    expect(driverTile.tileColor, Colors.yellow.shade100);
    expect(riderTile.tileColor, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('support shortcuts stay visible and show unread counts',
      (tester) async {
    final navigationKey = GlobalKey<DashboardNavigationState>();
    final openedDestinations = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          key: navigationKey,
          homeBuilder: (_) => const Text('خريطة السائقين'),
          routes: {
            DashboardNavigation.notificationsRoute: (_) =>
                const Text('التنبيهات'),
          },
          onRouteChanged: (_) {},
          unreadConversationCount: 6,
          unreadTicketCount: 3,
          onOpenConversations: () => openedDestinations.add('conversations'),
          onOpenTickets: () => openedDestinations.add('tickets'),
        ),
      ),
    ));

    expect(find.byTooltip('إدارة المحادثات'), findsOneWidget);
    expect(find.byTooltip('إدارة الشكاوى'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byTooltip('إدارة المحادثات'));
    expect(openedDestinations, ['conversations']);

    navigationKey.currentState!
        .pushNamed(DashboardNavigation.notificationsRoute);
    await tester.pumpAndSettle();
    expect(find.byTooltip('رجوع'), findsOneWidget);
    expect(find.byTooltip('إدارة المحادثات'), findsOneWidget);
    expect(find.byTooltip('إدارة الشكاوى'), findsOneWidget);
    await tester.tap(find.byTooltip('إدارة الشكاوى'));
    expect(openedDestinations, ['conversations', 'tickets']);
  });

  testWidgets('dashboard reopens an existing support route without stacking',
      (tester) async {
    final navigationKey = GlobalKey<DashboardNavigationState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          key: navigationKey,
          homeBuilder: (_) => const Text('خريطة السائقين'),
          routes: {
            DashboardNavigation.supportConversationsRoute: (_) =>
                const Text('قائمة المحادثات'),
            '/support/conversations/details': (_) =>
                const Text('تفاصيل المحادثة'),
          },
          onRouteChanged: (_) {},
        ),
      ),
    ));

    navigationKey.currentState!
        .pushNamed(DashboardNavigation.supportConversationsRoute);
    await tester.pumpAndSettle();
    navigationKey.currentState!.pushNamed('/support/conversations/details');
    await tester.pumpAndSettle();
    navigationKey.currentState!
        .openNamed(DashboardNavigation.supportConversationsRoute);
    await tester.pumpAndSettle();

    expect(find.text('قائمة المحادثات'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('خريطة السائقين'), findsOneWidget);
  });

  test('driver marker presentation creates distinct colored car images',
      () async {
    final offline = DriverMarkerPresentation.fromDriver(
      isOnline: false,
      status: 'idle',
    );
    final online = DriverMarkerPresentation.fromDriver(
      isOnline: true,
      status: 'idle',
    );
    final active = DriverMarkerPresentation.fromDriver(
      isOnline: true,
      status: 'active',
    );

    expect(offline.label, 'غير متصل');
    expect(offline.color, DriverMarkerPresentation.offlineColor);
    expect(online.label, 'متصل');
    expect(online.color, DriverMarkerPresentation.onlineColor);
    expect(active.label, 'في رحلة');
    expect(active.color, DriverMarkerPresentation.activeRideColor);
    expect(DriverMarkerPresentation.firstName('  سارة أحمد  '), 'سارة');
    expect(DriverMarkerPresentation.firstName(''), '');
    expect(
      DriverMarkerPresentation.preserveIdentityValue(null, 'سارة'),
      'سارة',
    );
    expect(
      DriverMarkerPresentation.preserveIdentityValue('', '+201000000008'),
      '+201000000008',
    );
    expect(
      DriverMarkerPresentation.preserveIdentityValue('منى', 'سارة'),
      'منى',
    );
    final driverInfo = DriverMarkerPresentation.infoWindow(
      role: 'السائق',
      id: 8,
      fullName: 'سارة أحمد',
      phone: '+201000000008',
      status: active.label,
      lastUpdated: '2026-10-19 12:00:00',
    );
    expect(driverInfo.title, 'السائق سارة');
    expect(
      driverInfo.snippet,
      'الجوال: +201000000008\nالحالة: في رحلة\nآخر تحديث: 2026-10-19 12:00:00',
    );

    final offlineIcon =
        await DriverMarkerPresentation.driverMarkerIcon(offline.color);
    final onlineIcon =
        await DriverMarkerPresentation.driverMarkerIcon(online.color);
    final activeIcon =
        await DriverMarkerPresentation.driverMarkerIcon(active.color);

    expect(offlineIcon, isA<BytesMapBitmap>());
    expect(onlineIcon, isA<BytesMapBitmap>());
    expect(activeIcon, isA<BytesMapBitmap>());
    expect(offlineIcon, isNot(onlineIcon));
    expect(onlineIcon, isNot(activeIcon));
  });

  test('rider marker color changes while a ride is active', () async {
    final online = DriverMarkerPresentation.fromRider(hasActiveRide: false);
    final active = DriverMarkerPresentation.fromRider(hasActiveRide: true);

    expect(online.label, 'متصل');
    expect(online.color, DriverMarkerPresentation.riderOnlineColor);
    expect(active.label, 'في رحلة');
    expect(active.color, DriverMarkerPresentation.riderActiveRideColor);
    final riderInfo = DriverMarkerPresentation.infoWindow(
      role: 'الراكب',
      id: 12,
      fullName: 'منى حسن',
      phone: '+201000000012',
      status: online.label,
      lastUpdated: '2026-10-19 12:00:00',
    );
    expect(riderInfo.title, 'الراكب منى');
    expect(
      riderInfo.snippet,
      'الجوال: +201000000012\nالحالة: متصل\nآخر تحديث: 2026-10-19 12:00:00',
    );
    expect(
      await DriverMarkerPresentation.markerIcon(online.color),
      isA<BytesMapBitmap>(),
    );
    expect(
      await DriverMarkerPresentation.markerIcon(active.color),
      isA<BytesMapBitmap>(),
    );
  });

  testWidgets('map marker details card shows Arabic fields and dismisses',
      (tester) async {
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MapMarkerDetailsCard(
          role: 'السائق',
          name: 'سارة أحمد',
          phone: '+201000000008',
          status: 'في رحلة',
          updatedAt: '2026-10-19 12:00:00',
          statusColor: DriverMarkerPresentation.activeRideColor,
          onDismiss: () => dismissed = true,
        ),
      ),
    ));

    expect(find.text('السائق'), findsOneWidget);
    expect(find.text('الاسم'), findsOneWidget);
    expect(find.text('سارة أحمد'), findsOneWidget);
    expect(find.text('الجوال'), findsOneWidget);
    expect(find.text('+201000000008'), findsOneWidget);
    expect(find.text('الحالة'), findsOneWidget);
    expect(find.text('في رحلة'), findsOneWidget);
    expect(find.text('آخر تحديث'), findsOneWidget);
    expect(find.text('2026-10-19 12:00:00'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Directionality &&
            widget.textDirection == TextDirection.rtl,
      ),
      findsWidgets,
    );

    await tester.tap(find.byTooltip('إغلاق'));
    expect(dismissed, isTrue);
  });

  test('active ride route colors are stable and distinct', () {
    final colors = RideRoutePresentation.colorsForRideIds([41, 12, 27, 41]);

    expect(colors.keys.toList(), [12, 27, 41]);
    expect(colors.values.toSet(), hasLength(3));
    expect(
      colors,
      RideRoutePresentation.colorsForRideIds([41, 27, 12]),
    );
  });

  test('route connectors require recent endpoint locations', () {
    final now = DateTime.utc(2026, 10, 4, 12);

    expect(
      RideRoutePresentation.hasFreshLocation(
        now.subtract(const Duration(seconds: 90)),
        maxAgeSeconds: 120,
        now: now,
      ),
      isTrue,
    );
    expect(
      RideRoutePresentation.hasFreshLocation(
        now.subtract(const Duration(seconds: 121)),
        maxAgeSeconds: 120,
        now: now,
      ),
      isFalse,
    );
    expect(
      RideRoutePresentation.hasFreshLocation(
        now.subtract(const Duration(milliseconds: 120001)),
        maxAgeSeconds: 120,
        now: now,
      ),
      isFalse,
    );
    expect(
      RideRoutePresentation.hasFreshLocation(null,
          maxAgeSeconds: 120, now: now),
      isFalse,
    );
  });

  testWidgets('dashboard back button pops one internal page at a time',
      (tester) async {
    final navigationKey = GlobalKey<DashboardNavigationState>();
    final routeChanges = <String>[];
    var homeMountCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          key: navigationKey,
          homeBuilder: (_) {
            return _HomeProbe(onMount: () => homeMountCount++);
          },
          routes: {
            DashboardNavigation.notificationsRoute: (_) =>
                const Text('التنبيهات'),
            '/notifications/details': (_) => const Text('تفاصيل التنبيه'),
          },
          onRouteChanged: routeChanges.add,
        ),
      ),
    ));

    expect(find.text('خريطة السائقين'), findsOneWidget);
    expect(find.byTooltip('رجوع'), findsNothing);

    navigationKey.currentState!
        .pushNamed(DashboardNavigation.notificationsRoute);
    await tester.pumpAndSettle();
    expect(find.text('التنبيهات'), findsOneWidget);
    expect(find.byTooltip('رجوع'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);

    navigationKey.currentState!.pushNamed('/notifications/details');
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل التنبيه'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('التنبيهات'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('خريطة السائقين'), findsOneWidget);
    expect(find.byTooltip('رجوع'), findsNothing);
    expect(homeMountCount, 1);
    expect(routeChanges, [
      DashboardNavigation.notificationsRoute,
      '/notifications/details',
      DashboardNavigation.notificationsRoute,
      DashboardNavigation.homeRoute,
    ]);
  });

  testWidgets('dashboard back unwinds screen details before prior routes',
      (tester) async {
    final navigationKey = GlobalKey<DashboardNavigationState>();
    final driverClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    driverClient.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/api/admin/drivers') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'drivers': [
                {
                  'driverId': 4,
                  'fullName': 'محمد علي',
                  'phone': '+201000000000',
                  'isActive': 1,
                  'accountStatus': 'active',
                },
              ],
              'total': 1,
            },
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'profile': {
              'driverId': 4,
              'fullName': 'محمد علي',
              'phone': '+201000000000',
              'isActive': 1,
              'accountStatus': 'active',
            },
            'rides': [],
            'wallet': {'balance': '0.00', 'transactions': []},
            'ratings': [],
            'financialRecords': {'appLedger': [], 'shortfalls': []},
          },
        ));
      },
    ));
    final rideClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    rideClient.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final ride = {
          'rideId': 7,
          'status': 'completed',
          'riderName': 'محمد راكب',
          'canReverseSettlement': false,
        };
        handler.resolve(Response(
          requestOptions: options,
          data: options.path == '/api/admin/rides'
              ? {
                  'rides': [ride],
                  'total': 1
                }
              : {'ride': ride},
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          key: navigationKey,
          homeBuilder: (_) => const Text('خريطة السائقين'),
          routes: {
            DashboardNavigation.driversRoute: (_) => DriverManagementScreen(
                  adminToken: 'admin-token',
                  onSessionExpired: fail,
                  client: driverClient,
                ),
            DashboardNavigation.rideHistoryRoute: (_) => RideHistoryScreen(
                  adminToken: 'admin-token',
                  onSessionExpired: fail,
                  client: rideClient,
                ),
            DashboardNavigation.notificationsRoute: (_) =>
                const Text('التنبيهات'),
          },
          onRouteChanged: (_) {},
        ),
      ),
    ));

    navigationKey.currentState!.pushNamed(DashboardNavigation.driversRoute);
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();
    final walletTab = find.byType(Tab).at(3);
    await tester.ensureVisible(walletTab);
    await tester.tap(walletTab);
    await tester.pumpAndSettle();

    navigationKey.currentState!
        .pushNamed(DashboardNavigation.notificationsRoute);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('البيانات الشخصية'), findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      3,
    );

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الكباتن'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('خريطة السائقين'), findsOneWidget);

    navigationKey.currentState!.pushNamed(DashboardNavigation.rideHistoryRoute);
    await tester.pumpAndSettle();
    await tester.tap(find.text('رحلة #7'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الرحلة #7'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('سجل الرحلات'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('خريطة السائقين'), findsOneWidget);
  });

  testWidgets(
      'admin headers clear dashboard controls at desktop and phone widths',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [1024.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      final navigationKey = GlobalKey<DashboardNavigationState>();
      final driverClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      driverClient.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
          requestOptions: options,
          data: {'drivers': [], 'total': 0},
        )),
      ));
      final riderClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      riderClient.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
          requestOptions: options,
          data: {'riders': [], 'total': 0},
        )),
      ));
      final rideClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      rideClient.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
          requestOptions: options,
          data: {'rides': [], 'total': 0},
        )),
      ));
      final couponClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      couponClient.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
          requestOptions: options,
          data: {'coupons': [], 'total': 0},
        )),
      ));
      final staffClient = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      staffClient.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
          requestOptions: options,
          data: {'staff': [], 'roles': []},
        )),
      ));

      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: DashboardNavigation(
                    key: navigationKey,
                    homeBuilder: (_) => const SizedBox.shrink(),
                    routes: {
                      DashboardNavigation.driversRoute: (_) =>
                          DriverManagementScreen(
                            adminToken: 'admin-token',
                            onSessionExpired: fail,
                            client: driverClient,
                          ),
                      DashboardNavigation.ridersRoute: (_) =>
                          RiderManagementScreen(
                            adminToken: 'admin-token',
                            onSessionExpired: fail,
                            client: riderClient,
                          ),
                      DashboardNavigation.rideHistoryRoute: (_) =>
                          RideHistoryScreen(
                            adminToken: 'admin-token',
                            onSessionExpired: fail,
                            client: rideClient,
                          ),
                      DashboardNavigation.couponsRoute: (_) =>
                          CouponManagementScreen(
                            adminToken: 'admin-token',
                            onSessionExpired: fail,
                            client: couponClient,
                          ),
                      DashboardNavigation.staffManagementRoute: (_) =>
                          StaffManagementScreen(
                            adminToken: 'admin-token',
                            currentAdminId: 'admin-1',
                            onSessionExpired: fail,
                            client: staffClient,
                          ),
                    },
                    onRouteChanged: (_) {},
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: IconButton.filledTonal(
                      tooltip: 'فتح القائمة',
                      onPressed: () {},
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));

      navigationKey.currentState!.pushNamed(DashboardNavigation.driversRoute);
      await tester.pumpAndSettle();

      final drawerButton = tester.getRect(find.byTooltip('فتح القائمة'));
      final driverTitle = tester.getRect(find.text('إدارة الكباتن'));
      expect(driverTitle.top, greaterThanOrEqualTo(drawerButton.bottom));

      final addButton = find.ancestor(
        of: find.text('إضافة سائق'),
        matching: find.byType(FilledButton),
      );
      final fixedControlBottom = [
        'إدارة المحادثات',
        'إدارة الشكاوى',
        'رجوع',
      ].map((tooltip) => tester.getRect(find.byTooltip(tooltip)).bottom).reduce(
            (first, second) => first > second ? first : second,
          );
      expect(tester.getRect(addButton).top,
          greaterThanOrEqualTo(fixedControlBottom));

      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('إضافة سائق جديد'), findsOneWidget);
      expect(find.text('الرقم القومي'), findsOneWidget);
      expect(find.text('رقم الشاسيه'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      navigationKey.currentState!.pushNamed(DashboardNavigation.ridersRoute);
      await tester.pumpAndSettle();
      final riderTitle = tester.getRect(find.text('إدارة الركاب'));
      expect(riderTitle.top, greaterThanOrEqualTo(drawerButton.bottom));

      navigationKey.currentState!
          .pushNamed(DashboardNavigation.rideHistoryRoute);
      await tester.pumpAndSettle();
      final rideHistoryTitle = tester.getRect(find.text('سجل الرحلات'));
      expect(rideHistoryTitle.top, greaterThanOrEqualTo(drawerButton.bottom));

      navigationKey.currentState!.pushNamed(DashboardNavigation.couponsRoute);
      await tester.pumpAndSettle();
      final couponsTitle = tester.getRect(find.text('إدارة الكوبونات'));
      expect(couponsTitle.top, greaterThanOrEqualTo(drawerButton.bottom));

      navigationKey.currentState!
          .pushNamed(DashboardNavigation.staffManagementRoute);
      await tester.pumpAndSettle();
      final staffTitle = tester.getRect(find.text('إدارة الموظفين'));
      expect(staffTitle.top, greaterThanOrEqualTo(drawerButton.bottom));
    }
  });

  testWidgets('admin drawer selects the notification destination',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال تنبيهات'));

    expect(selectedDestination, AdminDestination.notifications);
  });

  testWidgets('admin drawer selects the driver management destination',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة الكباتن'));

    expect(selectedDestination, AdminDestination.drivers);
  });

  testWidgets('admin drawer selects the rider management destination',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة الركاب'));

    expect(selectedDestination, AdminDestination.riders);
  });

  testWidgets('admin drawer selects the coupon management destination',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة الكوبونات'));

    expect(selectedDestination, AdminDestination.coupons);
  });

  testWidgets('admin drawer selects the ride history destination',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('سجل الرحلات'));

    expect(selectedDestination, AdminDestination.rideHistory);
  });

  testWidgets(
      'admin drawer shows unread support conversations and selects inbox',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
          unreadConversationCount: 4,
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('إدارة المحادثات'));

    expect(selectedDestination, AdminDestination.supportConversations);
  });

  testWidgets('admin drawer selects complaint management', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    AdminDestination? selectedDestination;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (destination) =>
              selectedDestination = destination,
          onLogout: () {},
          unreadTicketCount: 3,
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('إدارة الشكاوى'));

    expect(selectedDestination, AdminDestination.supportTickets);
  });

  testWidgets('ride history shows colored groups and guarded ride actions',
      (tester) async {
    var activeStatus = 'in_progress';
    var settlementReversed = false;
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));

    Map<String, dynamic> rideRecord(int rideId, String status) => {
          'rideId': rideId,
          'status': status,
          'riderId': 7,
          'driverId': 9,
          'riderName': 'محمد راكب',
          'riderPhone': '+201000000007',
          'driverName': 'أحمد سائق',
          'driverPhone': '+201000000009',
          'carModel': 'سيدان',
          'carColor': 'أبيض',
          'licensePlate': 'ABC-123',
          'pickupAddress': 'شارع النصر',
          'dropoffAddress': 'ميدان التحرير',
          'createdAt': '2026-10-10T10:00:00Z',
          'fare': '50.00',
          'distance': '8.5',
          'duration': 20,
          'paymentMethod': 'cash',
          'paymentStatus': 'pending',
          'cashReceived': null,
          'cancellationReason': status == 'cancelled' ? 'admin_free' : null,
          'canReverseSettlement': status == 'completed' && !settlementReversed,
          'riderRefundAmount': status == 'completed' ? 50 : 0,
          'settlementReversedAt':
              settlementReversed ? '2026-10-11 10:00:00' : null,
          'reversalReason': settlementReversed ? 'تصحيح' : null,
          'reversedBy': settlementReversed ? 'admin-panel' : null,
        };

    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.method == 'GET' && options.path == '/api/admin/rides') {
          final group = options.queryParameters['group'];
          final rides = switch (group) {
            'active' when activeStatus != 'cancelled' => [
                rideRecord(41, activeStatus)
              ],
            'cancelled' => [rideRecord(41, 'cancelled')],
            'completed' => [rideRecord(52, 'completed')],
            _ => <Map<String, dynamic>>[],
          };
          handler.resolve(Response(
            requestOptions: options,
            data: {'rides': rides, 'total': rides.length},
          ));
          return;
        }
        if (options.method == 'GET' &&
            options.path.startsWith('/api/admin/rides/')) {
          final rideId = int.parse(options.path.split('/').last);
          final status = rideId == 52 ? 'completed' : activeStatus;
          handler.resolve(Response(
            requestOptions: options,
            data: {'ride': rideRecord(rideId, status)},
          ));
          return;
        }
        if (options.method == 'POST' &&
            options.path == '/api/admin/rides/41/cancel') {
          activeStatus = 'cancelled';
          handler.resolve(Response(
            requestOptions: options,
            data: {'success': true, 'status': 'cancelled'},
          ));
          return;
        }
        if (options.method == 'POST' &&
            options.path == '/api/admin/rides/52/reverse-settlement') {
          settlementReversed = true;
          handler.resolve(Response(
            requestOptions: options,
            data: {'success': true, 'reversed': true, 'refundedAmount': 60},
          ));
          return;
        }
        handler.resolve(
            Response(requestOptions: options, data: {'success': true}));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RideHistoryScreen(
          adminToken: 'admin-token',
          canReverseSettlement: true,
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');
    expect(requests.first.queryParameters['group'], 'active');
    expect(requests.first.queryParameters['page'], 1);
    expect(find.text('كل الفترات'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ABC-123');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['search'], 'ABC-123');
    expect(requests.last.queryParameters['page'], 1);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    expect(find.text('أسبوع'), findsOneWidget);
    expect(find.text('شهر'), findsOneWidget);
    expect(find.text('مدة محددة'), findsOneWidget);
    await tester.tap(find.text('أمس'));
    await tester.pumpAndSettle();
    final yesterdayRequest = requests.last;
    expect(yesterdayRequest.queryParameters['search'], 'ABC-123');
    expect(yesterdayRequest.queryParameters['page'], 1);
    final startAt =
        DateTime.parse(yesterdayRequest.queryParameters['startAt'] as String)
            .toLocal();
    final endAt =
        DateTime.parse(yesterdayRequest.queryParameters['endAt'] as String)
            .toLocal();
    final today = DateTime.now();
    expect(
        DateTime(startAt.year, startAt.month, startAt.day),
        DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 1)));
    expect(DateTime(endAt.year, endAt.month, endAt.day),
        DateTime(today.year, today.month, today.day));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسبوع'));
    await tester.pumpAndSettle();
    final weekStart =
        DateTime.parse(requests.last.queryParameters['startAt'] as String)
            .toLocal();
    final weekEnd =
        DateTime.parse(requests.last.queryParameters['endAt'] as String)
            .toLocal();
    expect(DateTime(weekStart.year, weekStart.month, weekStart.day).weekday, 6);
    expect(
        DateTime(weekEnd.year, weekEnd.month, weekEnd.day),
        DateTime(weekStart.year, weekStart.month, weekStart.day)
            .add(const Duration(days: 7)));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر'));
    await tester.pumpAndSettle();
    final monthStart =
        DateTime.parse(requests.last.queryParameters['startAt'] as String)
            .toLocal();
    final monthEnd =
        DateTime.parse(requests.last.queryParameters['endAt'] as String)
            .toLocal();
    expect(monthStart.day, 1);
    expect(monthEnd.day, 1);
    expect(monthEnd, DateTime(monthStart.year, monthStart.month + 1));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق').last);
    await tester.pumpAndSettle();
    final customStart =
        DateTime.parse(requests.last.queryParameters['startAt'] as String)
            .toLocal();
    final customEnd =
        DateTime.parse(requests.last.queryParameters['endAt'] as String)
            .toLocal();
    expect(DateTime(customStart.year, customStart.month, customStart.day),
        DateTime(today.year, today.month, today.day));
    expect(
        DateTime(customEnd.year, customEnd.month, customEnd.day),
        DateTime(today.year, today.month, today.day)
            .add(const Duration(days: 1)));

    final activeCard = tester.widget<Card>(find.byType(Card).first);
    final activeShape = activeCard.shape! as RoundedRectangleBorder;
    expect(
        activeShape.side.color, Colors.amber.shade800.withValues(alpha: 0.65));

    await tester.tap(find.text('رحلة #41'));
    await tester.pumpAndSettle();
    expect(find.text('محمد راكب'), findsOneWidget);
    expect(find.text('أحمد سائق'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('نقطة الانطلاق'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('نقطة الانطلاق'), findsOneWidget);
    expect(find.text('إلغاء الرحلة مجانًا'), findsOneWidget);
    expect(find.text('إنهاء الرحلة'), findsOneWidget);

    await tester.tap(find.text('إلغاء الرحلة مجانًا'));
    await tester.pumpAndSettle();
    expect(find.textContaining('دون رسوم أو تسوية للأجرة'), findsOneWidget);
    await tester.tap(find.text('تأكيد الإلغاء'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.method == 'POST' &&
          request.path == '/api/admin/rides/41/cancel'),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('سبب الإلغاء'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('سبب الإلغاء'), findsOneWidget);
    expect(find.text('إلغاء الرحلة مجانًا'), findsNothing);
    expect(find.text('إنهاء الرحلة'), findsNothing);
    ScaffoldMessenger.of(tester.element(find.byType(RideHistoryScreen)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('العودة إلى السجل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الملغاة'));
    await tester.pumpAndSettle();
    final cancelledCard = tester.widget<Card>(find.byType(Card).first);
    final cancelledShape = cancelledCard.shape! as RoundedRectangleBorder;
    expect(
        cancelledShape.side.color, Colors.red.shade700.withValues(alpha: 0.65));
    await tester.tap(find.text('رحلة #41'));
    await tester.pumpAndSettle();
    expect(find.text('عكس التسوية'), findsNothing);
    await tester.tap(find.byTooltip('العودة إلى السجل'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المكتملة'));
    await tester.pumpAndSettle();
    final completedCard = tester.widget<Card>(find.byType(Card).first);
    final completedShape = completedCard.shape! as RoundedRectangleBorder;
    expect(completedShape.side.color,
        Colors.green.shade700.withValues(alpha: 0.65));
    await tester.tap(find.text('رحلة #52'));
    await tester.pumpAndSettle();
    expect(find.text('عكس التسوية'), findsOneWidget);
    await tester.tap(find.text('عكس التسوية'));
    await tester.pumpAndSettle();
    expect(find.textContaining('50 ج.م'), findsOneWidget);
    final confirmReversal = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('تأكيد العكس'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(confirmReversal.onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'تصحيح مبلغ الرحلة');
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد العكس'));
    await tester.pumpAndSettle();
    final reversalRequest = requests.lastWhere((request) =>
        request.method == 'POST' &&
        request.path == '/api/admin/rides/52/reverse-settlement');
    expect(reversalRequest.data, {'reason': 'تصحيح مبلغ الرحلة'});
    await tester.scrollUntilVisible(
      find.text('حالة عكس التسوية'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('حالة عكس التسوية'), findsOneWidget);
    expect(find.text('تم عكسها'), findsOneWidget);
    expect(find.text('عكس التسوية'), findsNothing);
  });

  testWidgets('rider management opens related records and adjusts wallet',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceSaturday = (now.weekday + 1) % 7;
    final weekStart = today.subtract(Duration(days: daysSinceSaturday));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final customDate = List.generate(
      DateTime(now.year, now.month + 1, 0).day,
      (index) => DateTime(now.year, now.month, index + 1),
    ).firstWhere((date) => date.isBefore(weekStart) || !date.isBefore(weekEnd));
    final weekDate = today.add(Duration(days: daysSinceSaturday == 6 ? -1 : 1));
    final previousMonthDate = DateTime(now.year, now.month - 1, 15);
    final requests = <RequestOptions>[];
    String? riderDebtLimit;
    var effectiveRiderDebtLimit = '-30.00';
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
                'phone': '+201000000000',
                'balance': '12.00',
                'ridesCount': 1,
                'isActive': 1,
                'accountStatus': 'active',
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
              'balance': '12.00',
              'rating': '4.65',
              'reputationPoints': 425,
              'isActive': 1,
              'accountStatus': 'active',
              'riderDebtLimit': riderDebtLimit,
              'effectiveRiderDebtLimit': effectiveRiderDebtLimit,
            },
            'rides': [
              {
                'rideId': 41,
                'status': 'completed',
                'fare': '25.00',
                'createdAt':
                    today.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'rideId': 42,
                'status': 'completed',
                'fare': '18.00',
                'createdAt':
                    customDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'rideId': 43,
                'status': 'completed',
                'fare': '30.00',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
              },
            ],
            'wallet': {
              'balance': '12.00',
              'transactions': [
                {'id': 5, 'amount': '12.00', 'transactionType': 'deposit'},
              ],
            },
            'ratings': [
              {
                'rideId': 411,
                'raterUserId': 99,
                'raterName': 'محمد سائق',
                'targetUserId': 12,
                'targetName': 'أحمد راكب',
                'stars': 5,
                'comment': 'تقييم كتبه السائق اليوم',
                'createdAt':
                    today.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'rideId': 412,
                'raterUserId': 99,
                'raterName': 'محمد سائق',
                'targetUserId': 12,
                'targetName': 'أحمد راكب',
                'stars': 4,
                'comment': 'تقييم هذا الأسبوع',
                'createdAt':
                    weekDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'rideId': 413,
                'raterUserId': 99,
                'raterName': 'محمد سائق',
                'targetUserId': 12,
                'targetName': 'أحمد راكب',
                'stars': 3,
                'comment': 'تقييم الشهر الماضي',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
              },
              {
                'rideId': 414,
                'raterUserId': 99,
                'raterName': 'محمد سائق',
                'targetUserId': 12,
                'targetName': 'أحمد راكب',
                'stars': 4,
                'comment': 'تقييم المدة المحددة',
                'createdAt':
                    customDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'rideId': 415,
                'raterUserId': 12,
                'raterName': 'أحمد راكب',
                'targetUserId': 99,
                'targetName': 'محمد سائق',
                'stars': 5,
                'comment': 'تقييم كتبه الراكب للسائق',
                'createdAt':
                    today.add(const Duration(hours: 12)).toIso8601String(),
              },
            ],
            'financialRecords': {
              'shortfalls': [
                {
                  'id': 501,
                  'amount': '5.00',
                  'createdAt':
                      today.add(const Duration(hours: 12)).toIso8601String(),
                },
                {
                  'id': 502,
                  'amount': '6.00',
                  'createdAt':
                      weekDate.add(const Duration(hours: 12)).toIso8601String(),
                },
                {
                  'id': 503,
                  'amount': '7.00',
                  'createdAt': previousMonthDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
                {
                  'id': 504,
                  'amount': '8.00',
                  'createdAt': customDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
              ],
              'reversals': [
                {
                  'id': 505,
                  'amount': '9.00',
                  'createdAt':
                      today.add(const Duration(hours: 12)).toIso8601String(),
                },
              ],
            },
            'coupons': {'assigned': [], 'reservations': [], 'redemptions': []},
            'notifications': [
              {
                'id': 801,
                'title': 'إشعار هذا الأسبوع',
                'createdAt':
                    weekDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'id': 802,
                'title': 'إشعار الشهر الماضي',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
              },
            ],
            'offers': [],
            'cancellationPolicies': [],
            'devices': [
              {'id': 803, 'role': 'rider'},
            ],
            'location': null,
            'chatMessages': [
              {
                'id': 14,
                'rideId': 41,
                'senderName': 'أحمد راكب',
                'messageBody': 'وصلت إلى نقطة الالتقاء',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 2))
                    .toIso8601String(),
              },
              {
                'id': 13,
                'rideId': 41,
                'senderName': 'محمد سائق',
                'messageBody': 'أنا في الطريق',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1))
                    .toIso8601String(),
                'deliveredAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1, seconds: 10))
                    .toIso8601String(),
                'readAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1, seconds: 20))
                    .toIso8601String(),
              },
              {
                'id': 99,
                'rideId': 99,
                'senderName': 'راكب آخر',
                'messageBody': 'محادثة رحلة أخرى',
                'createdAt': today
                    .add(const Duration(hours: 10, minutes: 3))
                    .toIso8601String(),
              },
            ],
            'locationPoints': [],
          }));
          return;
        }
        if (options.path == '/api/admin/riders/12' &&
            options.method == 'PATCH') {
          riderDebtLimit = options.data['riderDebtLimit'] as String?;
          effectiveRiderDebtLimit = riderDebtLimit ?? '-30.00';
          handler.resolve(Response(requestOptions: options, data: {
            'success': true,
          }));
          return;
        }
        handler.resolve(Response(requestOptions: options, data: {
          'success': true,
          'balance': '17.00',
          'transactionType': 'deposit',
        }));
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
    expect(find.text('أحمد راكب'), findsOneWidget);
    await tester.tap(find.text('أحمد راكب'));
    await tester.pumpAndSettle();
    expect(find.text('البيانات الشخصية'), findsNothing);
    final ratingsTab = find.byType(Tab).at(4);
    await tester.ensureVisible(ratingsTab);
    await tester.tap(ratingsTab);
    await tester.pumpAndSettle();
    expect(find.text('التقييم'), findsOneWidget);
    expect(find.text('4.65'), findsOneWidget);
    expect(find.text('نقاط السمعة'), findsOneWidget);
    expect(find.text('425'), findsOneWidget);
    expect(find.text('عدد التقييمات المستلمة'), findsOneWidget);
    expect(find.text('الرحلة 411'), findsOneWidget);
    expect(find.text('الرحلة 412'), findsOneWidget);
    expect(find.text('الرحلة 413'), findsNothing);
    expect(find.text('الرحلة 415'), findsNothing);
    await tester.tap(find.text('الرحلة 411'));
    await tester.pumpAndSettle();
    expect(find.text('تقييم كتبه السائق اليوم'), findsOneWidget);
    expect(find.text('محمد سائق'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 411'), findsOneWidget);
    expect(find.text('الرحلة 413'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customRatingDay = find.text('${customDate.day}').first;
    await tester.tap(customRatingDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 414'), findsOneWidget);
    expect(find.text('الرحلة 411'), findsNothing);

    final settlementsTab = find.byType(Tab).at(3);
    await tester.ensureVisible(settlementsTab);
    await tester.tap(settlementsTab);
    await tester.pumpAndSettle();
    final settlementPeriod = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).last,
    );
    expect(settlementPeriod.initialValue, 'week');
    expect(find.text('المعرّف: 501'), findsOneWidget);
    expect(find.text('المعرّف: 502'), findsOneWidget);
    expect(find.text('المعرّف: 503'), findsNothing);
    expect(find.text('المعرّف: 504'), findsNothing);
    expect(find.text('المعرّف: 505'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'عجوزات الرحلات'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 501'), findsOneWidget);
    expect(find.text('المعرّف: 505'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'كل التصنيفات'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 505'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customSettlementDay = find.text('${customDate.day}').first;
    await tester.tap(customSettlementDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 504'), findsOneWidget);
    expect(find.text('المعرّف: 501'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الفترات'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 501'), findsOneWidget);
    expect(find.text('المعرّف: 503'), findsOneWidget);

    final activityTab = find.byType(Tab).at(6);
    await tester.ensureVisible(activityTab);
    await tester.tap(activityTab);
    await tester.pumpAndSettle();
    final activityPeriod = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).last,
    );
    expect(activityPeriod.initialValue, 'week');
    expect(find.text('المعرّف: 801'), findsOneWidget);
    expect(find.text('المعرّف: 802'), findsNothing);
    expect(find.text('المعرّف: 803'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'الإشعارات'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 801'), findsOneWidget);
    expect(find.text('المعرّف: 803'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'كل التصنيفات'));
    await tester.pumpAndSettle();
    expect(find.text('المعرّف: 803'), findsOneWidget);

    final riderRidesTab = find.text('الرحلات');
    await tester.ensureVisible(riderRidesTab);
    expect(riderRidesTab, findsOneWidget);
    await tester.tap(riderRidesTab);
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsOneWidget);
    expect(find.text('الرحلة 42'), findsNothing);
    expect(find.text('الرحلة 43'), findsNothing);
    await tester.tap(find.text('الرحلة 41'));
    await tester.pumpAndSettle();
    expect(find.text('الحالة'), findsOneWidget);
    expect(find.text('مكتملة'), findsAtLeastNWidgets(1));
    expect(find.text('الأجرة'), findsOneWidget);
    expect(find.text('محادثة الرحلة'), findsOneWidget);
    final earlierRiderMessage = find.text('أنا في الطريق');
    final laterRiderMessage = find.text('وصلت إلى نقطة الالتقاء');
    expect(earlierRiderMessage, findsOneWidget);
    expect(laterRiderMessage, findsOneWidget);
    expect(tester.getTopLeft(earlierRiderMessage).dy,
        lessThan(tester.getTopLeft(laterRiderMessage).dy));
    expect(find.text('محادثة رحلة أخرى'), findsNothing);
    await tester.tap(find.text('الرحلة 41'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsOneWidget);
    expect(find.text('الرحلة 42'), findsOneWidget);
    expect(find.text('الرحلة 43'), findsNothing);
    await tester.tap(find.text('الرحلة 42'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد رسائل لهذه الرحلة'), findsOneWidget);
    await tester.tap(find.text('الرحلة 42'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customRideDay = find.text('${customDate.day}').first;
    await tester.tap(customRideDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsNothing);
    expect(find.text('الرحلة 42'), findsOneWidget);
    expect(find.text('الرحلة 43'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الفترات'));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 41'), findsOneWidget);
    expect(find.text('الرحلة 42'), findsOneWidget);
    expect(find.text('الرحلة 43'), findsOneWidget);

    await tester.tap(find.text('المحفظة'));
    await tester.pumpAndSettle();
    expect(find.text('الحد العام: -30.00 ج.م'), findsOneWidget);
    final balanceTitle = tester.getTopLeft(find.text('الرصيد الحالي'));
    final debtLimitTitle = tester.getTopLeft(find.text('حد الدين'));
    expect(balanceTitle.dy, debtLimitTitle.dy);
    await tester.tap(find.byTooltip('تعديل حد الدين'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-45.00');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    final customLimitRequest = requests.singleWhere((request) =>
        request.method == 'PATCH' && request.path == '/api/admin/riders/12');
    expect(customLimitRequest.data, {'riderDebtLimit': '-45.00'});
    expect(find.text('حد مخصص: -45.00 ج.م'), findsOneWidget);

    await tester.tap(find.byTooltip('تعديل حد الدين'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استخدام الحد العام'));
    await tester.pumpAndSettle();
    final resetLimitRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' && request.path == '/api/admin/riders/12');
    expect(resetLimitRequest.data, {'riderDebtLimit': null});
    expect(find.text('الحد العام: -30.00 ج.م'), findsOneWidget);

    await tester.tap(find.byTooltip('تعديل الرصيد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5.00');
    await tester.enterText(find.byType(TextField).last, 'تصحيح إداري');
    await tester.tap(find.text('تسجيل الحركة'));
    await tester.pumpAndSettle();

    final adjustment = requests.singleWhere((request) =>
        request.method == 'POST' &&
        request.path == '/api/admin/riders/12/wallet-adjustments');
    expect(adjustment.data, {
      'direction': 'credit',
      'amount': '5.00',
      'description': 'تصحيح إداري',
    });
    expect(adjustment.headers['Authorization'], 'Bearer admin-token');

    await tester.ensureVisible(find.text('الشكاوى'));
    await tester.tap(find.text('الشكاوى'));
    await tester.pumpAndSettle();
    final riderTicketHistory = requests.lastWhere(
        (request) => request.path == '/api/admin/support/history/tickets');
    expect(riderTicketHistory.queryParameters['userId'], 12);
    expect(riderTicketHistory.queryParameters['userRole'], 'rider');

    await tester.ensureVisible(find.text('محادثات خدمة العملاء'));
    await tester.tap(find.text('محادثات خدمة العملاء'));
    await tester.pumpAndSettle();
    final riderConversationHistory = requests.lastWhere((request) =>
        request.path == '/api/admin/support/history/conversations');
    expect(riderConversationHistory.queryParameters['userId'], 12);
    expect(riderConversationHistory.queryParameters['userRole'], 'rider');

    await tester.tap(find.byTooltip('العودة للقائمة'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الركاب'), findsOneWidget);
  });

  testWidgets(
      'driver management searches, filters and opens schema-backed tabs',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceSaturday = (now.weekday + 1) % 7;
    final weekStart = today.subtract(Duration(days: daysSinceSaturday));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final customDate = List.generate(
      DateTime(now.year, now.month + 1, 0).day,
      (index) => DateTime(now.year, now.month, index + 1),
    ).firstWhere((date) => date.isBefore(weekStart) || !date.isBefore(weekEnd));
    final weekDate = today.add(Duration(days: daysSinceSaturday == 6 ? -1 : 1));
    final previousMonthDate = DateTime(now.year, now.month - 1, 15);
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    final requests = <RequestOptions>[];
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.path == '/api/admin/drivers' && options.method == 'GET') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'drivers': [
                {
                  'driverId': 4,
                  'userId': 12,
                  'fullName': 'محمد علي',
                  'phone': '+201000000000',
                  'licensePlate': 'ABC-123',
                  'isActive': 1,
                  'accountStatus': 'active',
                  'latestRideId': 41,
                },
              ],
              'total': 1,
            },
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'profile': {
              'driverId': 4,
              'userId': 12,
              'fullName': 'محمد علي',
              'phone': '+201000000000',
              'isActive': 1,
              'accountStatus': 'active',
              'carModel': 'سيدان',
              'licensePlate': 'ABC-123',
              'vehicleCategory': 'standard',
              'driverDebtLimit': null,
              'effectiveDriverDebtLimit': '-300.00',
              'userRating': '4.75',
              'driverRating': '4.80',
              'reputationPoints': 485,
            },
            'rides': [
              {
                'id': 41,
                'status': 'completed',
                'fare': '25.00',
                'createdAt':
                    today.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'id': 42,
                'status': 'completed',
                'fare': '18.00',
                'createdAt':
                    customDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'id': 43,
                'status': 'completed',
                'fare': '30.00',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
              },
            ],
            'chatMessages': [
              {
                'id': 24,
                'rideId': 41,
                'senderName': 'الراكب',
                'messageBody': 'وصلت إلى نقطة الالتقاء',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 2))
                    .toIso8601String(),
              },
              {
                'id': 23,
                'rideId': 41,
                'senderName': 'محمد علي',
                'messageBody': 'أنا في الطريق',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1))
                    .toIso8601String(),
                'deliveredAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1, seconds: 10))
                    .toIso8601String(),
                'readAt': previousMonthDate
                    .add(const Duration(hours: 10, minutes: 1, seconds: 20))
                    .toIso8601String(),
              },
            ],
            'wallet': {
              'balance': '100.00',
              'transactions': [
                {
                  'id': 101,
                  'amount': '25.00',
                  'createdAt':
                      today.add(const Duration(hours: 12)).toIso8601String(),
                },
                {
                  'id': 102,
                  'amount': '10.00',
                  'createdAt': customDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
                {
                  'id': 104,
                  'amount': '15.00',
                  'createdAt':
                      weekDate.add(const Duration(hours: 12)).toIso8601String(),
                },
                {
                  'id': 103,
                  'amount': '5.00',
                  'createdAt': previousMonthDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
              ],
            },
            'ratings': [
              {
                'id': 991,
                'rideId': 701,
                'raterUserId': 55,
                'raterName': 'الراكب صاحب التقييم',
                'targetUserId': 12,
                'targetName': 'محمد علي',
                'stars': 5,
                'comment': 'تقييم الراكب اليوم',
                'createdAt':
                    today.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'id': 992,
                'rideId': 702,
                'raterUserId': 55,
                'raterName': 'الراكب صاحب التقييم',
                'targetUserId': 12,
                'targetName': 'محمد علي',
                'stars': 4,
                'comment': 'تقييم الراكب هذا الأسبوع',
                'createdAt':
                    weekDate.add(const Duration(hours: 12)).toIso8601String(),
              },
              {
                'id': 993,
                'rideId': 703,
                'raterUserId': 55,
                'raterName': 'الراكب صاحب التقييم',
                'targetUserId': 12,
                'targetName': 'محمد علي',
                'stars': 3,
                'comment': 'تقييم الشهر الماضي',
                'createdAt': previousMonthDate
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
              },
              {
                'id': 994,
                'rideId': 704,
                'raterUserId': 55,
                'raterName': 'الراكب صاحب التقييم',
                'targetUserId': 12,
                'targetName': 'محمد علي',
                'stars': 4,
                'comment': 'تقييم المدة المحددة',
                'createdAt':
                    customDate.add(const Duration(hours: 12)).toIso8601String(),
              },
            ],
            'financialRecords': {
              'appLedger': [
                {
                  'id': 901,
                  'amount': '5.00',
                  'createdAt':
                      today.add(const Duration(hours: 12)).toIso8601String(),
                },
                {
                  'id': 903,
                  'amount': '7.00',
                  'createdAt': previousMonthDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
                {
                  'id': 904,
                  'amount': '8.00',
                  'createdAt': customDate
                      .add(const Duration(hours: 12))
                      .toIso8601String(),
                },
              ],
              'shortfalls': [
                {
                  'id': 902,
                  'amount': '6.00',
                  'createdAt':
                      weekDate.add(const Duration(hours: 12)).toIso8601String(),
                },
              ],
            },
            'unavailable': ['vehicleDocuments', 'reports', 'payoutRequests'],
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverManagementScreen(
          adminToken: 'admin-token',
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('محمد علي'), findsOneWidget);
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');

    await tester.enterText(find.byType(TextField).first, 'ABC');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['search'], 'ABC');

    await tester.tap(find.text('نشط').first);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['status'], 'active');

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(IconButton, Icons.arrow_back), findsOneWidget);
    expect(find.text('البيانات الشخصية'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('نعم'), findsOneWidget);
    final ratingsTab = find.byType(Tab).at(5);
    await tester.ensureVisible(ratingsTab);
    await tester.tap(ratingsTab);
    await tester.pumpAndSettle();
    expect(find.text('التقييمات'), findsOneWidget);
    expect(find.text('التقييمات والملاحظات'), findsNothing);
    expect(find.text('4.75'), findsOneWidget);
    expect(find.text('4.80'), findsOneWidget);
    expect(find.text('عدد التقييمات المسجلة'), findsOneWidget);
    expect(find.text('الرحلة 701'), findsOneWidget);
    expect(find.text('الرحلة 702'), findsOneWidget);
    expect(find.text('الرحلة 703'), findsNothing);
    expect(find.text('رقم 991'), findsNothing);
    await tester.tap(find.text('الرحلة 701'));
    await tester.pumpAndSettle();
    expect(find.text('تقييم الراكب اليوم'), findsOneWidget);
    expect(find.text('الطرف المقيّم'), findsOneWidget);
    expect(find.text('محمد علي'), findsAtLeastNWidgets(1));
    expect(find.text('التعليق'), findsOneWidget);

    final ridesTab = find.byType(Tab).at(2);
    await tester.ensureVisible(ridesTab);
    await tester.tap(ridesTab);
    await tester.pumpAndSettle();
    expect(find.text('رقم 41'), findsOneWidget);
    expect(find.text('رقم 42'), findsNothing);
    expect(find.text('رقم 43'), findsNothing);
    await tester.tap(find.text('رقم 41'));
    await tester.pumpAndSettle();
    expect(find.text('محادثة الرحلة'), findsOneWidget);
    final earlierDriverMessage = find.text('أنا في الطريق');
    final laterDriverMessage = find.text('وصلت إلى نقطة الالتقاء');
    expect(earlierDriverMessage, findsOneWidget);
    expect(laterDriverMessage, findsOneWidget);
    expect(tester.getTopLeft(earlierDriverMessage).dy,
        lessThan(tester.getTopLeft(laterDriverMessage).dy));
    await tester.tap(find.text('رقم 41'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('رقم 41'), findsOneWidget);
    expect(find.text('رقم 42'), findsOneWidget);
    expect(find.text('رقم 43'), findsNothing);
    await tester.tap(find.text('رقم 42'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد رسائل لهذه الرحلة'), findsOneWidget);
    await tester.tap(find.text('رقم 42'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customDriverRideDay = find.text('${customDate.day}').first;
    await tester.tap(customDriverRideDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 41'), findsNothing);
    expect(find.text('رقم 42'), findsOneWidget);
    expect(find.text('رقم 43'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الفترات'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 41'), findsOneWidget);
    expect(find.text('رقم 42'), findsOneWidget);
    expect(find.text('رقم 43'), findsOneWidget);
    await tester.ensureVisible(ratingsTab);
    await tester.tap(ratingsTab);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 701'), findsOneWidget);
    expect(find.text('الرحلة 703'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customRatingDay = find.text('${customDate.day}').first;
    await tester.tap(customRatingDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة 704'), findsOneWidget);
    expect(find.text('الرحلة 701'), findsNothing);

    final walletTab = find.byType(Tab).at(3);
    await tester.ensureVisible(walletTab);
    await tester.tap(walletTab);
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      3,
    );
    await tester.scrollUntilVisible(
      find.text('حركات المحفظة'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('حركات المحفظة'), findsOneWidget);
    expect(find.text('رقم 101'), findsOneWidget);
    expect(find.text('رقم 102'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسبوع').last);
    await tester.pumpAndSettle();
    expect(find.text('رقم 101'), findsOneWidget);
    expect(find.text('رقم 104'), findsOneWidget);
    expect(find.text('رقم 103'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('رقم 101'), findsOneWidget);
    expect(find.text('رقم 102'), findsOneWidget);
    expect(find.text('رقم 103'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customDay = find.text('${customDate.day}').first;
    await tester.tap(customDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 101'), findsNothing);
    expect(find.text('رقم 102'), findsOneWidget);
    expect(find.text('رقم 103'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('حد مديونية المحفظة'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('الحد العام: -300.00 ج.م'), findsOneWidget);
    await tester.tap(find.byTooltip('تعديل حد المديونية'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '-450.00');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    final debtLimitRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' && request.path == '/api/admin/drivers/4');
    expect(debtLimitRequest.data, {'driverDebtLimit': '-450.00'});

    await tester.ensureVisible(find.text('المعاملات والتحويلات'));
    await tester.tap(find.text('المعاملات والتحويلات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا توجد في النظام طلبات سحب معلقة'),
        findsOneWidget);
    expect(find.text('حركات المحفظة'), findsNothing);
    final transactionPeriod = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).last,
    );
    expect(transactionPeriod.initialValue, 'week');
    expect(find.text('رقم 901'), findsOneWidget);
    expect(find.text('رقم 902'), findsOneWidget);
    expect(find.text('رقم 903'), findsNothing);
    expect(find.text('رقم 904'), findsNothing);

    await tester
        .tap(find.widgetWithText(FilterChip, 'دفتر عمولات ورسوم التطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 901'), findsOneWidget);
    expect(find.text('رقم 902'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'كل التصنيفات'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 902'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('يوم').last);
    await tester.pumpAndSettle();
    expect(find.text('رقم 901'), findsOneWidget);
    expect(find.text('رقم 902'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    expect(find.text('رقم 901'), findsOneWidget);
    expect(find.text('رقم 902'), findsOneWidget);
    expect(find.text('رقم 903'), findsNothing);
    expect(find.text('رقم 904'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    final customTransactionDay = find.text('${customDate.day}').first;
    await tester.tap(customTransactionDay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${customDate.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 904'), findsOneWidget);
    expect(find.text('رقم 901'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الفترات'));
    await tester.pumpAndSettle();
    expect(find.text('رقم 901'), findsOneWidget);
    expect(find.text('رقم 903'), findsOneWidget);

    await tester.ensureVisible(find.text('الشكاوى'));
    await tester.tap(find.text('الشكاوى'));
    await tester.pumpAndSettle();
    final driverTicketHistory = requests.lastWhere(
        (request) => request.path == '/api/admin/support/history/tickets');
    expect(driverTicketHistory.queryParameters['userId'], 12);
    expect(driverTicketHistory.queryParameters['userRole'], 'driver');

    await tester.ensureVisible(find.text('محادثات خدمة العملاء'));
    await tester.tap(find.text('محادثات خدمة العملاء'));
    await tester.pumpAndSettle();
    final driverConversationHistory = requests.lastWhere((request) =>
        request.path == '/api/admin/support/history/conversations');
    expect(driverConversationHistory.queryParameters['userId'], 12);
    expect(driverConversationHistory.queryParameters['userRole'], 'driver');

    await tester.tap(find.byTooltip('العودة للقائمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حذف آمن: تعطيل الحساب'));
    await tester.pumpAndSettle();
    expect(find.text('حذف السائق بأمان؟'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.method == 'PATCH' &&
          request.path == '/api/admin/drivers/4/status' &&
          request.data['status'] == 'suspended'),
      isTrue,
    );
  });

  testWidgets('notification composer preserves a targeted user payload',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    RequestOptions? sentRequest;
    RequestOptions? searchRequest;
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'GET') {
          searchRequest = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'success': true,
              'recipients': [
                {
                  'userId': 9,
                  'fullName': 'أحمد راكب',
                  'phone': '+201000000000',
                  'role': 'rider',
                },
              ],
            },
          ));
          return;
        }
        sentRequest = options;
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'recipients': 1,
            'savedRecipients': 1,
            'delivered': 1,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationScreen(
          adminToken: 'admin-token',
          onSessionExpired: (message) => fail(message),
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مستخدم محدد').last);
    await tester.pumpAndSettle();

    expect(find.text('+2010'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), '010');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(searchRequest?.path, '/api/admin/notifications/recipients');
    expect(searchRequest?.queryParameters, {
      'role': 'rider',
      'phonePrefix': '010',
    });
    await tester.tap(find.text('أحمد راكب'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'عنوان تجريبي');
    await tester.enterText(find.byType(TextField).at(2), 'نص تجريبي');
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال التنبيه'));
    await tester.pumpAndSettle();

    expect(sentRequest?.path, '/api/admin/notifications');
    expect(sentRequest?.headers['Authorization'], 'Bearer admin-token');
    expect(sentRequest?.data, {
      'category': 'customer_service',
      'title': 'عنوان تجريبي',
      'body': 'نص تجريبي',
      'audience': 'user',
      'role': 'rider',
      'phones': ['+201000000000'],
    });
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(
      find.text('تم حفظ التنبيه لـ 1 من 1 مستلم، وأُرسل إلى 1 جهاز'),
      findsOneWidget,
    );
  });

  testWidgets('notification composer sends pasted phone numbers together',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'recipients': 2,
            'savedRecipients': 2,
            'delivered': 2,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationScreen(
          adminToken: 'admin-token',
          onSessionExpired: (message) => fail(message),
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مستخدم محدد').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      '+201000000001, +201000000002',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'عنوان');
    await tester.enterText(find.byType(TextField).at(2), 'نص');
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال التنبيه'));
    await tester.pumpAndSettle();

    expect(requests.single.data['phones'], [
      '+201000000001',
      '+201000000002',
    ]);
  });

  testWidgets('notification composer explains missing devices and keeps text',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'recipients': 1,
            'savedRecipients': 0,
            'recipientsWithoutDevices': 1,
            'recipientsFailed': 0,
            'recipientsWithFailures': 0,
            'delivered': 0,
            'failedDevices': 0,
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationScreen(
          adminToken: 'admin-token',
          onSessionExpired: (message) => fail(message),
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'عنوان تجريبي');
    await tester.enterText(find.byType(TextField).at(1), 'نص تجريبي');
    await tester.tap(find.text('إرسال التنبيه'));
    await tester.pumpAndSettle();

    expect(
      find.text('لم يصل التنبيه لأي جهاز، لذلك لم يُحفظ. بلا جهاز مسجل: 1'),
      findsOneWidget,
    );
    expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        'عنوان تجريبي');
    expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
        'نص تجريبي');
  });

  testWidgets('notification composer shows FCM errors when delivery fails',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'recipients': 1,
            'savedRecipients': 0,
            'recipientsWithoutDevices': 0,
            'recipientsFailed': 1,
            'recipientsWithFailures': 1,
            'delivered': 0,
            'failedDevices': 1,
            'failureCodes': {'messaging/invalid-credential': 1},
          },
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationScreen(
          adminToken: 'admin-token',
          onSessionExpired: (message) => fail(message),
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'نص تجريبي');
    await tester.tap(find.text('إرسال التنبيه'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('messaging/invalid-credential (1)'),
      findsOneWidget,
    );
  });
}

class _HomeProbe extends StatefulWidget {
  const _HomeProbe({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_HomeProbe> createState() => _HomeProbeState();
}

class _HomeProbeState extends State<_HomeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('خريطة السائقين');
}
