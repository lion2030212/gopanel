import 'package:flutter/material.dart';

class MapStatsOverlay extends StatelessWidget {
  const MapStatsOverlay({
    required this.onlineGoFast,
    required this.onlineGoTalabat,
    required this.onlineGoScooter,
    required this.offlineDrivers,
    required this.riders,
    required this.activeRides,
    super.key,
  });

  final int onlineGoFast;
  final int onlineGoTalabat;
  final int onlineGoScooter;
  final int offlineDrivers;
  final int riders;
  final int activeRides;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapStatCircle(
          label: 'GoFast',
          count: onlineGoFast,
          iconAsset: 'web/car.png',
          color: const Color(0xFF167A54),
        ),
        const SizedBox(height: 6),
        _MapStatCircle(
          label: 'GoTalabat',
          count: onlineGoTalabat,
          iconAsset: 'web/dev.png',
          color: const Color(0xFF167A54),
        ),
        const SizedBox(height: 6),
        _MapStatCircle(
          label: 'GoScooter',
          count: onlineGoScooter,
          iconAsset: 'web/sco.png',
          color: const Color(0xFF167A54),
        ),
        const SizedBox(height: 6),
        _MapStatCircle(
          label: 'سائقون أوفلاين',
          count: offlineDrivers,
          color: const Color(0xFF58636B),
        ),
        const SizedBox(height: 6),
        _MapStatCircle(
          label: 'ركاب بالخريطة',
          count: riders,
          color: const Color(0xFF176B91),
        ),
        const SizedBox(height: 6),
        _MapStatCircle(
          label: 'رحلات نشطة',
          count: activeRides,
          color: const Color(0xFFB45B1D),
        ),
      ],
    );
  }
}

class _MapStatCircle extends StatelessWidget {
  const _MapStatCircle({
    required this.label,
    required this.count,
    required this.color,
    this.iconAsset,
  });

  final String label;
  final int count;
  final Color color;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $count',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconAsset != null)
                    Image.asset(
                      iconAsset!,
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  if (iconAsset != null) const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: iconAsset == null ? 9 : 8,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
