import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../core/admin_config.dart';
import '../core/admin_session.dart';

enum AdminDestination {
  driverMap,
  drivers,
  riders,
  rideHistory,
  coupons,
  notifications,
  adminSettings,
  staffManagement,
  supportConversations,
  supportTickets,
}

class AdminDrawer extends StatefulWidget {
  const AdminDrawer({
    this.adminId = 'admin-panel',
    this.adminToken = '',
    this.username = '',
    this.fullName,
    this.profileImageUrl,
    this.client,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.onLogout,
    this.permissions = AdminSession.managerPermissions,
    this.unreadConversationCount = 0,
    this.unreadTicketCount = 0,
    super.key,
  });

  final String adminId;
  final String adminToken;
  final String username;
  final String? fullName;
  final String? profileImageUrl;
  final Dio? client;
  final AdminDestination selectedDestination;
  final ValueChanged<AdminDestination> onDestinationSelected;
  final VoidCallback onLogout;
  final Set<String> permissions;
  final int unreadConversationCount;
  final int unreadTicketCount;

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  late final Dio _dio;
  double _averageRating = 0;

  bool _can(String permission) => widget.permissions.contains(permission);

  @override
  void initState() {
    super.initState();
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    _loadRating();
  }

  Future<void> _loadRating() async {
    if (widget.adminToken.isEmpty) return;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/my-ratings',
        options: Options(headers: {
          'Authorization': 'Bearer ${widget.adminToken}',
        }),
      );
      final rating = response.data?['averageRating'];
      final parsedRating = rating is num
          ? rating.toDouble()
          : double.tryParse(rating?.toString() ?? '');
      if (!mounted || parsedRating == null) return;
      setState(() => _averageRating = parsedRating.clamp(0, 5).toDouble());
    } on DioException {
      // Keep the fallback rating visible when the rating service is unavailable.
    }
  }

  String get _firstName {
    final name = widget.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    if (widget.adminId == 'admin-panel') return 'مدير GoFast';
    return widget.username.isEmpty ? 'الموظف' : widget.username;
  }

  Color get _ratingColor {
    if (_averageRating < 3) return Colors.red.shade700;
    if (_averageRating < 4) return Colors.amber.shade800;
    return Colors.green.shade700;
  }

  Widget _buildRatingStars() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        key: const ValueKey('admin-rating-stars'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 5; index++)
            SizedBox(
              width: 20,
              height: 20,
              child: Stack(
                children: [
                  Icon(Icons.star_border, size: 20, color: _ratingColor),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor:
                          (_averageRating - index).clamp(0, 1).toDouble(),
                      child: Icon(Icons.star, size: 20, color: _ratingColor),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDestination = widget.selectedDestination;
    final onDestinationSelected = widget.onDestinationSelected;
    final unreadConversationCount = widget.unreadConversationCount;
    final unreadTicketCount = widget.unreadTicketCount;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PointerInterceptor(
        child: Drawer(
          width: 240,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: widget.profileImageUrl?.trim().isNotEmpty == true
                          ? ClipOval(
                            child: Image.network(
                              widget.profileImageUrl!.trim(),
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              webHtmlElementStrategy:
                                WebHtmlElementStrategy.prefer,
                              errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person_outline, size: 34),
                            ),
                            )
                          : const Icon(Icons.person_outline, size: 34),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'مرحبًا، $_firstName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildRatingStars(),
                          const SizedBox(width: 8),
                          Text(
                            _averageRating.toStringAsFixed(1),
                            style: TextStyle(
                              color: _ratingColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (_can('map.view'))
                        ListTile(
                          leading: const Icon(Icons.map_outlined),
                          title: const Text('خريطة السائقين والركاب'),
                          selected:
                              selectedDestination == AdminDestination.driverMap,
                          onTap: () =>
                              onDestinationSelected(AdminDestination.driverMap),
                        ),
                      if (_can('drivers.manage'))
                        ListTile(
                          leading: const Icon(Icons.people_outline),
                          title: const Text('إدارة الكباتن'),
                          selected:
                              selectedDestination == AdminDestination.drivers,
                          onTap: () =>
                              onDestinationSelected(AdminDestination.drivers),
                        ),
                      if (_can('riders.manage'))
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('إدارة الركاب'),
                          selected:
                              selectedDestination == AdminDestination.riders,
                          onTap: () =>
                              onDestinationSelected(AdminDestination.riders),
                        ),
                      if (_can('rides.read'))
                        ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: const Text('سجل الرحلات'),
                          selected: selectedDestination ==
                              AdminDestination.rideHistory,
                          onTap: () => onDestinationSelected(
                              AdminDestination.rideHistory),
                        ),
                      if (_can('coupons.manage'))
                        ListTile(
                          leading: const Icon(Icons.discount_outlined),
                          title: const Text('إدارة الكوبونات'),
                          selected:
                              selectedDestination == AdminDestination.coupons,
                          onTap: () =>
                              onDestinationSelected(AdminDestination.coupons),
                        ),
                      if (_can('notifications.send'))
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text('إرسال تنبيهات'),
                          selected: selectedDestination ==
                              AdminDestination.notifications,
                          onTap: () => onDestinationSelected(
                              AdminDestination.notifications),
                        ),
                      if (_can('support.conversations'))
                        ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Row(
                            children: [
                              const Expanded(child: Text('إدارة المحادثات')),
                              if (unreadConversationCount > 0)
                                Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 24),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadConversationCount > 99
                                        ? '99+'
                                        : '$unreadConversationCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          selected: selectedDestination ==
                              AdminDestination.supportConversations,
                          onTap: () => onDestinationSelected(
                              AdminDestination.supportConversations),
                        ),
                      if (_can('support.tickets'))
                        ListTile(
                          leading:
                              const Icon(Icons.report_gmailerrorred_outlined),
                          title: Row(
                            children: [
                              const Expanded(child: Text('إدارة الشكاوى')),
                              if (unreadTicketCount > 0)
                                Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 24),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadTicketCount > 99
                                        ? '99+'
                                        : '$unreadTicketCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          selected: selectedDestination ==
                              AdminDestination.supportTickets,
                          onTap: () => onDestinationSelected(
                              AdminDestination.supportTickets),
                        ),
                      if (_can('settings.manage'))
                        ListTile(
                          leading: const Icon(Icons.tune),
                          title: const Text('الإدارة والتحكم'),
                          selected: selectedDestination ==
                              AdminDestination.adminSettings,
                          onTap: () => onDestinationSelected(
                              AdminDestination.adminSettings),
                        ),
                      if (_can('staff.manage'))
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: const Text('إدارة الموظفين'),
                          selected: selectedDestination ==
                              AdminDestination.staffManagement,
                          onTap: () => onDestinationSelected(
                              AdminDestination.staffManagement),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('تسجيل الخروج'),
                  onTap: widget.onLogout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
