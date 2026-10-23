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
            options.path.endsWith('/sent-notifications')) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'items': [
                {
                  'id': 42,
                  'category': 'promotion',
                  'title': 'عرض خاص',
                  'body': 'خصم على الرحلات',
                  'createdAt': DateTime.now().toIso8601String(),
                  'driverCount': 2,
                  'riderCount': 3,
                  'acceptedCount': 4,
                  'acceptedDevices': 4,
                  'failedCount': 1,
                  'noTokenCount': 0,
                  'readCount': 2,
                },
              ],
              'hasMore': false,
              'roleCounts': {'allCount': 1, 'driverCount': 1, 'riderCount': 1},
              'categoryCounts': {
                'allCount': 1,
                'customerServiceCount': 0,
                'promotionCount': 1,
                'guidanceCount': 0,
              },
            },
          ));
          return;
        }
        if (options.method == 'GET' &&
            (options.path.startsWith('/api/admin/staff/') ||
                options.path == '/api/admin/staff/ratings/general')) {
          final generalAdmin = options.path.endsWith('/general');
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'averageRating': generalAdmin ? 3.0 : 4.5,
              'ratingsCount': 2,
              'ratings': [
                {
                  'id': 1,
                  'interactionType': 'conversation',
                  'interactionId': generalAdmin ? 21 : 19,
                  'raterRole': 'driver',
                  'raterName': 'سائق',
                  'stars': generalAdmin ? 4 : 5,
                  'comment': generalAdmin ? 'جيد' : 'ممتاز',
                  'createdAt': DateTime.now().toIso8601String(),
                },
                {
                  'id': 2,
                  'interactionType': 'conversation',
                  'interactionId': generalAdmin ? 22 : 20,
                  'raterRole': 'driver',
                  'raterName': 'سائق آخر',
                  'stars': generalAdmin ? 2 : 1,
                  'comment': generalAdmin ? 'يحتاج تحسين' : 'ضعيف',
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
                  'profileImageUrl':
                      'https://firebasestorage.googleapis.com/v0/b/godrive-d7f94.firebasestorage.app/o/staff-profiles%2F1%2Fstaff.png?alt=media&token=test',
                  'isActive': 1,
                  'accountStatus': 'active',
                  'presenceStatus': 'active',
                  'lastOnlineAt': DateTime.now().toIso8601String(),
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
                  'accountStatus': 'active',
                  'presenceStatus': 'inactive',
                  'lastOnlineAt': null,
                },
                {
                  'id': 3,
                  'username': 'sara',
                  'fullName': 'سارة أحمد',
                  'role': 'employee',
                  'roleName': 'موظف',
                  'isActive': 1,
                  'accountStatus': 'suspended',
                  'presenceStatus': 'suspended',
                  'lastOnlineAt': DateTime.now().toIso8601String(),
                },
              ],
              'counts': {
                'all': 3,
                'active': 1,
                'inactive': 1,
                'suspended': 1,
              },
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
        if (options.method == 'GET' &&
            options.path.startsWith('/api/admin/support/history/')) {
          final tickets = options.path.endsWith('/tickets');
          handler.resolve(Response(
            requestOptions: options,
            data: {
              tickets ? 'tickets' : 'conversations': [],
              'total': 8,
              'roleCounts': {'all': 8, 'driver': 3, 'rider': 5},
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
    final staffTile = find.ancestor(
      of: find.text('محمد علي'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: staffTile, matching: find.byType(Image)),
      findsOneWidget,
    );
    final staffAvatar = tester.widget<CircleAvatar>(
      find.descendant(of: staffTile, matching: find.byType(CircleAvatar)),
    );
    expect(staffAvatar.backgroundImage, isNull);
    expect(staffAvatar.child, isA<ClipOval>());
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
      closeTo(tester.getRect(find.byTooltip('إيقاف الحساب')).center.dy, 1),
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

  testWidgets('employee sent notifications show recipient and status counts',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('التنبيهات المرسلة'));
    await tester.tap(find.text('التنبيهات المرسلة'));
    await tester.pumpAndSettle();

    expect(find.text('أسبوع'), findsOneWidget);
    expect(find.text('عرض خاص'), findsOneWidget);
    expect(find.textContaining('سائقون 2 · ركاب 3 · مقروء 2'), findsOneWidget);
    await tester.tap(find.text('عرض خاص'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مقبول عبر FCM: 4 مستلم'), findsOneWidget);
    expect(find.textContaining('فشل 1'), findsOneWidget);
    expect(find.text('خدمة العملاء (0)'), findsOneWidget);
    expect(find.text('توجيه (0)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('الكل (1)'),
      ),
      findsOneWidget,
    );
    expect(find.text('السائق (1)'), findsOneWidget);
    expect(find.text('الراكب (1)'), findsOneWidget);
    final initialRequest = requests.firstWhere((request) =>
      request.path == '/api/admin/staff/1/sent-notifications');
    final weekStart = DateTime.parse(initialRequest.queryParameters['startAt'] as String);
    final weekEnd = DateTime.parse(initialRequest.queryParameters['endAt'] as String);
    expect(weekStart.weekday, DateTime.saturday);
    expect(weekEnd.difference(weekStart), const Duration(days: 7));
    expect(
      requests.any((request) =>
          request.path == '/api/admin/staff/1/sent-notifications'),
      isTrue,
    );

    await tester.tap(find.text('الراكب (1)'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/staff/1/sent-notifications' &&
          request.queryParameters['role'] == 'rider'),
      isTrue,
    );

    await tester.tap(find.text('عرض ترويجي (1)'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/staff/1/sent-notifications' &&
          request.queryParameters['role'] == 'rider' &&
          request.queryParameters['category'] == 'promotion'),
      isTrue,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('اليوم').last);
    await tester.pumpAndSettle();
    final todayRequest = requests.lastWhere((request) =>
        request.path == '/api/admin/staff/1/sent-notifications');
    final todayStart = DateTime.parse(todayRequest.queryParameters['startAt'] as String);
    final todayEnd = DateTime.parse(todayRequest.queryParameters['endAt'] as String);
    expect(todayEnd.difference(todayStart), const Duration(days: 1));
    expect(todayRequest.queryParameters['category'], 'promotion');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مدة محددة').last);
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.text('تطبيق').last);
    await tester.pumpAndSettle();
    final customRequest = requests.lastWhere((request) =>
      request.path == '/api/admin/staff/1/sent-notifications');
    final customStart = DateTime.parse(customRequest.queryParameters['startAt'] as String);
    final customEnd = DateTime.parse(customRequest.queryParameters['endAt'] as String);
    expect(customEnd.difference(customStart), const Duration(days: 1));
    expect(customRequest.queryParameters['category'], 'promotion');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر').last);
    await tester.pumpAndSettle();
    final monthRequest = requests.lastWhere((request) =>
      request.path == '/api/admin/staff/1/sent-notifications');
    final monthStart = DateTime.parse(monthRequest.queryParameters['startAt'] as String);
    final monthEnd = DateTime.parse(monthRequest.queryParameters['endAt'] as String);
    expect(monthStart.day, 1);
    expect(monthEnd.day, 1);
    expect(monthStart.month == monthEnd.month, isFalse);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكل').last);
    await tester.pumpAndSettle();
    final allRequest = requests.lastWhere((request) =>
      request.path == '/api/admin/staff/1/sent-notifications');
    expect(allRequest.queryParameters.containsKey('startAt'), isFalse);
    expect(allRequest.queryParameters.containsKey('endAt'), isFalse);
  });

  testWidgets('staff status filters show counts and toggle account access',
      (tester) async {
    final requests = <RequestOptions>[];
    await pumpStaffScreen(tester, createClient(requests));

    expect(find.text('الكل (3)'), findsOneWidget);
    expect(find.text('نشط (1)'), findsOneWidget);
    expect(find.text('غير نشط (1)'), findsOneWidget);
    expect(find.text('محظور / موقوف (1)'), findsOneWidget);

    await tester.tap(find.text('نشط (1)'));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) =>
          request.path == '/api/admin/staff' &&
          request.queryParameters['status'] == 'active'),
      isTrue,
    );

    await tester.tap(find.text('الكل (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إجراءات الموظف').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إيقاف الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    final statusRequest = requests.lastWhere((request) =>
        request.method == 'PATCH' &&
        request.path == '/api/admin/staff/1/status');
    expect(statusRequest.data['status'], 'suspended');

    final suspendedSegment = find.text('محظور / موقوف (1)');
    await tester.ensureVisible(suspendedSegment);
    await tester.tap(suspendedSegment);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إجراءات الموظف').last);
    await tester.pumpAndSettle();
    expect(find.text('تفعيل الحساب'), findsOneWidget);
    expect(find.text('تعطيل الحساب'), findsNothing);
    await tester.tap(find.text('تفعيل الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    final activationRequest = requests.lastWhere((request) =>
      request.method == 'PATCH' &&
      request.path == '/api/admin/staff/3/status');
    expect(activationRequest.data['status'], 'active');
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
    expect(find.text('1 نجمة (1)'), findsOneWidget);
    expect(find.text('الكل (2)'), findsOneWidget);
    expect(
      requests.any((request) => request.path == '/api/admin/staff/1/ratings'),
      isTrue,
    );

    await tester.tap(find.text('1 نجمة (1)'));
    await tester.pumpAndSettle();
    expect(find.text('ضعيف'), findsOneWidget);
    expect(find.text('ممتاز'), findsNothing);
    await tester.tap(find.text('الكل (2)'));
    await tester.pumpAndSettle();
    expect(find.text('ممتاز'), findsOneWidget);

    await tester.tap(find.text('الإدارة العامة'));
    await tester.pumpAndSettle();
    expect(find.text('جيد'), findsOneWidget);
    expect(find.text('2 نجمة (1)'), findsOneWidget);
    await tester.tap(find.text('2 نجمة (1)'));
    await tester.pumpAndSettle();
    expect(find.text('يحتاج تحسين'), findsOneWidget);
    expect(find.text('جيد'), findsNothing);
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

    await tester.ensureVisible(find.text('المحادثات'));
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
    expect(find.text('الكل (8)'), findsOneWidget);
    expect(find.text('السائق (3)'), findsOneWidget);
    expect(find.text('الراكب (5)'), findsOneWidget);
    await tester.tap(find.text('السائق (3)'));
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
    expect(find.text('الكل (8)'), findsOneWidget);
    expect(find.text('السائق (3)'), findsOneWidget);
    expect(find.text('الراكب (5)'), findsOneWidget);
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
