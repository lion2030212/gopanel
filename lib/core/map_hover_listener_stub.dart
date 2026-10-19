import 'package:flutter/widgets.dart';

abstract interface class MapHoverListener {
  void dispose();
}

MapHoverListener? attachMapHoverListener(
  int mapId,
  ValueChanged<Offset?> onPointer,
) =>
    null;