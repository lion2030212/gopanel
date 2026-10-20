import 'dart:convert';
import 'dart:typed_data';

import 'package:admin_panel/core/admin_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode({
          'code': 'ADMIN_SESSION_REPLACED',
          'message': 'تم تسجيل الدخول إلى الحساب من جهاز آخر',
        }),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  test('401 responses invalidate the active admin session', () async {
    final messages = <String>[];
    final client = createAdminApiClient(onSessionExpired: messages.add);
    client.httpClientAdapter = UnauthorizedAdapter();

    await expectLater(
      client.get<void>('/api/admin/session'),
      throwsA(isA<DioException>()),
    );

    expect(messages, ['تم تسجيل الدخول إلى الحساب من جهاز آخر']);
    client.close(force: true);
  });
}
