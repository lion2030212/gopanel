import 'package:admin_panel/screens/admin_settings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads and saves pricing, search, and wallet settings',
      (tester) async {
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
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('baseFare')))
          .controller!
          .text,
      '20.00',
    );
    expect(requests.first.path, '/api/admin/settings');
    expect(requests.first.headers['Authorization'], 'Bearer admin-token');

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
    await tester.tap(find.text('حفظ إعدادات البحث'));
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/admin/settings/search');
    expect(requests.last.data['nearRadiusMeters'], '750');

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
}
