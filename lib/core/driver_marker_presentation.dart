import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static String firstName(String? fullName) {
    final normalized = fullName?.trim();
    if (normalized == null || normalized.isEmpty) return '';
    return normalized.split(RegExp(r'\s+')).first;
  }

  static String? preserveIdentityValue(String? incoming, String? existing) {
    final normalized = incoming?.trim();
    return normalized == null || normalized.isEmpty ? existing : normalized;
  }

  static InfoWindow infoWindow({
    required String role,
    required int id,
    required String? fullName,
    required String? phone,
    required String status,
    required String lastUpdated,
  }) {
    final name = firstName(fullName);
    final normalizedPhone = phone?.trim();
    return InfoWindow(
      title: name.isEmpty ? '$role $id' : '$role $name',
      snippet:
          'الجوال: ${normalizedPhone == null || normalizedPhone.isEmpty ? 'غير متوفر' : normalizedPhone}\nالحالة: $status\nآخر تحديث: $lastUpdated',
    );
  }

  static final Map<Color, Future<BitmapDescriptor>> _markerIcons = {};
  static final Map<Color, Future<BitmapDescriptor>> _driverMarkerIcons = {};
  static Future<ui.Image>? _carImage;

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

  static Future<BitmapDescriptor> driverMarkerIcon(Color color) =>
      _driverMarkerIcons.putIfAbsent(
        color,
        () => _createDriverMarkerIcon(color),
      );

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

  static Future<BitmapDescriptor> _createDriverMarkerIcon(Color color) async {
    const imageSize = 84;
    final carImage = await (_carImage ??= _loadCarImage());
    final coloredCarImage = await _colorizeCarBody(carImage, color);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final carAspectRatio = coloredCarImage.width / coloredCarImage.height;
    final carWidth = carAspectRatio >= 1.2 ? 68.0 : 56.0 * carAspectRatio;
    final carHeight = carWidth / carAspectRatio;
    final carRect = Rect.fromLTWH(
      (imageSize - carWidth) / 2,
      (imageSize - carHeight) / 2 - 5,
      carWidth,
      carHeight,
    );
    canvas.drawImageRect(
      coloredCarImage,
      Rect.fromLTWH(
        0,
        0,
        coloredCarImage.width.toDouble(),
        coloredCarImage.height.toDouble(),
      ),
      carRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    coloredCarImage.dispose();

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageSize, imageSize);
    picture.dispose();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) throw StateError('تعذر إنشاء أيقونة دبوس السائق');

    return BitmapDescriptor.bytes(
      byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      width: 42,
      height: 42,
    );
  }

  static Future<ui.Image> _colorizeCarBody(ui.Image carImage, Color color) async {
    final byteData = await carImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw StateError('تعذر تعديل لون أيقونة السيارة');
    }

    final pixels = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final targetColor = HSLColor.fromColor(color);
    for (var offset = 0; offset < pixels.length; offset += 4) {
      final red = pixels[offset];
      final green = pixels[offset + 1];
      final blue = pixels[offset + 2];
      final isOrangeBody =
          red > 70 && red - green > 18 && green - blue > 12;
      if (!isOrangeBody) continue;

      final lightness = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;
      final replacement = targetColor
          .withLightness(lightness.clamp(0.18, 0.82))
          .toColor();
        pixels[offset] = (replacement.r * 255).round().clamp(0, 255).toInt();
        pixels[offset + 1] =
          (replacement.g * 255).round().clamp(0, 255).toInt();
        pixels[offset + 2] =
          (replacement.b * 255).round().clamp(0, 255).toInt();
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: carImage.width,
        height: carImage.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  static Future<ui.Image> _loadCarImage() async {
    final data = await rootBundle.load('web/car.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
