import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;

const _localAdminApiBaseUrl = 'http://localhost:3000';
const _androidEmulatorApiBaseUrl = 'http://10.0.2.2:3000';
const _deployedAdminApiBaseUrl = 'https://goserver-i3ab.onrender.com';

String resolveAdminApiBaseUrl({
  required String host,
  String configuredUrl = const String.fromEnvironment('API_BASE_URL'),
  bool? debugMode,
  TargetPlatform? targetPlatform,
}) {
  final override = configuredUrl.trim();
  if (override.isNotEmpty) return override;

  if ((debugMode ?? kDebugMode) &&
      !kIsWeb &&
      (targetPlatform ?? defaultTargetPlatform) == TargetPlatform.android) {
    return _androidEmulatorApiBaseUrl;
  }

  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost' || normalizedHost == '127.0.0.1') {
    return _localAdminApiBaseUrl;
  }

  return _deployedAdminApiBaseUrl;
}

final adminApiBaseUrl = resolveAdminApiBaseUrl(host: Uri.base.host);
