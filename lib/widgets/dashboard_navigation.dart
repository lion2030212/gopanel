import 'package:flutter/material.dart';

class DashboardBackHandler {
  Object? _owner;
  bool Function()? _callback;

  void register(Object owner, bool Function() callback) {
    _owner = owner;
    _callback = callback;
  }

  void unregister(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _callback = null;
  }

  bool handleBack() => _callback?.call() ?? false;
}

class DashboardBackHandlerScope extends InheritedWidget {
  const DashboardBackHandlerScope({
    required this.handler,
    required super.child,
    super.key,
  });

  final DashboardBackHandler handler;

  static DashboardBackHandler? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DashboardBackHandlerScope>()
      ?.handler;

  @override
  bool updateShouldNotify(DashboardBackHandlerScope oldWidget) =>
      handler != oldWidget.handler;
}

class DashboardNavigation extends StatefulWidget {
  const DashboardNavigation({
    required this.homeBuilder,
    required this.routes,
    required this.onRouteChanged,
    this.unreadConversationCount = 0,
    this.unreadTicketCount = 0,
    this.showTicketShortcut = true,
    this.onOpenConversations,
    this.onOpenTickets,
    super.key,
  });

  static const String homeRoute = '/';
  static const String driversRoute = '/drivers';
  static const String ridersRoute = '/riders';
  static const String rideHistoryRoute = '/rides';
  static const String couponsRoute = '/coupons';
  static const String notificationsRoute = '/notifications';
  static const String adminSettingsRoute = '/settings';
  static const String staffManagementRoute = '/staff';
  static const String supportConversationsRoute = '/support/conversations';
  static const String supportTicketsRoute = '/support/tickets';

  final WidgetBuilder homeBuilder;
  final Map<String, WidgetBuilder> routes;
  final ValueChanged<String> onRouteChanged;
  final int unreadConversationCount;
  final int unreadTicketCount;
  final bool showTicketShortcut;
  final VoidCallback? onOpenConversations;
  final VoidCallback? onOpenTickets;

  @override
  State<DashboardNavigation> createState() => DashboardNavigationState();
}

class DashboardNavigationState extends State<DashboardNavigation> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Map<Route<dynamic>, DashboardBackHandler> _routeBackHandlers = {};
  final List<Route<dynamic>> _routeStack = [];
  late final _DashboardRouteObserver _routeObserver;
  DashboardBackHandler? _activeBackHandler;
  String _currentRouteName = DashboardNavigation.homeRoute;

  @override
  void initState() {
    super.initState();
    _routeObserver = _DashboardRouteObserver(_handleRouteChanged);
  }

  void pushNamed(String routeName) {
    if (!widget.routes.containsKey(routeName)) {
      throw ArgumentError.value(
          routeName, 'routeName', 'Unknown dashboard route');
    }
    _navigatorKey.currentState?.pushNamed<void>(routeName);
  }

  void openNamed(String routeName) {
    if (!widget.routes.containsKey(routeName)) {
      throw ArgumentError.value(
          routeName, 'routeName', 'Unknown dashboard route');
    }
    Route<dynamic>? existingRoute;
    for (final route in _routeStack.reversed) {
      if (route.settings.name == routeName) {
        existingRoute = route;
        break;
      }
    }
    if (existingRoute == null) {
      pushNamed(routeName);
    } else {
      _navigatorKey.currentState
          ?.popUntil((route) => identical(route, existingRoute));
    }
  }

  void goHome() {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  void _handleBack() {
    if (_activeBackHandler?.handleBack() ?? false) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      goHome();
    }
  }

  void _handleRouteChanged(
    Route<dynamic>? route, {
    Route<dynamic>? removedRoute,
  }) {
    if (removedRoute != null) {
      _routeBackHandlers.remove(removedRoute);
      _routeStack.remove(removedRoute);
    }
    if (!mounted || route == null) return;
    if (!_routeStack.contains(route)) _routeStack.add(route);
    _activeBackHandler = _routeBackHandlers[route];
    final routeName = route.settings.name;
    if (routeName == null || routeName == _currentRouteName) return;
    setState(() => _currentRouteName = routeName);
    widget.onRouteChanged(routeName);
  }

  Route<void>? _onGenerateRoute(RouteSettings settings) {
    final builder = settings.name == DashboardNavigation.homeRoute
        ? widget.homeBuilder
        : widget.routes[settings.name];
    if (builder == null) return null;
    if (settings.name == DashboardNavigation.homeRoute) {
      return MaterialPageRoute<void>(builder: builder, settings: settings);
    }
    final handler = DashboardBackHandler();
    final route = MaterialPageRoute<void>(
      builder: (context) => DashboardBackHandlerScope(
        handler: handler,
        child: builder(context),
      ),
      settings: settings,
    );
    _routeBackHandlers[route] = handler;
    return route;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Navigator(
            key: _navigatorKey,
            initialRoute: DashboardNavigation.homeRoute,
            onGenerateRoute: _onGenerateRoute,
            observers: [_routeObserver],
          ),
        ),
        if (_currentRouteName != DashboardNavigation.homeRoute)
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSupportShortcut(
                    tooltip: 'إدارة المحادثات',
                    icon: Icons.forum_outlined,
                    count: widget.unreadConversationCount,
                    onPressed: widget.onOpenConversations ??
                        () => openNamed(
                            DashboardNavigation.supportConversationsRoute),
                  ),
                  if (widget.showTicketShortcut) ...[
                    const SizedBox(width: 4),
                    _buildSupportShortcut(
                      tooltip: 'إدارة الشكاوى',
                      icon: Icons.report_gmailerrorred_outlined,
                      count: widget.unreadTicketCount,
                      onPressed: widget.onOpenTickets ??
                          () => openNamed(
                              DashboardNavigation.supportTicketsRoute),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'رجوع',
                    onPressed: _handleBack,
                    icon: const Icon(Icons.undo),
                  ),
                ],
              ),
            ),
          ),
        if (_currentRouteName == DashboardNavigation.homeRoute)
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSupportShortcut(
                    tooltip: 'إدارة المحادثات',
                    icon: Icons.forum_outlined,
                    count: widget.unreadConversationCount,
                    onPressed: widget.onOpenConversations ??
                        () => openNamed(
                            DashboardNavigation.supportConversationsRoute),
                  ),
                  if (widget.showTicketShortcut) ...[
                    const SizedBox(width: 4),
                    _buildSupportShortcut(
                      tooltip: 'إدارة الشكاوى',
                      icon: Icons.report_gmailerrorred_outlined,
                      count: widget.unreadTicketCount,
                      onPressed: widget.onOpenTickets ??
                          () => openNamed(
                              DashboardNavigation.supportTicketsRoute),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSupportShortcut({
    required String tooltip,
    required IconData icon,
    required int count,
    required VoidCallback onPressed,
  }) =>
      SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IconButton.filledTonal(
                tooltip: tooltip,
                onPressed: onPressed,
                icon: Icon(icon),
              ),
            ),
            if (count > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _DashboardRouteObserver extends NavigatorObserver {
  _DashboardRouteObserver(this.onRouteChanged);

  final void Function(Route<dynamic>? route, {Route<dynamic>? removedRoute})
      onRouteChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute, removedRoute: route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute, removedRoute: route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRouteChanged(newRoute, removedRoute: oldRoute);
  }
}
