import 'package:admin_panel/core/admin_config.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAdminApiBaseUrl', () {
    test('uses localhost for local development hosts', () {
      expect(
        resolveAdminApiBaseUrl(
          host: 'localhost',
          targetPlatform: TargetPlatform.windows,
        ),
        'http://localhost:3000',
      );
      expect(
        resolveAdminApiBaseUrl(
          host: '127.0.0.1',
          targetPlatform: TargetPlatform.windows,
        ),
        'http://localhost:3000',
      );
    });

    test('uses Render for deployed and unknown hosts', () {
      expect(
        resolveAdminApiBaseUrl(
          host: 'gofast.github.io',
          targetPlatform: TargetPlatform.windows,
        ),
        'https://goserver-i3ab.onrender.com',
      );
      expect(
        resolveAdminApiBaseUrl(
          host: 'admin.example.com',
          targetPlatform: TargetPlatform.windows,
        ),
        'https://goserver-i3ab.onrender.com',
      );
      expect(
        resolveAdminApiBaseUrl(
          host: '',
          targetPlatform: TargetPlatform.windows,
        ),
        'https://goserver-i3ab.onrender.com',
      );
    });

    test('uses the host emulator address for Android debug builds', () {
      expect(
        resolveAdminApiBaseUrl(
          host: '',
          debugMode: true,
          targetPlatform: TargetPlatform.android,
        ),
        'http://10.0.2.2:3000',
      );
    });

    test('keeps the deployed URL for Android release builds', () {
      expect(
        resolveAdminApiBaseUrl(
          host: '',
          debugMode: false,
          targetPlatform: TargetPlatform.android,
        ),
        'https://goserver-i3ab.onrender.com',
      );
    });

    test('uses a non-empty configured URL as an override', () {
      expect(
        resolveAdminApiBaseUrl(
          host: 'gofast.github.io',
          configuredUrl: ' https://api.example.com ',
        ),
        'https://api.example.com',
      );
    });
  });
}
