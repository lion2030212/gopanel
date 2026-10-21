import 'package:flutter/gestures.dart';
import 'package:admin_panel/core/admin_session.dart';
import 'package:admin_panel/screens/ride_history_screen.dart';
import 'package:admin_panel/widgets/admin_drawer.dart';
import 'package:admin_panel/widgets/dashboard_navigation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session parses server role and permission keys', () {
    final session = AdminSession.fromLoginResponse({
      'token': 'staff-token',
      'admin': {
        'id': 'staff-12',
        'username': 'operator',
        'fullName': 'محمد علي',
        'profileImageUrl': 'https://example.test/staff.jpg',
        'role': 'employee',
        'permissions': ['map.view', 'rides.read'],
      },
    });

    expect(session.role, 'employee');
    expect(session.fullName, 'محمد علي');
    expect(session.profileImageUrl, 'https://example.test/staff.jpg');
    expect(session.can('map.view'), isTrue);
    expect(session.can('staff.manage'), isFalse);
  });

  testWidgets('drawer shows employee identity and colored fractional rating',
      (tester) async {
    var rating = 3.5;
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.path, '/api/admin/my-ratings');
        expect(options.headers['Authorization'], 'Bearer staff-token');
        handler.resolve(Response(
          requestOptions: options,
          data: {'averageRating': rating},
        ));
      },
    ));

    for (final entry in [
      (rating: 2.9, color: Colors.red.shade700),
      (rating: 3.5, color: Colors.amber.shade800),
      (rating: 4.5, color: Colors.green.shade700),
    ]) {
      rating = entry.rating;
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: AdminDrawer(
            adminId: 'staff-12',
            adminToken: 'staff-token',
            username: 'operator',
            fullName: 'محمد علي',
            profileImageUrl:
              'https://firebasestorage.googleapis.com/v0/b/godrive-d7f94.firebasestorage.app/o/staff-profiles%2F12%2Fstaff.png?alt=media&token=test',
            client: client,
            selectedDestination: AdminDestination.driverMap,
            permissions: const {'map.view'},
            onDestinationSelected: (_) {},
            onLogout: () {},
          ),
          body: const SizedBox.expand(),
        ),
      ));
      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('مرحبًا، محمد'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text(entry.rating.toStringAsFixed(1)), findsOneWidget);
      final starsFinder = find.byKey(const ValueKey('admin-rating-stars'));
      final filledStar = tester.widget<Icon>(find
          .descendant(
            of: starsFinder,
            matching: find.byIcon(Icons.star),
          )
          .first);
      expect(filledStar.color, entry.color);
      if (entry.rating == 3.5) {
        final aligns = tester.widgetList<Align>(find.descendant(
          of: starsFinder,
          matching: find.byType(Align),
        ));
        expect(aligns.elementAt(3).widthFactor, 0.5);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('drawer wheel input scrolls the menu', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          permissions: AdminSession.managerPermissions,
          onDestinationSelected: (_) {},
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final listFinder = find.byType(ListView);
    final scrollable = tester.state<ScrollableState>(find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    ));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(listFinder),
      scrollDelta: const Offset(0, 240),
    ));
    await tester.pump();

    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('general admin uses fallback identity and shared rating',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          data: {'averageRating': 4.5},
        ));
      },
    ));
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          adminId: 'admin-panel',
          adminToken: 'admin-token',
          username: 'admin-panel',
          client: client,
          selectedDestination: AdminDestination.driverMap,
          permissions: const {'map.view'},
          onDestinationSelected: (_) {},
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('مرحبًا، مدير GoFast'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
  });

  testWidgets('employee drawer hides restricted destinations', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          permissions: const {
            'map.view',
            'rides.read',
            'rides.cancel',
            'rides.complete',
            'support.conversations',
          },
          onDestinationSelected: (_) {},
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('سجل الرحلات'), findsOneWidget);
    expect(find.text('إدارة المحادثات'), findsOneWidget);
    expect(find.text('إدارة الشكاوى'), findsNothing);
    expect(find.text('إرسال تنبيهات'), findsNothing);
    expect(find.text('إدارة الموظفين'), findsNothing);
    expect(find.text('الإدارة المالية'), findsNothing);
    expect(find.text('الإدارة والتحكم'), findsNothing);
  });

  testWidgets('financial management drawer entry requires finance permission',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          permissions: const {'map.view', 'finance.reports.read'},
          onDestinationSelected: (_) {},
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('الإدارة المالية'), findsOneWidget);
    expect(find.text('إدارة الموظفين'), findsNothing);
  });

  testWidgets('admin drawer uses a compact width', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: AdminDrawer(
          selectedDestination: AdminDestination.driverMap,
          onDestinationSelected: (_) {},
          onLogout: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ));

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(tester.widget<Drawer>(find.byType(Drawer)).width, 240);
  });

  testWidgets('complaint shortcut is absent without ticket permission',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardNavigation(
          homeBuilder: (_) => const SizedBox.shrink(),
          routes: const {},
          onRouteChanged: (_) {},
          showTicketShortcut: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('إدارة المحادثات'), findsOneWidget);
    expect(find.byTooltip('إدارة الشكاوى'), findsNothing);
  });

  testWidgets('employee can cancel rides but cannot reverse settlement',
      (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'GET' && options.path == '/api/admin/rides') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'rides': [
                {'rideId': 52, 'status': 'in_progress'},
              ],
              'total': 1,
            },
          ));
          return;
        }
        if (options.method == 'GET' && options.path == '/api/admin/rides/52') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'ride': {
                'rideId': 52,
                'status': 'in_progress',
                'canReverseSettlement': true,
              },
            },
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
          adminToken: 'employee-token',
          canReverseSettlement: false,
          onSessionExpired: (_) =>
              fail('employee session should remain active'),
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('رحلة #52'));
    await tester.pumpAndSettle();

    expect(find.text('إلغاء الرحلة مجانًا'), findsOneWidget);
    expect(find.text('إنهاء الرحلة'), findsOneWidget);
    expect(find.text('عكس التسوية'), findsNothing);
  });
}
