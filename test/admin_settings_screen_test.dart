import 'package:admin_panel/screens/admin_settings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads and saves pricing, search, and wallet settings',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.method == 'GET') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'success': true,
              'settings': {
                'pricing': {
                  'standard': {
                    'baseFare': '20.00',
                    'perKmRate': '5.00',
                    'waitingPerMinute': '1.00',
                    'cancellationFee': '20.00',
                    'minimumFare': '10.00',
                    'commissionPercent': '25.00',
                  },
                  'comfort': {},
                  'scooter': {},
                },
                'search': {
                  'nearRadiusMeters': '500.00',
                  'maxDistanceKm': '5.00',
                  'categories': {
                    'standard': {
                      'nearRadiusMeters': '500.00',
                      'maxDistanceKm': '5.00',
                      'visible': true,
                    },
                    'comfort': {
                      'nearRadiusMeters': '350.00',
                      'maxDistanceKm': '4.00',
                      'visible': false,
                    },
                    'scooter': {
                      'nearRadiusMeters': '250.00',
                      'maxDistanceKm': '3.00',
                      'visible': true,
                    },
                  },
                },
                'wallet': {
                  'driverDebtLimit': '-300.00',
                  'riderDebtLimit': '-30.00',
                },
                'versions': {
                  'minimumRiderBuild': '0.00',
                  'minimumDriverBuild': '0.00',
                },
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminSettingsScreen(
          adminToken: 'admin-token',
          onSessionExpired: fail,
          client: client,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('الإدارة والتحكم'), findsOneWidget);
    expect(find.text('المراقبة والأمان'), findsNothing);
    expect(find.text('مراقبة الكوبونات'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('baseFare')))
          .controller!
          .text,
      '20.00',
    );
    expect(requests.first.path, '/api/admin/settings');
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');

    await tester.tap(find.byKey(const ValueKey('pricingCategory')));
    await tester.pumpAndSettle();
    expect(find.text('GoFast سوزوكي'), findsWidgets);
    expect(find.text('GoTalabat دليفيرى'), findsWidgets);
    expect(find.text('GoScooter المنجز'), findsWidgets);
    await tester.tap(find.text('GoFast سوزوكي').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('perKmRate')), '6.25');
    await tester.tap(find.text('حفظ أسعار الفئة'));
    await tester.pumpAndSettle();

    final pricingRequest = requests.last;
    expect(pricingRequest.method, 'PATCH');
    expect(pricingRequest.path, '/api/admin/settings/pricing/standard');
    expect(pricingRequest.data['perKmRate'], '6.25');

    await tester.tap(find.text('البحث'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('nearRadiusMeters')), '750');
    await tester.enterText(find.byKey(const ValueKey('maxDistanceKm')), '8');
    await tester.tap(find.byKey(const ValueKey('searchVisibility-standard')));
    await tester.tap(find.text('حفظ إعدادات الفئة'));
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/settings/search/standard');
    expect(requests.last.data['nearRadiusMeters'], '750');
    expect(requests.last.data['maxDistanceKm'], '8');
    expect(requests.last.data['visible'], false);

    await tester.tap(find.byKey(const ValueKey('searchCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GoTalabat دليفيرى').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('nearRadiusMeters')))
          .controller!
          .text,
      '350.00',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('maxDistanceKm')))
          .controller!
          .text,
      '4.00',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('searchVisibility-comfort')),
          )
          .value,
      false,
    );

    await tester.tap(find.text('المحفظة'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('driverDebtLimit')), '-250');
    await tester.tap(find.text('حفظ حدود المحافظ'));
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/settings/wallet');
    expect(requests.last.data['driverDebtLimit'], '-250');

    await tester.tap(find.text('الإصدارات'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('minimumRiderBuild')))
          .controller!
          .text,
      '0',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('minimumDriverBuild')))
          .controller!
          .text,
      '0',
    );
    final requestCountBeforeInvalidSave = requests.length;
    await tester.enterText(
        find.byKey(const ValueKey('minimumRiderBuild')), '42.0');
    await tester.tap(find.text('حفظ حدود الإصدارات'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(requestCountBeforeInvalidSave));
    expect(find.text('تحقق من القيم المدخلة قبل الحفظ'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('minimumRiderBuild')), '42');
    await tester.tap(find.text('حفظ حدود الإصدارات'));
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/settings/versions');
    expect(requests.last.data['minimumRiderBuild'], '42');
    expect(requests.last.data['minimumDriverBuild'], '0');
  });

  testWidgets('manager can monitor security and block or unblock an IP',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.path == '/api/admin/settings') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'success': true,
              'settings': {
                'pricing': {'standard': {}, 'comfort': {}, 'scooter': {}},
                'search': {},
                'wallet': {},
                'versions': {},
              },
            },
          ));
          return;
        }
        if (options.path == '/api/admin/security/overview') {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'success': true,
              'security': {
                'status': 'red',
                'windowMinutes': 5,
                'failureCounts': {'day': 2, 'week': 6, 'month': 12},
                'alerts': [
                  {
                    'ipAddress': '192.0.2.21',
                    'failureCount': 10,
                    'severity': 'red',
                  },
                ],
                'recentFailures': [
                  {
                    'id': 5,
                    'username': 'operator',
                    'ipAddress': '192.0.2.21',
                    'failureReason': 'invalid_credentials',
                    'attemptedAt': '2026-11-05T10:15:00Z',
                  },
                ],
                'sessions': [
                  {
                    'adminId': 'admin-panel',
                    'ipAddress': '192.0.2.22',
                    'loginAt': '2026-11-05T09:00:00Z',
                    'logoutAt': null,
                    'active': 1,
                  },
                ],
                'blockedIps': [
                  {
                    'ipAddress': '192.0.2.23',
                    'reason': 'manual block',
                    'blockedBy': 'admin-panel',
                  },
                ],
              },
            },
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: options.method == 'POST' ? 201 : 200,
          data: {'success': true},
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminSettingsScreen(
          adminToken: 'manager-token',
          onSessionExpired: fail,
          client: client,
          canManageSecurity: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المراقبة والأمان'));
    await tester.pumpAndSettle();

    expect(find.text('خطر أمني'), findsOneWidget);
    expect(find.text('operator'), findsOneWidget);
    expect(find.text('admin-panel'), findsOneWidget);
    expect(find.byKey(const ValueKey('applySecuritySearch')), findsNothing);
    expect(
      tester.widget<Wrap>(find.byKey(const ValueKey('securityPeriodFilters'))).alignment,
      WrapAlignment.center,
    );
    expect(
      tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('security-period-count-day')),
        matching: find.byType(Text),
      )).data,
      '2',
    );
    expect(find.byKey(const ValueKey('security-period-count-custom')), findsNothing);
    expect(
      requests.last.headers['Authorization'],
      'Bearer manager-token',
    );

    await tester.tap(find.byKey(const ValueKey('security-period-week')));
    await tester.pumpAndSettle();
    expect(
      requests.last.queryParameters['period'],
      'week',
    );
    final overviewRequestCount = requests
        .where((request) => request.path == '/api/admin/security/overview')
        .length;
    await tester.enterText(
      find.byKey(const ValueKey('securitySearchInput')),
      '192.0.2.21',
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(
      requests.where((request) => request.path == '/api/admin/security/overview'),
      hasLength(overviewRequestCount),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    final searchRequest = requests.lastWhere(
      (request) => request.path == '/api/admin/security/overview',
    );
    expect(searchRequest.queryParameters['period'], 'week');
    expect(searchRequest.queryParameters['search'], '192.0.2.21');

    await tester.tap(find.byKey(const ValueKey('addIpBlock')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('securityBlockIpInput')),
      '192.0.2.24',
    );
    await tester.enterText(
      find.byKey(const ValueKey('securityBlockReasonInput')),
      'repeated failures',
    );
    await tester.tap(find.byKey(const ValueKey('securityConfirmBlock')));
    await tester.pumpAndSettle();
    final blockRequest = requests.firstWhere(
      (request) => request.method == 'POST',
    );
    expect(blockRequest.path, '/api/admin/security/ip-blocks');
    expect(blockRequest.data['ipAddress'], '192.0.2.24');
    expect(blockRequest.headers['Authorization'], 'Bearer manager-token');

    await tester.ensureVisible(
      find.byKey(const ValueKey('unblock-ip-192.0.2.23')),
    );
    await tester.tap(find.byKey(const ValueKey('unblock-ip-192.0.2.23')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('securityConfirmUnblock')));
    await tester.pumpAndSettle();
    final unblockRequest = requests.lastWhere(
      (request) => request.method == 'DELETE',
    );
    expect(unblockRequest.method, 'DELETE');
    expect(
      unblockRequest.path,
      '/api/admin/security/ip-blocks/192.0.2.23',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('security-period-custom')),
    );
    await tester.tap(find.byKey(const ValueKey('security-period-custom')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('مخصص'), findsOneWidget);
  });

  testWidgets('coupon permission adds a monitoring tab under admin controls',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        if (options.path == '/api/admin/settings') {
          handler.resolve(Response(requestOptions: options, data: {
            'success': true,
            'settings': {
              'pricing': {'standard': {}, 'comfort': {}, 'scooter': {}},
              'search': {},
              'wallet': {},
              'versions': {},
            },
          }));
          return;
        }
        handler.resolve(Response(requestOptions: options, data: {
          'success': true,
          'analytics': {
            'activeCoupons': 1,
            'totalCouponUses': 0,
            'totalDiscountSpend': 0,
            'current': {},
            'previous': {},
          },
          'events': [],
          'total': 0,
        }));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminSettingsScreen(
          adminToken: 'manager-token',
          onSessionExpired: fail,
          client: client,
          canManageCoupons: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('الإدارة والتحكم'), findsOneWidget);
    expect(find.text('مراقبة الكوبونات'), findsOneWidget);
    await tester.tap(find.text('مراقبة الكوبونات'));
    await tester.pumpAndSettle();

    expect(find.text('مراقبة وأمان الكوبونات'), findsOneWidget);
    expect(find.text('الكوبونات النشطة الآن'), findsOneWidget);
    final monitoringRequest = requests.firstWhere(
      (request) => request.path == '/api/admin/coupons/monitoring',
    );
    expect(monitoringRequest.headers['Authorization'], 'Bearer manager-token');
  });
}
