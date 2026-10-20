import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueChanged;

import 'admin_config.dart';

Dio createAdminApiClient({required ValueChanged<String> onSessionExpired}) {
  final client = Dio(BaseOptions(baseUrl: adminApiBaseUrl));
  client.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) {
      if (error.response?.statusCode == 401) {
        final responseData = error.response?.data;
        final message =
            responseData is Map ? responseData['message']?.toString() : null;
        onSessionExpired(message ?? 'جلسة الإدارة غير صالحة');
      }
      handler.next(error);
    },
  ));
  return client;
}
