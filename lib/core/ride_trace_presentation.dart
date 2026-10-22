import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RideTracePoint {
  const RideTracePoint({
    required this.position,
    required this.capturedAtMs,
    this.speedMps,
  });

  final LatLng position;
  final int capturedAtMs;
  final double? speedMps;
}

class RideTracePresentation {
  static Set<Marker> markersForRoute(List<RideTracePoint> points) {
    if (points.isEmpty) return const {};
    final stops = waitingLocations(points)
        .where((stop) =>
            distanceMeters(stop, points.first.position) > 30 &&
            distanceMeters(stop, points.last.position) > 30)
        .toList();
    return {
      Marker(
        markerId: const MarkerId('route-start'),
        position: points.first.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'بداية المسار'),
      ),
      Marker(
        markerId: const MarkerId('route-end'),
        position: points.last.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'نهاية المسار'),
      ),
      for (var index = 0; index < stops.length; index++)
        Marker(
          markerId: MarkerId('route-wait-$index'),
          position: stops[index],
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'نقطة انتظار محتملة'),
        ),
    };
  }

  static Set<Polyline> polylinesForRoute(
    List<RideTracePoint> points, {
    required Color color,
  }) =>
      {
        if (points.length > 1)
          Polyline(
            polylineId: const PolylineId('ride-route'),
            points: points.map((point) => point.position).toList(),
            color: color,
            width: 5,
          ),
      };

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
      ));
    }
    return points;
  }

  static List<LatLng> waitingLocations(
    List<RideTracePoint> points, {
    double radiusMeters = 30,
    Duration minimumStop = const Duration(minutes: 2),
    double maximumSpeedMps = 0.8,
  }) {
    final stops = <LatLng>[];
    var cluster = <RideTracePoint>[];

    void finishCluster() {
      if (cluster.length >= 2 &&
          cluster.last.capturedAtMs - cluster.first.capturedAtMs >=
              minimumStop.inMilliseconds) {
        stops.add(cluster[cluster.length ~/ 2].position);
      }
      cluster = [];
    }

    for (final point in points) {
      final speed = point.speedMps;
      if (speed != null && speed > maximumSpeedMps) {
        finishCluster();
        continue;
      }
      if (cluster.isEmpty) {
        cluster.add(point);
        continue;
      }
      if (point.capturedAtMs < cluster.last.capturedAtMs ||
          distanceMeters(cluster.first.position, point.position) >
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
