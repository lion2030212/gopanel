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
        'role': 'employee',
        'permissions': ['map.view', 'rides.read'],
      },
    });

    expect(session.role, 'employee');
    expect(session.can('map.view'), isTrue);
    expect(session.can('staff.manage'), isFalse);
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
    expect(find.text('الإدارة والتحكم'), findsNothing);
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
