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
