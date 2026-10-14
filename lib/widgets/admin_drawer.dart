import 'package:flutter/material.dart';

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

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.onLogout,
    this.permissions = AdminSession.managerPermissions,
    this.unreadConversationCount = 0,
    this.unreadTicketCount = 0,
    super.key,
  });

  final AdminDestination selectedDestination;
  final ValueChanged<AdminDestination> onDestinationSelected;
  final VoidCallback onLogout;
  final Set<String> permissions;
  final int unreadConversationCount;
  final int unreadTicketCount;

  bool _can(String permission) => permissions.contains(permission);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const ListTile(
                title: Text('لوحة GoFast'),
                titleTextStyle:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                        selected:
                            selectedDestination == AdminDestination.rideHistory,
                        onTap: () =>
                            onDestinationSelected(AdminDestination.rideHistory),
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
                                constraints: const BoxConstraints(minWidth: 24),
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
                                constraints: const BoxConstraints(minWidth: 24),
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
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
