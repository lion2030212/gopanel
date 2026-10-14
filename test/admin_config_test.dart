import 'package:admin_panel/core/admin_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAdminApiBaseUrl', () {
    test('uses localhost for local development hosts', () {
      expect(
        resolveAdminApiBaseUrl(host: 'localhost'),
        'http://localhost:3000',
      );
      expect(
        resolveAdminApiBaseUrl(host: '127.0.0.1'),
        'http://localhost:3000',
      );
    });

    test('uses Render for deployed and unknown hosts', () {
      expect(
        resolveAdminApiBaseUrl(host: 'gofast.github.io'),
        'https://goserver-i3ab.onrender.com',
      );
      expect(
        resolveAdminApiBaseUrl(host: 'admin.example.com'),
        'https://goserver-i3ab.onrender.com',
      );
      expect(
        resolveAdminApiBaseUrl(host: ''),
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
