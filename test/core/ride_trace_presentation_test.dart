import 'package:admin_panel/core/ride_trace_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses valid GPS coordinates and ignores invalid rows', () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': '30.1', 'longitude': '31.2', 'capturedAtMs': '1000'},
      {'latitude': 95, 'longitude': 31.2, 'capturedAtMs': 2000},
      {'latitude': 30.1, 'longitude': 31.2},
    ]);

    expect(points, hasLength(1));
    expect(points.single.position.latitude, 30.1);
    expect(points.single.position.longitude, 31.2);
    expect(points.single.phase, RideTracePhase.trip);
  });

  test('groups actual wait accruals by location and phase', () {
    final points = RideTracePresentation.parseWaitPoints([
      {
        'latitude': 30,
        'longitude': 31,
        'phase': 'pickup',
        'waitSeconds': 30,
        'capturedAtMs': 1000,
      },
      {
        'latitude': 30.00005,
        'longitude': 31,
        'phase': 'pickup',
        'waitSeconds': 20,
        'capturedAtMs': 2000,
      },
      {
        'latitude': 30.00005,
        'longitude': 31,
        'phase': 'trip',
        'waitSeconds': 40,
        'capturedAtMs': 3000,
      },
      {
        'latitude': 30,
        'longitude': 31,
        'phase': 'trip',
        'waitSeconds': 0,
        'capturedAtMs': 4000,
      },
    ]);

    final stops = RideTracePresentation.waitStops(points);

    expect(stops, hasLength(2));
    expect(stops[0].phase, RideWaitPhase.pickup);
    expect(stops[0].duration, const Duration(seconds: 50));
    expect(stops[1].phase, RideWaitPhase.trip);
    expect(stops[1].duration, const Duration(seconds: 40));
  });

  test('actual wait markers expose the phase and recorded duration', () {
    final waitPoints = RideTracePresentation.parseWaitPoints([
      {
        'latitude': 30,
        'longitude': 31,
        'phase': 'pickup',
        'waitSeconds': 125,
        'capturedAtMs': 1000,
      },
    ]);

    final markers = RideTracePresentation.markersForRoute(
      const [],
      waitPoints: waitPoints,
    );

    expect(markers, hasLength(1));
    expect(markers.single.infoWindow.title, 'انتظار الالتقاء الفعلي');
    expect(markers.single.infoWindow.snippet, '2 د 5 ث');
  });

  test('splits approach and trip polylines while preserving legacy trip points',
      () {
    final points = RideTracePresentation.parsePoints([
      {
        'latitude': 30,
        'longitude': 31,
        'capturedAtMs': 1000,
        'phase': 'approach',
      },
      {
        'latitude': 30.001,
        'longitude': 31,
        'capturedAtMs': 2000,
        'phase': 'approach',
      },
      {'latitude': 30.002, 'longitude': 31, 'capturedAtMs': 3000},
      {
        'latitude': 30.003,
        'longitude': 31,
        'capturedAtMs': 4000,
        'phase': 'trip',
      },
    ]);

    final polylines = RideTracePresentation.polylinesForRoute(
      points,
      color: Colors.teal,
    );
    final approach = polylines.singleWhere(
      (line) => line.polylineId.value == 'ride-approach-route',
    );
    final trip = polylines.singleWhere(
      (line) => line.polylineId.value == 'ride-route',
    );

    expect(approach.color, Colors.amber);
    expect(approach.points, points.take(2).map((point) => point.position));
    expect(trip.color, Colors.teal);
    expect(trip.points, points.skip(2).map((point) => point.position));
  });

  test('detects stationary clusters lasting at least two minutes', () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': 30, 'longitude': 31, 'capturedAtMs': 0, 'speedMps': 0.2},
      {
        'latitude': 30.0001,
        'longitude': 31,
        'capturedAtMs': 60000,
        'speedMps': 0.1,
      },
      {
        'latitude': 30.00012,
        'longitude': 31,
        'capturedAtMs': 120000,
        'speedMps': 0.1,
      },
      {
        'latitude': 30.01,
        'longitude': 31,
        'capturedAtMs': 180000,
        'speedMps': 8,
      },
    ]);

    final stops = RideTracePresentation.waitingLocations(points);

    expect(stops, hasLength(1));
    expect(
      RideTracePresentation.waitingStops(points).single.duration,
      const Duration(minutes: 2),
    );
    expect(
      RideTracePresentation.distanceMeters(stops.single, points[1].position),
      lessThan(1),
    );
  });

  test('does not report a stationary cluster shorter than two minutes', () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': 30, 'longitude': 31, 'capturedAtMs': 0},
      {'latitude': 30.0001, 'longitude': 31, 'capturedAtMs': 60000},
    ]);

    expect(RideTracePresentation.waitingLocations(points), isEmpty);
  });

  test('sums only qualifying stops away from the route endpoints', () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': 30, 'longitude': 31, 'capturedAtMs': 0, 'speedMps': 8},
      {
        'latitude': 30.005,
        'longitude': 31,
        'capturedAtMs': 60000,
        'speedMps': 0.2,
      },
      {
        'latitude': 30.0051,
        'longitude': 31,
        'capturedAtMs': 180000,
        'speedMps': 0.2,
      },
      {
        'latitude': 30.01,
        'longitude': 31,
        'capturedAtMs': 240000,
        'speedMps': 8
      },
    ]);

    expect(RideTracePresentation.inTripWaitingStops(points), hasLength(1));
    expect(
      RideTracePresentation.inTripWaitingDuration(points),
      const Duration(minutes: 2),
    );
  });

  test('returns no in-trip duration when fewer than two points are available',
      () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': 30, 'longitude': 31, 'capturedAtMs': 0},
    ]);

    expect(RideTracePresentation.inTripWaitingDuration(points), isNull);
  });

  test('creates a route polyline and start, end, and waiting markers', () {
    final points = RideTracePresentation.parsePoints([
      {'latitude': 30, 'longitude': 31, 'capturedAtMs': 0, 'speedMps': 0.1},
      {
        'latitude': 30.005,
        'longitude': 31,
        'capturedAtMs': 60000,
        'speedMps': 0.2,
      },
      {
        'latitude': 30.0051,
        'longitude': 31,
        'capturedAtMs': 120000,
        'speedMps': 0.2,
      },
      {
        'latitude': 30.0052,
        'longitude': 31,
        'capturedAtMs': 180000,
        'speedMps': 0.2,
      },
      {
        'latitude': 30.01,
        'longitude': 31,
        'capturedAtMs': 240000,
        'speedMps': 8,
      },
    ]);

    final markers = RideTracePresentation.markersForRoute(points);
    final polylines = RideTracePresentation.polylinesForRoute(
      points,
      color: Colors.teal,
    );

    expect(
      markers.map((marker) => marker.markerId.value).toSet(),
      {'route-start', 'route-end', 'route-wait-0'},
    );
    expect(polylines.single.points, points.map((point) => point.position));
    expect(polylines.single.color, Colors.teal);
  });
}
