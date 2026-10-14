import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverMarkerPresentation {
  const DriverMarkerPresentation({required this.label, required this.color});

  final String label;
  final Color color;

  static const Color offlineColor = Color(0xFFD93645);
  static const Color onlineColor = Color(0xFFF2C230);
  static const Color activeRideColor = Color(0xFF278A58);
  static const Color riderOnlineColor = Color(0xFF167D8D);
  static const Color riderActiveRideColor = Color(0xFFE56B3F);

  static final Map<Color, Future<BitmapDescriptor>> _markerIcons = {};

  static DriverMarkerPresentation fromDriver({
    required bool isOnline,
    required String status,
  }) {
    if (!isOnline) {
      return const DriverMarkerPresentation(
        label: 'غير متصل',
        color: offlineColor,
      );
    }
    if (status == 'active') {
      return const DriverMarkerPresentation(
        label: 'في رحلة',
        color: activeRideColor,
      );
    }
    return const DriverMarkerPresentation(
      label: 'متصل',
      color: onlineColor,
    );
  }

  static DriverMarkerPresentation fromRider({required bool hasActiveRide}) =>
      DriverMarkerPresentation(
        label: hasActiveRide ? 'في رحلة' : 'متصل',
        color: hasActiveRide ? riderActiveRideColor : riderOnlineColor,
      );

  static Future<BitmapDescriptor> markerIcon(Color color) =>
      _markerIcons.putIfAbsent(color, () => _createMarkerIcon(color));

  static Future<BitmapDescriptor> _createMarkerIcon(Color color) async {
    const imageWidth = 72;
    const imageHeight = 88;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final pinPath = Path()
      ..moveTo(36, 85)
      ..cubicTo(31, 78, 10, 54, 10, 34)
      ..cubicTo(10, 19, 21, 7, 36, 7)
      ..cubicTo(51, 7, 62, 19, 62, 34)
      ..cubicTo(62, 54, 41, 78, 36, 85)
      ..close();

    canvas.drawPath(
      pinPath.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(pinPath, Paint()..color = color);
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(const Offset(36, 32), 12, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(36, 32), 5, Paint()..color = color);

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    picture.dispose();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) throw StateError('تعذر إنشاء أيقونة دبوس السائق');

    return BitmapDescriptor.bytes(
      byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      width: 36,
      height: 44,
    );
  }
}
