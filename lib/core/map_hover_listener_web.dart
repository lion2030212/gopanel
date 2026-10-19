import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'map_hover_listener_stub.dart';

export 'map_hover_listener_stub.dart' show MapHoverListener;

MapHoverListener? attachMapHoverListener(
  int mapId,
  ValueChanged<Offset?> onPointer,
) {
  final element = web.document.getElementById(
    'plugins.flutter.io/google_maps_$mapId',
  );
  if (element == null) return null;
  return _WebMapHoverListener(element, onPointer);
}

class _WebMapHoverListener implements MapHoverListener {
  _WebMapHoverListener(web.Element element, this.onPointer) : _element = element {
    _moveListener = ((web.Event event) {
      final pointer = event as JSObject;
      final bounds = _element.getBoundingClientRect();
      onPointer(Offset(
        (pointer.getProperty('clientX'.toJS) as JSNumber).toDartDouble -
            bounds.left,
        (pointer.getProperty('clientY'.toJS) as JSNumber).toDartDouble -
            bounds.top,
      ));
    }).toJS;
    _leaveListener = ((web.Event _) => onPointer(null)).toJS;
    _element.addEventListener('pointermove', _moveListener);
    _element.addEventListener('pointerleave', _leaveListener);
  }

  final web.Element _element;
  final ValueChanged<Offset?> onPointer;
  late final JSFunction _moveListener;
  late final JSFunction _leaveListener;

  @override
  void dispose() {
    _element.removeEventListener('pointermove', _moveListener);
    _element.removeEventListener('pointerleave', _leaveListener);
  }
}