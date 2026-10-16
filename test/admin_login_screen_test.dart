import 'package:admin_panel/core/admin_session.dart';
import 'package:admin_panel/screens/admin_login_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Arabic heading and disables login during server lockout',
      (tester) async {
    final requests = <RequestOptions>[];
    final client = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        handler.reject(DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 429,
            data: {
              'success': false,
              'message': 'تم إيقاف الدخول مؤقتًا',
              'retryAfterSeconds': 120,
            },
          ),
        ));
      },
    ));

    await tester.pumpWidget(MaterialApp(
      home: AdminLoginScreen(
        client: client,
        onAuthenticated: (AdminSession _) {},
      ),
    ));

    expect(find.text('دخول الادارة'), findsOneWidget);
    final frameRect = tester.getRect(
      find.byKey(const Key('admin-login-heading-frame')),
    );
    final listRect = tester.getRect(find.byType(ListView));
    final usernameRect = tester.getRect(find.byType(TextField).at(0));
    expect(frameRect.width, lessThan(usernameRect.width));
    expect(frameRect.center.dx, closeTo(listRect.center.dx, 0.5));
    expect(frameRect.top, closeTo(listRect.top, 0.5));
    expect(usernameRect.top - frameRect.bottom, closeTo(48, 0.5));

    await tester.enterText(find.byType(TextField).at(0), 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'incorrect');
    final loginButton = find.byType(FilledButton);
    final onPressed = tester.widget<FilledButton>(loginButton).onPressed;
    expect(onPressed, isNotNull);
    onPressed!();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(milliseconds: 500),
    );

    expect(requests, hasLength(1));
    expect(requests.single.path, '/api/admin/login');
    expect(find.text('دخول بعد 02:00'), findsOneWidget);
    expect(find.text('تم إيقاف الدخول مؤقتًا (02:00)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('دخول بعد 01:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('دخول'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    client.close(force: true);
  });
}