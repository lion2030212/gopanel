import 'package:flutter/material.dart';

class RideRoutePresentation {
  static Map<int, Color> colorsForRideIds(Iterable<int> rideIds) {
    final sortedIds = rideIds.where((id) => id > 0).toSet().toList()..sort();
    final usedHues = <int>{};
    final colors = <int, Color>{};

    for (final rideId in sortedIds) {
      var hue = (rideId * 137) % 360;
      var attempts = 0;
      while (usedHues.contains(hue) && attempts < 360) {
        hue = (hue + 47) % 360;
        attempts++;
      }
      usedHues.add(hue);
      colors[rideId] =
          HSVColor.fromAHSV(1, hue.toDouble(), 0.82, 0.88).toColor();
    }

    return colors;
  }

  static bool hasFreshLocation(
    DateTime? updatedAt, {
    required int maxAgeSeconds,
    DateTime? now,
  }) {
    if (updatedAt == null || maxAgeSeconds <= 0) return false;
    final age = (now ?? DateTime.now()).difference(updatedAt.toLocal());
    return age >= const Duration(seconds: -15) &&
      age <= Duration(seconds: maxAgeSeconds);
  }
}
