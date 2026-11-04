import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RideTracePhase { approach, trip }

enum RideWaitPhase { pickup, trip }

class RideTracePoint {
  const RideTracePoint({
    required this.position,
    required this.capturedAtMs,
    this.speedMps,
    this.phase = RideTracePhase.trip,
  });

  final LatLng position;
  final int capturedAtMs;
  final double? speedMps;
  final RideTracePhase phase;
}

class RideTraceStop {
  const RideTraceStop({required this.position, required this.duration});

  final LatLng position;
  final Duration duration;
}

class RideWaitPoint {
  const RideWaitPoint({
    required this.position,
    required this.phase,
    required this.waitSeconds,
    required this.capturedAtMs,
  });

  final LatLng position;
  final RideWaitPhase phase;
  final int waitSeconds;
  final int capturedAtMs;
}

class RideWaitStop {
  const RideWaitStop({
    required this.position,
    required this.phase,
    required this.duration,
  });

  final LatLng position;
  final RideWaitPhase phase;
  final Duration duration;
}

class RideTracePresentation {
  static Set<Marker> markersForRoute(
    List<RideTracePoint> points, {
    List<RideWaitPoint> waitPoints = const [],
  }) {
    if (points.isEmpty && waitPoints.isEmpty) return const {};
    final actualStops =
        waitPoints.isEmpty ? const <RideWaitStop>[] : waitStops(waitPoints);
    final inferredStops = waitPoints.isNotEmpty || points.isEmpty
        ? const <LatLng>[]
        : waitingLocations(points)
            .where((stop) =>
                distanceMeters(stop, points.first.position) > 30 &&
                distanceMeters(stop, points.last.position) > 30)
            .toList();
    return {
      if (points.isNotEmpty)
        Marker(
          markerId: const MarkerId('route-start'),
          position: points.first.position,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'بداية المسار'),
        ),
      if (points.isNotEmpty)
        Marker(
          markerId: const MarkerId('route-end'),
          position: points.last.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'نهاية المسار'),
        ),
      for (var index = 0; index < inferredStops.length; index++)
        Marker(
          markerId: MarkerId('route-wait-$index'),
          position: inferredStops[index],
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'نقطة انتظار محتملة'),
        ),
      for (var index = 0; index < actualStops.length; index++)
        Marker(
          markerId:
              MarkerId('route-wait-${actualStops[index].phase.name}-$index'),
          position: actualStops[index].position,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: actualStops[index].phase == RideWaitPhase.pickup
                ? 'انتظار الالتقاء الفعلي'
                : 'انتظار الرحلة الفعلي',
            snippet: formatWaitDuration(actualStops[index].duration),
          ),
        ),
    };
  }

  static Set<Polyline> polylinesForRoute(
    List<RideTracePoint> points, {
    required Color color,
    Color approachColor = Colors.amber,
  }) {
    final approachPoints = pointsForPhase(points, RideTracePhase.approach);
    final tripPoints = pointsForPhase(points, RideTracePhase.trip);
    return {
      if (approachPoints.length > 1)
        Polyline(
          polylineId: const PolylineId('ride-approach-route'),
          points: approachPoints.map((point) => point.position).toList(),
          color: approachColor,
          width: 5,
        ),
      if (tripPoints.length > 1)
        Polyline(
          polylineId: const PolylineId('ride-route'),
          points: tripPoints.map((point) => point.position).toList(),
          color: color,
          width: 5,
        ),
    };
  }

  static List<RideTracePoint> pointsForPhase(
    List<RideTracePoint> points,
    RideTracePhase phase,
  ) =>
      points.where((point) => point.phase == phase).toList();

  static List<RideTracePoint> parsePoints(dynamic value) {
    if (value is! List) return const [];
    final points = <RideTracePoint>[];
    for (final item in value) {
      if (item is! Map) continue;
      final latitude = double.tryParse(item['latitude']?.toString() ?? '');
      final longitude = double.tryParse(item['longitude']?.toString() ?? '');
      final capturedAtMs = int.tryParse(item['capturedAtMs']?.toString() ?? '');
      final speedMps = item['speedMps'] == null
          ? null
          : double.tryParse(item['speedMps'].toString());
      final phase = item['phase'] == 'approach'
          ? RideTracePhase.approach
          : RideTracePhase.trip;
      if (latitude == null ||
          longitude == null ||
          capturedAtMs == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }
      points.add(RideTracePoint(
        position: LatLng(latitude, longitude),
        capturedAtMs: capturedAtMs,
        speedMps: speedMps,
        phase: phase,
      ));
    }
    return points;
  }

  static List<RideWaitPoint> parseWaitPoints(dynamic value) {
    if (value is! List) return const [];
    final points = <RideWaitPoint>[];
    for (final item in value) {
      if (item is! Map) continue;
      final latitude = double.tryParse(item['latitude']?.toString() ?? '');
      final longitude = double.tryParse(item['longitude']?.toString() ?? '');
      final waitSeconds = int.tryParse(item['waitSeconds']?.toString() ?? '');
      final capturedAtMs = int.tryParse(item['capturedAtMs']?.toString() ?? '');
      final phase = switch (item['phase']) {
        'pickup' => RideWaitPhase.pickup,
        'trip' => RideWaitPhase.trip,
        _ => null,
      };
      if (latitude == null ||
          longitude == null ||
          waitSeconds == null ||
          capturedAtMs == null ||
          phase == null ||
          waitSeconds <= 0 ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }
      points.add(RideWaitPoint(
        position: LatLng(latitude, longitude),
        phase: phase,
        waitSeconds: waitSeconds,
        capturedAtMs: capturedAtMs,
      ));
    }
    return points;
  }

  static List<RideWaitStop> waitStops(
    List<RideWaitPoint> points, {
    double radiusMeters = 20,
  }) {
    final stops = <RideWaitStop>[];
    for (final point in points) {
      final nearbyIndex = stops.indexWhere((stop) =>
          stop.phase == point.phase &&
          distanceMeters(stop.position, point.position) <= radiusMeters);
      if (nearbyIndex == -1) {
        stops.add(RideWaitStop(
          position: point.position,
          phase: point.phase,
          duration: Duration(seconds: point.waitSeconds),
        ));
        continue;
      }
      final existing = stops[nearbyIndex];
      stops[nearbyIndex] = RideWaitStop(
        position: existing.position,
        phase: existing.phase,
        duration: existing.duration + Duration(seconds: point.waitSeconds),
      );
    }
    return stops;
  }

  static String formatWaitDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes < 60) {
      if (minutes == 0) return '$seconds ث';
      return seconds == 0 ? '$minutes دقيقة' : '$minutes د $seconds ث';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final time =
        remainingMinutes == 0 ? '$hours س' : '$hours س $remainingMinutes د';
    return seconds == 0 ? time : '$time $seconds ث';
  }

  static List<RideTraceStop> waitingStops(
    List<RideTracePoint> points, {
    double radiusMeters = 10,
    Duration minimumStop = const Duration(minutes: 2),
    double maximumSpeedMps = 0.8,
  }) {
    final stops = <RideTraceStop>[];
    var cluster = <RideTracePoint>[];

    void finishCluster() {
      if (cluster.length >= 2 &&
          cluster.last.capturedAtMs - cluster.first.capturedAtMs >=
              minimumStop.inMilliseconds) {
        stops.add(RideTraceStop(
          position: cluster[cluster.length ~/ 2].position,
          duration: Duration(
            milliseconds:
                cluster.last.capturedAtMs - cluster.first.capturedAtMs,
          ),
        ));
      }
      cluster = [];
    }

    for (final point in points) {
      final speed = point.speedMps;
      if (speed != null &&
          speed.isFinite &&
          speed >= 0 &&
          speed > maximumSpeedMps) {
        finishCluster();
        continue;
      }
      if (cluster.isEmpty) {
        cluster.add(point);
        continue;
      }
      if (point.capturedAtMs < cluster.last.capturedAtMs ||
          distanceMeters(cluster.last.position, point.position) >
              radiusMeters) {
        finishCluster();
        cluster.add(point);
        continue;
      }
      cluster.add(point);
    }
    finishCluster();
    return stops;
  }

  static List<LatLng> waitingLocations(
    List<RideTracePoint> points, {
    double radiusMeters = 10,
    Duration minimumStop = const Duration(minutes: 2),
    double maximumSpeedMps = 0.8,
  }) =>
      waitingStops(
        points,
        radiusMeters: radiusMeters,
        minimumStop: minimumStop,
        maximumSpeedMps: maximumSpeedMps,
      ).map((stop) => stop.position).toList();

  static List<RideTraceStop> inTripWaitingStops(
    List<RideTracePoint> points,
  ) =>
      waitingStops(points)
          .where((stop) =>
              distanceMeters(stop.position, points.first.position) > 30 &&
              distanceMeters(stop.position, points.last.position) > 30)
          .toList();

  static Duration? inTripWaitingDuration(List<RideTracePoint> points) {
    if (points.length < 2) return null;
    return inTripWaitingStops(points).fold<Duration>(
      Duration.zero,
      (total, stop) => total + stop.duration,
    );
  }

  static double distanceMeters(LatLng first, LatLng second) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final firstLatitude = _radians(first.latitude);
    final secondLatitude = _radians(second.latitude);
    final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadiusMeters * 2 * math.asin(math.sqrt(haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
