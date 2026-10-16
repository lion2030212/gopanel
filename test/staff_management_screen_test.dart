import 'package:admin_panel/screens/staff_management_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/widgets/dashboard_navigation.dart';

void main() {
  Dio createClient(List<RequestOptions> requests) {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.method == 'GET' &&
            (options.path.startsWith('/api/admin/staff/') ||
                options.path == '/api/admin/staff/ratings/general')) {
          final generalAdmin = options.path.endsWith('/general');
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'averageRating': generalAdmin ? 3.0 : 4.5,
              'ratingsCount': 1,
              'ratings': [
                {
                  'id': 1,
                  'interactionType': 'conversation',
                  'interactionId': generalAdmin ? 21 : 19,
                  'raterRole': 'driver',
                  'raterName': 'سائق',
                  'stars': generalAdmin ? 3 : 5,
                  'comment': generalAdmin ? 'جيد' : 'ممتاز',
                  'createdAt': DateTime.now().toIso8601String(),
                },
              ],
            },
          ));
          return;
        }
        if (options.method == 'GET' && options.path == '/api/admin/staff') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'staff': [
                {
                  'id': 1,
                  'username': 'mohamed',
                  'fullName': 'محمد علي',
                  'phone': '+201000000001',
                  'email': 'mohamed@example.com',
                  'jobTitle': 'مشرف',
                  'role': 'supervisor',
                  'roleName': 'مشرف',
                  'isActive': 1,
                },
                {
                  'id': 2,
                  'username': 'layla',
                  'fullName': 'ليلى حسن',
                  'phone': '+201000000002',
                  'email': 'layla@example.com',
                  'jobTitle': 'موظف',
                  'role': 'employee',
                  'roleName': 'موظف',
                  'isActive': 1,
                },
              ],
              'roles': [
                {'role': 'employee', 'name': 'موظف'},
                {'role': 'supervisor', 'name': 'مشرف'},
              ],
            },
          ));
          return;
        }
        if (options.method == 'POST' && options.path == '/api/admin/staff') {
          final data = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'success': true,
              'staff': {
                'id': 3,
                'username': data['username'],
                'fullName': data['fullName'],
                'role': data['role'],
                'profileImageUrl': null,
              },
            },
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          data: {'success': true},
        ));
      },
    ));
    return client;
  }

  Future<void> pumpStaffScreen(
    WidgetTester tester,
    Dio client, {
    bool canViewConversations = false,
    bool canViewTickets = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: StaffManagementScreen(
          adminToken: 'admin-token',
          currentAdminId: 'admin-1',
          canViewConversations: canViewConversations,
          canViewTickets: canViewTickets,
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('search opens a right-to-left tabbed staff profile',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    expect(find.text('إضافة موظف'), findsOneWidget);
    expect(find.text('محمد علي'), findsOneWidget);
    expect(find.text('ليلى حسن'), findsOneWidget);
    expect(
      tester.getRect(find.text('إضافة موظف')).center.dy,
      closeTo(tester.getRect(find.text('إدارة الموظفين')).center.dy, 1),
    );

    await tester.enterText(find.byType(TextField).first, 'layla@example.com');
    await tester.pumpAndSettle();
    expect(find.text('ليلى حسن'), findsOneWidget);
    expect(find.text('محمد علي'), findsNothing);

    await tester.tap(find.text('ليلى حسن'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('العودة للقائمة'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('البيانات الشخصية'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('ليلى حسن'))),
      TextDirection.rtl,
    );

    await tester.tap(find.byTooltip('تعديل البيانات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final supervisorOption = find.text('مشرف').last;
    expect(
      Directionality.of(tester.element(supervisorOption)),
      TextDirection.rtl,
    );
    await tester.tap(supervisorOption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('البيانات الشخصية'));
    await tester.pumpAndSettle();
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
    expect(find.text('إضافة صورة'), findsOneWidget);

    await tester.tap(find.byTooltip('العودة للقائمة'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الموظفين'), findsOneWidget);
  });

  testWidgets('staff profile actions share a row below dashboard shortcuts',
      (tester) async {
    final requests = <RequestOptions>[];
    final navigationKey = GlobalKey<DashboardNavigationState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          key: navigationKey,
          homeBuilder: (_) => const SizedBox.shrink(),
          routes: {
            DashboardNavigation.staffManagementRoute: (_) =>
                StaffManagementScreen(
                  adminToken: 'admin-token',
                  currentAdminId: 'admin-1',
                  onSessionExpired: fail,
                  client: createClient(requests),
                ),
          },
          onRouteChanged: (_) {},
          unreadConversationCount: 2,
          unreadTicketCount: 1,
        ),
      ),
    ));

    navigationKey.currentState!
        .pushNamed(DashboardNavigation.staffManagementRoute);
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();

    final backButton = find.byTooltip('العودة للقائمة');
    expect(
      find.descendant(of: backButton, matching: find.byIcon(Icons.arrow_back)),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byTooltip('تعديل البيانات')).center.dy,
      closeTo(tester.getRect(find.byTooltip('تعطيل الحساب')).center.dy, 1),
    );

    final editTop = tester.getTopLeft(find.byTooltip('تعديل البيانات')).dy;
    final conversationsBottom =
        tester.getBottomLeft(find.byTooltip('إدارة المحادثات')).dy;
    final ticketsBottom =
        tester.getBottomLeft(find.byTooltip('إدارة الشكاوى')).dy;
    expect(editTop, greaterThan(conversationsBottom));
    expect(editTop, greaterThan(ticketsBottom));

    await tester.tap(find.byTooltip('تعديل البيانات'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('staff ratings tab shows employee and general-admin records',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التقييمات'));
    await tester.pumpAndSettle();

    expect(find.textContaining('4.5 من 5'), findsOneWidget);
    expect(find.textContaining('محادثة #19'), findsOneWidget);
    expect(find.text('ممتاز'), findsOneWidget);
    expect(
      requests.any((request) => request.path == '/api/admin/staff/1/ratings'),
      isTrue,
    );

    await tester.tap(find.text('الإدارة العامة'));
    await tester.pumpAndSettle();
    expect(find.text('جيد'), findsOneWidget);
    expect(
      requests
          .any((request) => request.path == '/api/admin/staff/ratings/general'),
      isTrue,
    );
  });

  testWidgets('staff support history is permissioned and filterable',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(
      tester,
      createClient(requests),
      canViewConversations: true,
      canViewTickets: true,
    );

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();
    expect(find.text('المحادثات'), findsOneWidget);
    expect(find.text('الشكاوى'), findsOneWidget);

    await tester.tap(find.text('المحادثات'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/support/history/conversations' &&
          request.queryParameters['adminId'] == 'staff-1' &&
          request.queryParameters['userRole'] == 'all'),
      isTrue,
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    await tester.tap(find.text('السائق').last);
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/support/history/conversations' &&
          request.queryParameters['adminId'] == 'staff-1' &&
          request.queryParameters['userRole'] == 'driver'),
      isTrue,
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('يوم').last);
    await tester.pumpAndSettle();
    final dayRequest = requests.lastWhere((request) =>
        request.path == '/api/admin/support/history/conversations');
    final dayStart =
        DateTime.parse(dayRequest.queryParameters['startAt'] as String);
    final dayEnd =
        DateTime.parse(dayRequest.queryParameters['endAt'] as String);
    expect(dayEnd.difference(dayStart), const Duration(days: 1));

    await tester.tap(find.text('الشكاوى'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/support/history/tickets' &&
          request.queryParameters['adminId'] == 'staff-1'),
      isTrue,
    );
  });

  testWidgets('staff support history tabs stay hidden without permissions',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();

    expect(find.text('المحادثات'), findsNothing);
    expect(find.text('الشكاوى'), findsNothing);
    expect(
      requests.any(
          (request) => request.path.startsWith('/api/admin/support/history/')),
      isFalse,
    );
  });

  testWidgets('staff creation requires eight-character passwords',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.text('إضافة موظف'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'new-operator');
    await tester.enterText(find.byType(TextFormField).last, '1234567');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(
        find.text('كلمة المرور يجب أن تكون 8 أحرف على الأقل'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '12345678');
    await tester.tap(find.text('البيانات الشخصية'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'موظف جديد');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final createRequest = requests.lastWhere((request) =>
        request.method == 'POST' && request.path == '/api/admin/staff');
    expect(createRequest.data['password'], '12345678');
    expect(createRequest.data['fullName'], 'موظف جديد');
    expect(find.byTooltip('العودة للقائمة'), findsOneWidget);
    await tester.tap(find.text('البيانات الشخصية'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة صورة'), findsOneWidget);
  });

  testWidgets('password reset enables eight characters, not seven',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.byTooltip('إجراءات الموظف').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة تعيين كلمة المرور'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('staffPasswordReset')), '1234567');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'تغيير كلمة المرور'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
        find.byKey(const ValueKey('staffPasswordReset')), '12345678');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'تغيير كلمة المرور'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('تغيير كلمة المرور'));
    await tester.pumpAndSettle();
    final resetRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' &&
        request.path == '/api/admin/staff/1/password');
    expect(resetRequest.data['password'], '12345678');
  });

  testWidgets('saving with a missing profile name shows validation then saves',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.text('إضافة موظف'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'new-operator');
    await tester.enterText(find.byType(TextFormField).last, '12345678');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('الاسم الكامل مطلوب'), findsOneWidget);
    expect(
      requests.where((request) =>
          request.method == 'POST' && request.path == '/api/admin/staff'),
      isEmpty,
    );

    await tester.enterText(find.byType(TextFormField).first, 'موظف جديد');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(
      requests.where((request) =>
          request.method == 'POST' && request.path == '/api/admin/staff'),
      hasLength(1),
    );
  });
}
