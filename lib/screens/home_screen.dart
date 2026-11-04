import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;

import '../core/admin_api_client.dart';
import '../core/admin_config.dart';
import '../core/admin_session.dart';
import '../core/driver_marker_presentation.dart';
import '../core/map_search_presentation.dart';
import '../core/ride_route_presentation.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/dashboard_navigation.dart';
import '../widgets/map_marker_details_card.dart';
import '../widgets/map_stats_overlay.dart';
import '../core/map_hover_listener.dart';
import 'driver_management_screen.dart';
import 'coupon_management_screen.dart';
import 'admin_settings_screen.dart';
import 'notification_screen.dart';
import 'rider_management_screen.dart';
import 'ride_history_screen.dart';
import 'staff_management_screen.dart';
import 'admin_finance_screen.dart';
import 'support_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.adminSession,
    required this.onLogout,
    super.key,
  });

  final AdminSession adminSession;
  final ValueChanged<String?> onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final Dio _dio;
  final Map<int, _DriverLocation> _drivers = {};
  final Map<int, _RiderLocation> _riders = {};
  final Map<int, _ActiveRide> _activeRides = {};
  final Map<Color, BitmapDescriptor> _markerIcons = {};
  final Map<String, Map<Color, BitmapDescriptor>> _driverMarkerIcons = {};
  final Map<MarkerId, Offset> _markerScreenPositions = {};
  final ValueNotifier<Set<Marker>> _markerNotifier = ValueNotifier(<Marker>{});
  final TextEditingController _mapSearchController = TextEditingController();
  final GlobalKey<DashboardNavigationState> _dashboardNavigationKey =
      GlobalKey<DashboardNavigationState>();
  final GlobalKey<SupportManagementScreenState> _supportConversationsKey =
      GlobalKey<SupportManagementScreenState>();
  final GlobalKey<SupportManagementScreenState> _supportTicketsKey =
      GlobalKey<SupportManagementScreenState>();
  GoogleMapController? _mapController;
  MapHoverListener? _mapHoverListener;
  socket_io_client.Socket? _socket;
  Timer? _freshnessTimer;
  Timer? _staffPresenceTimer;
  bool _isLoadingDrivers = false;
  bool _showOfflineDrivers = true;
  String _mapSearchQuery = '';
  int _maxDriverLocationAgeSeconds = 120;
  int _maxRiderLocationAgeSeconds = 120;
  AdminDestination _selectedDestination = AdminDestination.driverMap;
  String? _mapError;
  bool _hasFramedDrivers = false;
  MarkerId? _hoveredMarkerId;
  MarkerId? _selectedMarkerId;
  int _unreadSupportConversationCount = 0;
  int _unreadSupportTicketCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dio = createAdminApiClient(
      onSessionExpired: widget.onLogout,
    );
    if (widget.adminSession.id.startsWith('staff-')) {
      unawaited(_sendStaffHeartbeat());
      _staffPresenceTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(_sendStaffHeartbeat()),
      );
    }
    _freshnessTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_loadDrivers()),
    );
    unawaited(_loadMarkerIcons());
    _loadDrivers();
    _connectSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _freshnessTimer?.cancel();
    _staffPresenceTimer?.cancel();
    _socket?.dispose();
    _dio.close(force: true);
    _mapHoverListener?.dispose();
    _mapController?.dispose();
    _mapSearchController.dispose();
    _markerNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sendStaffHeartbeat());
    }
  }

  Future<void> _sendStaffHeartbeat() async {
    if (!widget.adminSession.id.startsWith('staff-') ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await _dio.post<void>(
        '/api/admin/staff/heartbeat',
        options: Options(
          headers: {'Authorization': 'Bearer ${widget.adminSession.token}'},
        ),
      );
    } on DioException catch (_) {}
  }

  Future<void> _logoutManually() async {
    try {
      await _dio.post<void>(
        '/api/admin/logout',
        options: Options(headers: {
          'Authorization': 'Bearer ${widget.adminSession.token}',
        }),
      );
    } on DioException {
      // Local logout must still complete if the server is unreachable.
    } finally {
      if (mounted) widget.onLogout(null);
    }
  }

  Future<void> _loadDrivers() async {
    if (_isLoadingDrivers) return;
    _isLoadingDrivers = true;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/drivers/locations',
        options: Options(
            headers: {'Authorization': 'Bearer ${widget.adminSession.token}'}),
      );
      if (!mounted) return;
      final data = response.data ?? const {};
      final rawDrivers = data['drivers'];
      final drivers = <int, _DriverLocation>{};
      if (rawDrivers is List) {
        for (final rawDriver in rawDrivers) {
          if (rawDriver is Map) {
            final driver = _DriverLocation.fromJson(rawDriver);
            if (driver != null) drivers[driver.id] = driver;
          }
        }
      }
      final rawRiders = data['riders'];
      final riders = <int, _RiderLocation>{};
      if (rawRiders is List) {
        for (final rawRider in rawRiders) {
          if (rawRider is Map) {
            final rider = _RiderLocation.fromJson(rawRider);
            if (rider != null) riders[rider.id] = rider;
          }
        }
      }
      final rawActiveRides = data['activeRides'];
      final activeRides = <int, _ActiveRide>{};
      if (rawActiveRides is List) {
        for (final rawRide in rawActiveRides) {
          if (rawRide is Map) {
            final ride = _ActiveRide.fromJson(rawRide);
            if (ride != null) activeRides[ride.rideId] = ride;
          }
        }
      }
      final maxDriverAge =
          (data['maxLocationAgeSeconds'] as num?)?.toInt() ?? 120;
      final maxRiderAge =
          (data['maxRiderLocationAgeSeconds'] as num?)?.toInt() ?? 120;
      setState(() {
        _drivers
          ..clear()
          ..addAll(drivers);
        _riders
          ..clear()
          ..addAll(riders);
        _activeRides
          ..clear()
          ..addAll(activeRides);
        _maxDriverLocationAgeSeconds = maxDriverAge;
        _maxRiderLocationAgeSeconds = maxRiderAge;
        _mapError = null;
      });
      _publishMarkers();
      _frameDrivers();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onLogout('جلسة الإدارة غير صالحة');
        return;
      }
      if (mounted) setState(() => _mapError = 'تعذر تحميل مواقع السائقين');
    } finally {
      _isLoadingDrivers = false;
    }
  }

  Future<void> _loadMarkerIcons() async {
    const driverCategories = ['standard', 'comfort', 'scooter'];
    final driverColors = [
      DriverMarkerPresentation.offlineColor,
      DriverMarkerPresentation.onlineColor,
      DriverMarkerPresentation.activeRideColor,
    ];
    final riderColors = [
      DriverMarkerPresentation.riderOnlineColor,
      DriverMarkerPresentation.riderActiveRideColor,
    ];
    final driverIcons = await Future.wait(
      driverCategories.map((category) async {
        final icons = await Future.wait(
          driverColors.map(
            (color) => DriverMarkerPresentation.driverMarkerIcon(
              color,
              vehicleCategory: category,
            ),
          ),
        );
        return Map<Color, BitmapDescriptor>.fromIterables(
          driverColors,
          icons,
        );
      }),
    );
    final riderIcons = await Future.wait(
      riderColors.map(DriverMarkerPresentation.markerIcon),
    );
    if (!mounted) return;
    for (var index = 0; index < driverCategories.length; index++) {
      _driverMarkerIcons[driverCategories[index]] = driverIcons[index];
    }
    for (var index = 0; index < riderColors.length; index++) {
      _markerIcons[riderColors[index]] = riderIcons[index];
    }
    _publishMarkers();
  }

  void _connectSocket() {
    final socket = socket_io_client.io(
      '$adminApiBaseUrl/admin',
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': widget.adminSession.token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    socket.on('admin_session_invalidated', (payload) {
      if (!mounted) return;
      final message = payload is Map ? payload['message']?.toString() : null;
      widget.onLogout(message ?? 'جلسة الإدارة غير صالحة');
    });
    socket.on('driver_location_updated', (payload) {
      if (payload is Map) _updateDriver(payload);
    });
    socket.on('rider_location_updated', (payload) {
      if (payload is Map) _updateRider(payload);
    });
    socket.on('rider_location_removed', (payload) {
      if (payload is Map) _removeRider(payload);
    });
    socket.on('rider_ride_state_updated', (payload) {
      if (payload is Map) _updateRiderRideState(payload);
    });
    socket.on('support:conversations:changed', (_) {
      unawaited(_refreshSupportUnreadCount());
    });
    socket.on('support:conversation:message', (_) {
      unawaited(_refreshSupportUnreadCount());
    });
    if (widget.adminSession.can('support.tickets')) {
      socket.on('support:tickets:changed', (_) {
        unawaited(_refreshSupportUnreadTicketCount());
      });
    }
    socket.onConnect((_) {
      _loadDrivers();
      unawaited(_refreshSupportUnreadCount());
      if (widget.adminSession.can('support.tickets')) {
        unawaited(_refreshSupportUnreadTicketCount());
      }
    });
    socket.onConnectError((error) {
      final errorMessage = error.toString();
      if (errorMessage.contains('ADMIN_SESSION_REPLACED') ||
          errorMessage.contains('ADMIN_ACCOUNT_DISABLED') ||
          errorMessage.contains('ADMIN_SESSION_INVALID')) {
        widget.onLogout('جلسة الإدارة غير صالحة');
        return;
      }
      if (mounted) setState(() => _mapError = 'تعذر الاتصال بتحديثات المواقع');
    });
    socket.connect();
  }

  Future<void> _refreshSupportUnreadCount() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/support/conversations',
        queryParameters: const {'limit': 1},
        options: Options(
            headers: {'Authorization': 'Bearer ${widget.adminSession.token}'}),
      );
      final count = (response.data?['unreadCount'] as num?)?.toInt() ?? 0;
      if (mounted && count != _unreadSupportConversationCount) {
        setState(() => _unreadSupportConversationCount = count);
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onLogout('جلسة الإدارة غير صالحة');
      }
    }
  }

  Future<void> _refreshSupportUnreadTicketCount() async {
    if (!widget.adminSession.can('support.tickets')) return;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/support/tickets',
        queryParameters: const {'limit': 1, 'status': 'all'},
        options: Options(
            headers: {'Authorization': 'Bearer ${widget.adminSession.token}'}),
      );
      final count = (response.data?['unreadCount'] as num?)?.toInt() ?? 0;
      if (mounted && count != _unreadSupportTicketCount) {
        setState(() => _unreadSupportTicketCount = count);
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onLogout('جلسة الإدارة غير صالحة');
      }
    }
  }

  void _updateDriver(Map payload) {
    final driverId = (payload['id'] as num?)?.toInt();
    if (driverId == null) return;
    final driver = _DriverLocation.fromJson(
      payload,
      fallbackStatus: _drivers[driverId]?.status ?? 'idle',
      fallbackFullName: _drivers[driverId]?.fullName,
      fallbackPhone: _drivers[driverId]?.phone,
      fallbackLicensePlate: _drivers[driverId]?.licensePlate,
      fallbackVehicleCategory: _drivers[driverId]?.vehicleCategory,
    );
    if (driver == null || !mounted) return;
    setState(() {
      _drivers[driver.id] = driver;
      _mapError = null;
    });
    _publishMarkers();
    _frameDrivers();
  }

  void _updateRider(Map payload) {
    final riderId = (payload['id'] as num?)?.toInt();
    final previousRider = riderId == null ? null : _riders[riderId];
    final rider = _RiderLocation.fromJson(
      payload,
      fallbackFullName: previousRider?.fullName,
      fallbackPhone: previousRider?.phone,
    );
    if (rider == null || !mounted) return;
    setState(() {
      _riders[rider.id] = rider;
      _mapError = null;
    });
    _publishMarkers();
    _frameDrivers();
  }

  void _removeRider(Map payload) {
    final riderId = (payload['id'] as num?)?.toInt();
    if (riderId == null || !mounted) return;
    setState(() => _riders.remove(riderId));
    _publishMarkers();
  }

  void _updateRiderRideState(Map payload) {
    final riderId = (payload['id'] as num?)?.toInt();
    final rideId = (payload['rideId'] as num?)?.toInt();
    if (!mounted) return;
    final hasActiveRide =
        payload['hasActiveRide'] == true || payload['hasActiveRide'] == 1;
    final isAssignedActive =
        payload['isAssignedActive'] == true || payload['isAssignedActive'] == 1;
    final driverId = (payload['driverId'] as num?)?.toInt();
    final previousRide = rideId == null ? null : _activeRides[rideId];
    setState(() {
      final rider = riderId == null ? null : _riders[riderId];
      if (rider != null) {
        _riders[rider.id] = rider.copyWith(hasActiveRide: hasActiveRide);
      }
      if (rideId != null) {
        if (isAssignedActive && riderId != null && driverId != null) {
          _activeRides[rideId] = _ActiveRide(
            rideId: rideId,
            riderId: riderId,
            driverId: driverId,
            status: payload['status']?.toString() ?? '',
            isDelivery: payload['isDelivery'] == true ||
              payload['isDelivery'] == 1 ||
              previousRide?.isDelivery == true,
            deliveryPaymentCollected:
              payload['deliveryPaymentCollected'] == true ||
                payload['deliveryPaymentCollected'] == 1 ||
                previousRide?.deliveryPaymentCollected == true,
          );
        } else {
          _activeRides.remove(rideId);
        }
      }
    });
    _publishMarkers();
  }

  void _frameDrivers() {
    if (_hasFramedDrivers ||
        (_drivers.isEmpty && _riders.isEmpty) ||
        _mapController == null) {
      return;
    }
    _hasFramedDrivers = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _mapController == null) return;
      final locations = [
        ..._drivers.values.map((driver) => driver.position),
        ..._riders.values.map((rider) => rider.position),
      ];
      await _frameMapPositions(_mapController!, locations);
    });
  }

  Future<void> _frameMapPositions(
    GoogleMapController controller,
    List<LatLng> locations,
  ) async {
    if (!mounted ||
        !identical(controller, _mapController) ||
        locations.isEmpty) {
      return;
    }
    if (locations.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(locations.single, 13),
      );
      return;
    }
    var south = locations.first.latitude;
    var north = south;
    var west = locations.first.longitude;
    var east = west;
    for (final location in locations.skip(1)) {
      if (location.latitude < south) south = location.latitude;
      if (location.latitude > north) north = location.latitude;
      if (location.longitude < west) west = location.longitude;
      if (location.longitude > east) east = location.longitude;
    }
    if (south == north && west == east) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(locations.first, 13),
      );
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  void _publishMarkers() {
    _markerNotifier.value = _markers;
    unawaited(_refreshMarkerScreenPositions());
  }

  bool get _hasMapSearchQuery => _mapSearchQuery.trim().isNotEmpty;

  Set<int> get _matchingRideIds {
    if (!_hasMapSearchQuery) return const <int>{};
    return _activeRides.values
        .where((ride) => MapSearchPresentation.matchesRideId(
              query: _mapSearchQuery,
              rideId: ride.rideId,
            ))
        .map((ride) => ride.rideId)
        .toSet();
  }

  Set<int> get _matchingDriverIds {
    final matchingRideIds = _matchingRideIds;
    final matchingDriverIds = <int>{
      if (!_hasMapSearchQuery) ..._drivers.keys,
      for (final driver in _drivers.values)
        if (_hasMapSearchQuery && MapSearchPresentation.matchesIdentity(
          query: _mapSearchQuery,
          name: driver.fullName,
          phone: driver.phone,
          licensePlate: driver.licensePlate,
        ))
          driver.id,
      for (final ride in _activeRides.values)
        if (_hasMapSearchQuery &&
            matchingRideIds.contains(ride.rideId) &&
            _drivers.containsKey(ride.driverId))
          ride.driverId,
    };
    return {
      for (final driver in _drivers.values)
        if (matchingDriverIds.contains(driver.id) &&
            DriverMarkerPresentation.isVisibleOnMap(
              isOnline: driver.isOnline,
              showOfflineDrivers: _showOfflineDrivers,
            ))
          driver.id,
    };
  }

  Set<int> get _matchingRiderIds {
    if (!_hasMapSearchQuery) return _riders.keys.toSet();
    final matchingRideIds = _matchingRideIds;
    return {
      for (final rider in _riders.values)
        if (MapSearchPresentation.matchesIdentity(
          query: _mapSearchQuery,
          name: rider.fullName,
          phone: rider.phone,
        ))
          rider.id,
      for (final ride in _activeRides.values)
        if (matchingRideIds.contains(ride.rideId) &&
            _riders.containsKey(ride.riderId))
          ride.riderId,
    };
  }

  bool get _hasMapSearchResults =>
      _matchingDriverIds.isNotEmpty || _matchingRiderIds.isNotEmpty;

  void _handleMapSearchChanged(String value) {
    setState(() {
      _mapSearchQuery = value;
      _hoveredMarkerId = null;
      _selectedMarkerId = null;
    });
    _publishMarkers();
    _focusMapSearchResults();
  }

  void _toggleOfflineDrivers() {
    setState(() {
      _showOfflineDrivers = !_showOfflineDrivers;
      _hoveredMarkerId = null;
      _selectedMarkerId = null;
    });
    _publishMarkers();
  }

  void _focusMapSearchResults() {
    final controller = _mapController;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(controller, _mapController)) return;
      final positions = <LatLng>[];
      for (final id in _matchingDriverIds) {
        final driver = _drivers[id];
        if (driver != null) positions.add(driver.position);
      }
      for (final id in _matchingRiderIds) {
        final rider = _riders[id];
        if (rider != null) positions.add(rider.position);
      }
      unawaited(_frameMapPositions(controller, positions));
    });
  }

  _ActiveRide? _activeRideForMarker({int? driverId, int? riderId}) {
    for (final ride in _activeRides.values) {
      if ((driverId != null && ride.driverId == driverId) ||
          (riderId != null && ride.riderId == riderId)) {
        return ride;
      }
    }
    return null;
  }

  String _rideStatusLabel(_ActiveRide ride) => switch (ride.status) {
        'requested' => 'بانتظار السائق',
        'accepted' => ride.isDelivery
            ? 'الكابتن في الطريق لاستلام الطلب'
            : 'الكابتن في الطريق',
        'arriving' => ride.isDelivery ? 'وصل الكابتن للاستلام' : 'وصل الكابتن',
        'in_progress' => ride.isDelivery ? 'الطلب قيد التوصيل' : 'الرحلة جارية',
        'completed' => ride.isDelivery ? 'تم تسليم الطلب' : 'مكتملة',
        'cancelled' => 'ملغاة',
        _ => ride.status,
      };

  Map<MarkerId, _MapMarkerDetails> get _markerDetails {
    final details = <MarkerId, _MapMarkerDetails>{};
    final matchingDriverIds = _matchingDriverIds;
    for (final driver in _drivers.values) {
      if (!matchingDriverIds.contains(driver.id)) continue;
      final presentation = DriverMarkerPresentation.fromDriver(
        isOnline: driver.isOnline,
        status: driver.status,
      );
      final category =
          DriverMarkerPresentation.driverMarkerCategory(driver.vehicleCategory);
      final categoryIcons = _driverMarkerIcons[category];
      if (categoryIcons == null ||
          !categoryIcons.containsKey(presentation.color)) {
        continue;
      }
      final activeRide = _activeRideForMarker(driverId: driver.id);
      final markerId = MarkerId('driver-${driver.id}');
      details[markerId] = _MapMarkerDetails(
        position: driver.position,
        role: 'السائق',
        name: driver.fullName,
        phone: driver.phone,
        status: presentation.label,
        updatedAt: DriverMarkerPresentation.formatLastUpdated(driver.updatedAt),
        statusColor: presentation.color,
        rideId: activeRide?.rideId,
        rideStatus:
          activeRide == null ? null : _rideStatusLabel(activeRide),
        deliveryPaymentCollected: activeRide?.isDelivery == true &&
          activeRide?.deliveryPaymentCollected == true,
      );
    }
    final matchingRiderIds = _matchingRiderIds;
    for (final rider in _riders.values) {
      if (!matchingRiderIds.contains(rider.id)) continue;
      final presentation = DriverMarkerPresentation.fromRider(
        hasActiveRide: rider.hasActiveRide,
      );
      if (!_markerIcons.containsKey(presentation.color)) continue;
      final activeRide = _activeRideForMarker(riderId: rider.id);
      final markerId = MarkerId('rider-${rider.id}');
      details[markerId] = _MapMarkerDetails(
        position: rider.position,
        role: 'الراكب',
        name: rider.fullName,
        phone: rider.phone,
        status: presentation.label,
        updatedAt: DriverMarkerPresentation.formatLastUpdated(rider.updatedAt),
        statusColor: presentation.color,
        rideId: activeRide?.rideId,
        rideStatus:
          activeRide == null ? null : _rideStatusLabel(activeRide),
        deliveryPaymentCollected: activeRide?.isDelivery == true &&
          activeRide?.deliveryPaymentCollected == true,
      );
    }
    return details;
  }

  Future<void> _refreshMarkerScreenPositions() async {
    final controller = _mapController;
    if (controller == null) return;
    final details = _markerDetails;
    final coordinates = await Future.wait(
      details.entries.map((entry) async {
        try {
          final coordinate =
              await controller.getScreenCoordinate(entry.value.position);
          return MapEntry(
            entry.key,
            Offset(coordinate.x.toDouble(), coordinate.y.toDouble()),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted || !identical(controller, _mapController)) return;
    setState(() {
      _markerScreenPositions
        ..clear()
        ..addEntries(coordinates.whereType<MapEntry<MarkerId, Offset>>());
      if (!_markerDetails.containsKey(_hoveredMarkerId)) {
        _hoveredMarkerId = null;
      }
      if (!_markerDetails.containsKey(_selectedMarkerId)) {
        _selectedMarkerId = null;
      }
    });
  }

  void _attachMapHoverListener(GoogleMapController controller) {
    _mapHoverListener?.dispose();
    _mapHoverListener = attachMapHoverListener(
      controller.mapId,
      _handleMapPointer,
    );
    unawaited(_refreshMarkerScreenPositions());
  }

  void _handleMapPointer(Offset? pointerPosition) {
    if (pointerPosition == null) {
      if (_hoveredMarkerId != null && mounted) {
        setState(() => _hoveredMarkerId = null);
      }
      return;
    }
    MarkerId? nearestMarker;
    var nearestDistance = (34 * 34).toDouble();
    for (final entry in _markerScreenPositions.entries) {
      final dx = entry.value.dx - pointerPosition.dx;
      final dy = entry.value.dy - pointerPosition.dy;
      final distance = dx * dx + dy * dy;
      if (distance <= nearestDistance) {
        nearestDistance = distance;
        nearestMarker = entry.key;
      }
    }
    if (nearestMarker != _hoveredMarkerId && mounted) {
      setState(() => _hoveredMarkerId = nearestMarker);
    }
  }

  void _selectMarker(MarkerId markerId) {
    if (!mounted) return;
    setState(() => _selectedMarkerId = markerId);
  }

  void _holdMarkerCard(MarkerId markerId) {
    if (!mounted) return;
    setState(() => _selectedMarkerId = markerId);
  }

  void _releaseMarkerCard(MarkerId markerId) {
    if (!mounted || _selectedMarkerId != markerId) return;
    setState(() => _selectedMarkerId = null);
  }

  Set<Marker> get _markers {
    final matchingDriverIds = _matchingDriverIds;
    final matchingRiderIds = _matchingRiderIds;
    final markers = _drivers.values
        .map((driver) {
          if (!matchingDriverIds.contains(driver.id)) return null;
          final presentation = DriverMarkerPresentation.fromDriver(
            isOnline: driver.isOnline,
            status: driver.status,
          );
          final category = DriverMarkerPresentation.driverMarkerCategory(
            driver.vehicleCategory,
          );
          final icon = _driverMarkerIcons[category]?[presentation.color];
          if (icon == null) return null;
          final markerId = MarkerId('driver-${driver.id}');
            final lastUpdate =
              DriverMarkerPresentation.formatLastUpdated(driver.updatedAt);
          return Marker(
            markerId: markerId,
            position: driver.position,
            icon: icon,
            consumeTapEvents: true,
            onTap: () => _selectMarker(markerId),
            infoWindow: DriverMarkerPresentation.infoWindow(
              role: 'السائق',
              id: driver.id,
              fullName: driver.fullName,
              phone: driver.phone,
              status: presentation.label,
              lastUpdated: lastUpdate,
            ),
          );
        })
        .whereType<Marker>()
        .toSet();
    for (final rider in _riders.values) {
      if (!matchingRiderIds.contains(rider.id)) continue;
      final presentation = DriverMarkerPresentation.fromRider(
        hasActiveRide: rider.hasActiveRide,
      );
      final icon = _markerIcons[presentation.color];
      if (icon == null) continue;
      final markerId = MarkerId('rider-${rider.id}');
        final lastUpdate =
          DriverMarkerPresentation.formatLastUpdated(rider.updatedAt);
      markers.add(Marker(
        markerId: markerId,
        position: rider.position,
        icon: icon,
        consumeTapEvents: true,
        onTap: () => _selectMarker(markerId),
        infoWindow: DriverMarkerPresentation.infoWindow(
          role: 'الراكب',
          id: rider.id,
          fullName: rider.fullName,
          phone: rider.phone,
          status: presentation.label,
          lastUpdated: lastUpdate,
        ),
      ));
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    final matchingRideIds = _matchingRideIds;
    final rides = _activeRides.values.toList()
      ..sort((left, right) => left.rideId.compareTo(right.rideId));
    final colors = RideRoutePresentation.colorsForRideIds(
      rides.map((ride) => ride.rideId),
    );
    final polylines = <Polyline>{};
    for (final ride in rides) {
      if (_hasMapSearchQuery && !matchingRideIds.contains(ride.rideId)) {
        continue;
      }
      final driver = _drivers[ride.driverId];
      final rider = _riders[ride.riderId];
      if (driver == null ||
          rider == null ||
          !RideRoutePresentation.hasFreshLocation(
            driver.updatedAt,
            maxAgeSeconds: _maxDriverLocationAgeSeconds,
          ) ||
          !RideRoutePresentation.hasFreshLocation(
            rider.updatedAt,
            maxAgeSeconds: _maxRiderLocationAgeSeconds,
          )) {
        continue;
      }
      polylines.add(Polyline(
        polylineId: PolylineId('ride-${ride.rideId}'),
        points: [driver.position, rider.position],
        color: colors[ride.rideId]!,
        width: 5,
        zIndex: 1,
      ));
    }
    return polylines;
  }

  void _selectDestination(AdminDestination destination) {
    if (!_canOpenDestination(destination)) return;
    Navigator.of(context).pop();
    if (destination == AdminDestination.driverMap) {
      _dashboardNavigationKey.currentState?.goHome();
    } else if (destination == AdminDestination.supportConversations ||
        destination == AdminDestination.supportTickets) {
      _openSupportDestination(destination);
    } else if (_selectedDestination != destination) {
      final route = switch (destination) {
        AdminDestination.drivers => DashboardNavigation.driversRoute,
        AdminDestination.riders => DashboardNavigation.ridersRoute,
        AdminDestination.rideHistory => DashboardNavigation.rideHistoryRoute,
        AdminDestination.coupons => DashboardNavigation.couponsRoute,
        AdminDestination.notifications =>
          DashboardNavigation.notificationsRoute,
        AdminDestination.adminSettings =>
          DashboardNavigation.adminSettingsRoute,
        AdminDestination.staffManagement =>
          DashboardNavigation.staffManagementRoute,
        AdminDestination.financialManagement =>
          DashboardNavigation.financialManagementRoute,
        AdminDestination.supportConversations =>
          DashboardNavigation.supportConversationsRoute,
        AdminDestination.supportTickets =>
          DashboardNavigation.supportTicketsRoute,
        AdminDestination.driverMap => DashboardNavigation.homeRoute,
      };
      _dashboardNavigationKey.currentState?.pushNamed(route);
    }
  }

  void _openSupportDestination(AdminDestination destination) {
    if (!_canOpenDestination(destination)) return;
    final isTickets = destination == AdminDestination.supportTickets;
    (isTickets ? _supportTicketsKey : _supportConversationsKey)
        .currentState
        ?.showList();
    _dashboardNavigationKey.currentState?.openNamed(
      isTickets
          ? DashboardNavigation.supportTicketsRoute
          : DashboardNavigation.supportConversationsRoute,
    );
  }

  bool _canOpenDestination(AdminDestination destination) =>
      switch (destination) {
        AdminDestination.driverMap => widget.adminSession.can('map.view'),
        AdminDestination.drivers => widget.adminSession.can('drivers.manage'),
        AdminDestination.riders => widget.adminSession.can('riders.manage'),
        AdminDestination.rideHistory => widget.adminSession.can('rides.read'),
        AdminDestination.coupons => widget.adminSession.can('coupons.manage'),
        AdminDestination.notifications =>
          widget.adminSession.can('notifications.send'),
        AdminDestination.adminSettings =>
          widget.adminSession.can('settings.manage'),
        AdminDestination.staffManagement =>
          widget.adminSession.can('staff.manage'),
        AdminDestination.financialManagement =>
          widget.adminSession.can('finance.reports.read'),
        AdminDestination.supportConversations =>
          widget.adminSession.can('support.conversations'),
        AdminDestination.supportTickets =>
          widget.adminSession.can('support.tickets'),
      };

  void _handleRouteChanged(String routeName) {
    final destination = routeName == DashboardNavigation.driversRoute ||
            routeName.startsWith('${DashboardNavigation.driversRoute}/')
        ? AdminDestination.drivers
        : routeName == DashboardNavigation.ridersRoute ||
                routeName.startsWith('${DashboardNavigation.ridersRoute}/')
            ? AdminDestination.riders
            : routeName == DashboardNavigation.rideHistoryRoute ||
                    routeName
                        .startsWith('${DashboardNavigation.rideHistoryRoute}/')
                ? AdminDestination.rideHistory
                : routeName == DashboardNavigation.couponsRoute ||
                        routeName
                            .startsWith('${DashboardNavigation.couponsRoute}/')
                    ? AdminDestination.coupons
                    : routeName == DashboardNavigation.notificationsRoute ||
                            routeName.startsWith(
                                '${DashboardNavigation.notificationsRoute}/')
                        ? AdminDestination.notifications
                        : routeName == DashboardNavigation.adminSettingsRoute ||
                                routeName.startsWith(
                                    '${DashboardNavigation.adminSettingsRoute}/')
                            ? AdminDestination.adminSettings
                            : routeName == DashboardNavigation.staffManagementRoute ||
                                    routeName.startsWith(
                                        '${DashboardNavigation.staffManagementRoute}/')
                                ? AdminDestination.staffManagement
                                : routeName == DashboardNavigation.financialManagementRoute ||
                                        routeName.startsWith(
                                            '${DashboardNavigation.financialManagementRoute}/')
                                    ? AdminDestination.financialManagement
                                    : routeName ==
                                                DashboardNavigation
                                                    .supportConversationsRoute ||
                                            routeName.startsWith(
                                                '${DashboardNavigation.supportConversationsRoute}/')
                                        ? AdminDestination.supportConversations
                                        : routeName ==
                                                    DashboardNavigation
                                                        .supportTicketsRoute ||
                                                routeName.startsWith(
                                                    '${DashboardNavigation.supportTicketsRoute}/')
                                            ? AdminDestination.supportTickets
                                            : AdminDestination.driverMap;
    if (_selectedDestination != destination) {
      setState(() => _selectedDestination = destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: AdminDrawer(
          adminId: widget.adminSession.id,
          adminToken: widget.adminSession.token,
          username: widget.adminSession.username,
          fullName: widget.adminSession.fullName,
          profileImageUrl: widget.adminSession.profileImageUrl,
          selectedDestination: _selectedDestination,
          permissions: widget.adminSession.permissions,
          onDestinationSelected: _selectDestination,
          unreadConversationCount: _unreadSupportConversationCount,
          unreadTicketCount: widget.adminSession.can('support.tickets')
              ? _unreadSupportTicketCount
              : 0,
          onLogout: () {
            Navigator.of(context).pop();
            unawaited(_logoutManually());
          },
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: DashboardNavigation(
                key: _dashboardNavigationKey,
                homeBuilder: (_) => ValueListenableBuilder<Set<Marker>>(
                  valueListenable: _markerNotifier,
                  builder: (context, markers, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final markerId = _hoveredMarkerId ?? _selectedMarkerId;
                      final details =
                          markerId == null ? null : _markerDetails[markerId];
                      final position = markerId == null
                          ? null
                          : _markerScreenPositions[markerId];
                      final cardWidth = math.max(
                          0.0, math.min(300.0, constraints.maxWidth - 24));
                      final cardLeft = position == null
                          ? 12.0
                          : (position.dx + 20)
                              .clamp(
                                12.0,
                                math.max(12.0,
                                    constraints.maxWidth - cardWidth - 12),
                              )
                              .toDouble();
                            final cardHeight = 190.0 +
                              (details?.rideId != null ? 26.0 : 0.0) +
                              (details?.rideStatus != null ? 26.0 : 0.0) +
                              (details?.deliveryPaymentCollected == true
                                ? 26.0
                                : 0.0);
                      final cardTop = position == null
                          ? 12.0
                          : (position.dy + 20)
                              .clamp(
                                12.0,
                                math.max(
                                    12.0, constraints.maxHeight - cardHeight - 12),
                              )
                              .toDouble();
                      return Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(20, 0),
                              zoom: 2,
                            ),
                            markers: markers,
                            polylines: _polylines,
                            myLocationButtonEnabled: false,
                            onTap: (_) => setState(() {
                              _selectedMarkerId = null;
                            }),
                            onCameraIdle: () =>
                                unawaited(_refreshMarkerScreenPositions()),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              _attachMapHoverListener(controller);
                              _frameDrivers();
                            },
                          ),
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              child: Center(
                                child: SizedBox(
                                  width: math.min(
                                    520.0,
                                    math.max(0.0, constraints.maxWidth - 120),
                                  ),
                                  child: Material(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(8),
                                    child: TextField(
                                      controller: _mapSearchController,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      textInputAction: TextInputAction.search,
                                      onChanged: _handleMapSearchChanged,
                                      decoration: InputDecoration(
                                        hintText:
                                          'ابحث بالاسم أو الجوال أو رقم السيارة أو الرحلة',
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon:
                                            _mapSearchController.text.isEmpty
                                                ? null
                                                : IconButton(
                                                    tooltip: 'مسح البحث',
                                                    onPressed: () {
                                                      _mapSearchController
                                                          .clear();
                                                      _handleMapSearchChanged(
                                                          '');
                                                    },
                                                    icon: const Icon(
                                                        Icons.clear),
                                                  ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_hasMapSearchQuery && !_hasMapSearchResults)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 24,
                              child: SafeArea(
                                child: Center(
                                  child: Material(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Text('لا توجد نتائج مطابقة'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (details != null)
                            Positioned(
                              left: cardLeft,
                              top: cardTop,
                              width: cardWidth,
                              child: MouseRegion(
                                onEnter: (_) => _holdMarkerCard(markerId!),
                                onExit: (_) => _releaseMarkerCard(markerId!),
                                child: MapMarkerDetailsCard(
                                  role: details.role,
                                  name: details.name,
                                  phone: details.phone,
                                  status: details.status,
                                  updatedAt: details.updatedAt,
                                  statusColor: details.statusColor,
                                    rideId: details.rideId,
                                    rideStatus: details.rideStatus,
                                    deliveryPaymentCollected:
                                      details.deliveryPaymentCollected,
                                  onDismiss: () => setState(() {
                                    _selectedMarkerId = null;
                                    _hoveredMarkerId = null;
                                  }),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                routes: {
                  if (widget.adminSession.can('drivers.manage'))
                    DashboardNavigation.driversRoute: (_) =>
                        DriverManagementScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: (message) =>
                              widget.onLogout(message),
                        ),
                  if (widget.adminSession.can('riders.manage'))
                    DashboardNavigation.ridersRoute: (_) =>
                        RiderManagementScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: (message) =>
                              widget.onLogout(message),
                        ),
                  DashboardNavigation.rideHistoryRoute: (_) =>
                      RideHistoryScreen(
                        adminToken: widget.adminSession.token,
                        canReverseSettlement:
                            widget.adminSession.can('rides.reverse_settlement'),
                        onSessionExpired: (message) => widget.onLogout(message),
                      ),
                  if (widget.adminSession.can('coupons.manage'))
                    DashboardNavigation.couponsRoute: (_) =>
                        CouponManagementScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                        ),
                  if (widget.adminSession.can('notifications.send'))
                    DashboardNavigation.notificationsRoute: (_) =>
                        NotificationScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                        ),
                  if (widget.adminSession.can('settings.manage'))
                    DashboardNavigation.adminSettingsRoute: (_) =>
                        AdminSettingsScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                        ),
                  if (widget.adminSession.can('support.conversations'))
                    DashboardNavigation.supportConversationsRoute: (_) =>
                        SupportManagementScreen(
                          key: _supportConversationsKey,
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                          ticketsMode: false,
                        ),
                  if (widget.adminSession.can('support.tickets'))
                    DashboardNavigation.supportTicketsRoute: (_) =>
                        SupportManagementScreen(
                          key: _supportTicketsKey,
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                          ticketsMode: true,
                          onTicketRead: () =>
                              unawaited(_refreshSupportUnreadTicketCount()),
                        ),
                  if (widget.adminSession.can('staff.manage'))
                    DashboardNavigation.staffManagementRoute: (_) =>
                        StaffManagementScreen(
                          adminToken: widget.adminSession.token,
                          currentAdminId: widget.adminSession.id,
                          canViewConversations:
                              widget.adminSession.can('support.conversations'),
                          canViewTickets:
                              widget.adminSession.can('support.tickets'),
                          onSessionExpired: widget.onLogout,
                        ),
                  if (widget.adminSession.can('finance.reports.read'))
                    DashboardNavigation.financialManagementRoute: (_) =>
                        AdminFinanceScreen(
                          adminToken: widget.adminSession.token,
                          onSessionExpired: widget.onLogout,
                        ),
                },
                onRouteChanged: _handleRouteChanged,
                unreadConversationCount: _unreadSupportConversationCount,
                unreadTicketCount: widget.adminSession.can('support.tickets')
                    ? _unreadSupportTicketCount
                    : 0,
                showTicketShortcut: widget.adminSession.can('support.tickets'),
                onOpenConversations: () => _openSupportDestination(
                    AdminDestination.supportConversations),
                onOpenTickets: () =>
                    _openSupportDestination(AdminDestination.supportTickets),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: 'فتح القائمة',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              ),
            ),
            if (_selectedDestination == AdminDestination.driverMap)
              Positioned(
                top: _mapError == null ? 72 : 140,
                left: 12,
                child: SafeArea(
                  child: MapStatsOverlay(
                    onlineGoFast: _drivers.values
                      .where((driver) =>
                        driver.isOnline &&
                        DriverMarkerPresentation.driverMarkerCategory(
                            driver.vehicleCategory) ==
                          'standard')
                      .length,
                    onlineGoTalabat: _drivers.values
                      .where((driver) =>
                        driver.isOnline &&
                        DriverMarkerPresentation.driverMarkerCategory(
                            driver.vehicleCategory) ==
                          'comfort')
                      .length,
                    onlineGoScooter: _drivers.values
                      .where((driver) =>
                        driver.isOnline &&
                        DriverMarkerPresentation.driverMarkerCategory(
                            driver.vehicleCategory) ==
                          'scooter')
                      .length,
                    offlineDrivers: _drivers.values
                        .where((driver) => !driver.isOnline)
                        .length,
                    riders: _riders.length,
                    activeRides: _activeRides.length,
                    showOfflineDrivers: _showOfflineDrivers,
                    onToggleOfflineDrivers: _toggleOfflineDrivers,
                  ),
                ),
              ),
            if (_selectedDestination == AdminDestination.driverMap &&
                _mapError != null)
              Positioned(
                top: 76,
                right: 16,
                left: 16,
                child: SafeArea(
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_mapError!),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapMarkerDetails {
  const _MapMarkerDetails({
    required this.position,
    required this.role,
    required this.name,
    required this.phone,
    required this.status,
    required this.updatedAt,
    required this.statusColor,
    this.rideId,
    this.rideStatus,
    this.deliveryPaymentCollected = false,
  });

  final LatLng position;
  final String role;
  final String? name;
  final String? phone;
  final String status;
  final String updatedAt;
  final Color statusColor;
  final int? rideId;
  final String? rideStatus;
  final bool deliveryPaymentCollected;
}

class _DriverLocation {
  const _DriverLocation({
    required this.id,
    this.fullName,
    this.phone,
    this.licensePlate,
    required this.latitude,
    required this.longitude,
    required this.isOnline,
    required this.status,
    this.vehicleCategory,
    required this.updatedAt,
  });

  final int id;
  final String? fullName;
  final String? phone;
  final String? licensePlate;
  final double latitude;
  final double longitude;
  final bool isOnline;
  final String status;
  final String? vehicleCategory;
  final DateTime? updatedAt;

  LatLng get position => LatLng(latitude, longitude);

  static _DriverLocation? fromJson(
    Map<dynamic, dynamic> json, {
    String? fallbackStatus,
    String? fallbackFullName,
    String? fallbackPhone,
    String? fallbackLicensePlate,
    String? fallbackVehicleCategory,
  }) {
    final id = (json['id'] as num?)?.toInt();
    final latitude = double.tryParse(json['latitude']?.toString() ?? '');
    final longitude = double.tryParse(json['longitude']?.toString() ?? '');
    if (id == null || latitude == null || longitude == null) return null;
    final rawUpdatedAt = json['lastLocationUpdate'] ?? json['updatedAt'];
    return _DriverLocation(
      id: id,
      fullName: DriverMarkerPresentation.preserveIdentityValue(
        json['fullName']?.toString(),
        fallbackFullName,
      ),
      phone: DriverMarkerPresentation.preserveIdentityValue(
        json['phone']?.toString(),
        fallbackPhone,
      ),
      licensePlate: DriverMarkerPresentation.preserveIdentityValue(
        json['licensePlate']?.toString(),
        fallbackLicensePlate,
      ),
      vehicleCategory: DriverMarkerPresentation.preserveIdentityValue(
        json['vehicleCategory']?.toString() ??
            json['vehicle_category']?.toString(),
        fallbackVehicleCategory,
      ),
      latitude: latitude,
      longitude: longitude,
      isOnline: json['isOnline'] == true || json['isOnline'] == 1,
      status: json['status']?.toString() ?? fallbackStatus ?? 'غير معروف',
      updatedAt: rawUpdatedAt == null
          ? null
          : DateTime.tryParse(rawUpdatedAt.toString()),
    );
  }
}

class _RiderLocation {
  const _RiderLocation({
    required this.id,
    this.fullName,
    this.phone,
    required this.latitude,
    required this.longitude,
    required this.hasActiveRide,
    required this.updatedAt,
  });

  final int id;
  final String? fullName;
  final String? phone;
  final double latitude;
  final double longitude;
  final bool hasActiveRide;
  final DateTime? updatedAt;

  LatLng get position => LatLng(latitude, longitude);

  _RiderLocation copyWith({bool? hasActiveRide}) => _RiderLocation(
        id: id,
        fullName: fullName,
        phone: phone,
        latitude: latitude,
        longitude: longitude,
        hasActiveRide: hasActiveRide ?? this.hasActiveRide,
        updatedAt: updatedAt,
      );

  static _RiderLocation? fromJson(
    Map<dynamic, dynamic> json, {
    String? fallbackFullName,
    String? fallbackPhone,
  }) {
    final id = (json['id'] as num?)?.toInt();
    final latitude = double.tryParse(json['latitude']?.toString() ?? '');
    final longitude = double.tryParse(json['longitude']?.toString() ?? '');
    if (id == null || latitude == null || longitude == null) return null;
    final rawUpdatedAt = json['lastLocationUpdate'] ?? json['updatedAt'];
    return _RiderLocation(
      id: id,
      fullName: DriverMarkerPresentation.preserveIdentityValue(
        json['fullName']?.toString(),
        fallbackFullName,
      ),
      phone: DriverMarkerPresentation.preserveIdentityValue(
        json['phone']?.toString(),
        fallbackPhone,
      ),
      latitude: latitude,
      longitude: longitude,
      hasActiveRide:
          json['hasActiveRide'] == true || json['hasActiveRide'] == 1,
      updatedAt: rawUpdatedAt == null
          ? null
          : DateTime.tryParse(rawUpdatedAt.toString()),
    );
  }
}

class _ActiveRide {
  const _ActiveRide({
    required this.rideId,
    required this.riderId,
    required this.driverId,
    required this.status,
    required this.isDelivery,
    required this.deliveryPaymentCollected,
  });

  final int rideId;
  final int riderId;
  final int driverId;
  final String status;
  final bool isDelivery;
  final bool deliveryPaymentCollected;

  static _ActiveRide? fromJson(Map<dynamic, dynamic> json) {
    final rideId = (json['rideId'] as num?)?.toInt();
    final riderId = (json['riderId'] as num?)?.toInt();
    final driverId = (json['driverId'] as num?)?.toInt();
    final status = json['status']?.toString();
    if (rideId == null ||
        riderId == null ||
        driverId == null ||
        status == null) {
      return null;
    }
    return _ActiveRide(
      rideId: rideId,
      riderId: riderId,
      driverId: driverId,
      status: status,
        isDelivery: json['isDelivery'] == true ||
          json['isDelivery'] == 1 ||
          json['deliveryDescription'] != null,
        deliveryPaymentCollected: json['deliveryPaymentCollected'] == true ||
          json['deliveryPaymentCollected'] == 1 ||
          json['deliveryPaymentCollectedAt'] != null,
    );
  }
}
