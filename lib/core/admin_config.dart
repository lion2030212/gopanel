const _localAdminApiBaseUrl = 'http://localhost:3000';
const _deployedAdminApiBaseUrl = 'https://goserver-i3ab.onrender.com';

String resolveAdminApiBaseUrl({
  required String host,
  String configuredUrl = const String.fromEnvironment('API_BASE_URL'),
}) {
  final override = configuredUrl.trim();
  if (override.isNotEmpty) return override;

  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost' || normalizedHost == '127.0.0.1') {
    return _localAdminApiBaseUrl;
  }

  return _deployedAdminApiBaseUrl;
}

final adminApiBaseUrl = resolveAdminApiBaseUrl(host: Uri.base.host);
