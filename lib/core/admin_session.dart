class AdminSession {
  const AdminSession({
    required this.token,
    required this.id,
    required this.username,
    this.fullName,
    this.profileImageUrl,
    required this.role,
    required this.permissions,
  });

  static const Set<String> managerPermissions = {
    'map.view',
    'rides.read',
    'rides.cancel',
    'rides.complete',
    'rides.reverse_settlement',
    'drivers.manage',
    'riders.manage',
    'coupons.manage',
    'notifications.send',
    'settings.manage',
    'support.conversations',
    'support.tickets',
    'staff.manage',
    'finance.reports.read',
    'security.manage',
  };

  final String token;
  final String id;
  final String username;
  final String? fullName;
  final String? profileImageUrl;
  final String role;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  Map<String, dynamic> toJson() => {
        'token': token,
        'id': id,
        'username': username,
        'fullName': fullName,
        'profileImageUrl': profileImageUrl,
        'role': role,
        'permissions': permissions.toList(),
      };

  factory AdminSession.fromJson(Map<String, dynamic> json) {
    final token = json['token']?.toString();
    final id = json['id']?.toString();
    final username = json['username']?.toString();
    final role = json['role']?.toString();
    final rawPermissions = json['permissions'];
    if (token == null ||
        token.isEmpty ||
        id == null ||
        username == null ||
        role == null ||
        rawPermissions is! List) {
      throw const FormatException('بيانات الجلسة غير مكتملة');
    }
    return AdminSession(
      token: token,
      id: id,
      username: username,
      fullName: json['fullName']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString(),
      role: role,
      permissions:
          rawPermissions.map((permission) => permission.toString()).toSet(),
    );
  }

  factory AdminSession.fromLoginResponse(Map<String, dynamic> response) {
    final rawAdmin = response['admin'];
    if (rawAdmin is! Map) {
      throw const FormatException('بيانات الجلسة غير مكتملة');
    }
    final admin = Map<String, dynamic>.from(rawAdmin);
    final token = response['token']?.toString();
    final role = admin['role']?.toString();
    final rawPermissions = admin['permissions'];
    if (token == null ||
        token.isEmpty ||
        role == null ||
        rawPermissions is! List) {
      throw const FormatException('بيانات الجلسة غير مكتملة');
    }
    return AdminSession(
      token: token,
      id: admin['id']?.toString() ?? '',
      username: admin['username']?.toString() ?? '',
      fullName: admin['fullName']?.toString(),
      profileImageUrl: admin['profileImageUrl']?.toString(),
      role: role,
      permissions:
          rawPermissions.map((permission) => permission.toString()).toSet(),
    );
  }
}
