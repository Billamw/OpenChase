import 'dart:async';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// Simulated GPS source for local dev/testing builds.
/// Enable with `--dart-define=SIM=true`. Then W/A/S/D keys
/// (W = north, S = south, A = west, D = east, hold Shift = fast ~30 m/s)
/// continuously integrate this instance's position, which is fed through
/// the normal pipeline: GeolocatorService -> RoomClient.sendLocation ->
/// relays -> other players' maps, trails and item pickup checks.
class SimLocation {
  static const enabled = bool.fromEnvironment('SIM');
  static double lat = 50.94;
  static double lng = 6.96;
  static double speedMps = 6.0; // walking pace; Shift multiplies
  static const double _fastMps = 30.0;
  static const double _tickSec = 0.2;
  static Timer? _timer;

  /// Start each window at a different spot, e.g.
  /// --dart-define=SIM_DY=0.001 offsets north for this build.
  static final double _spawnDy = double.tryParse(
        const String.fromEnvironment('SIM_DY')) ??
    0.0;
  static final double _spawnDx = double.tryParse(
        const String.fromEnvironment('SIM_DX')) ??
    0.0;

  static void init() {
    if (!enabled) return;
    lat += _spawnDy;
    lng += _spawnDx;
    _timer?.cancel();
    // HardwareKeyboard is app-global, so no focus widget is needed.
    _timer = Timer.periodic(
      Duration(microseconds: (_tickSec * 1e6).round()),
      (_) {
        final k = HardwareKeyboard.instance;
        final fast = k.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
            k.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
        final meters = (fast ? _fastMps : speedMps) * _tickSec;
        final dLat = (k.isLogicalKeyPressed(LogicalKeyboardKey.keyW) ? 1 : 0) -
            (k.isLogicalKeyPressed(LogicalKeyboardKey.keyS) ? 1 : 0);
        final dLng = (k.isLogicalKeyPressed(LogicalKeyboardKey.keyD) ? 1 : 0) -
            (k.isLogicalKeyPressed(LogicalKeyboardKey.keyA) ? 1 : 0);
        if (dLat == 0 && dLng == 0) return;
        const mPerDegLat = 111320.0;
        const mPerDegLng = 111320.0 * 0.63; // cos(~50.9 deg)
        lat += meters * dLat / mPerDegLat;
        lng += meters * dLng / mPerDegLng;
      },
    );
  }

  static LatLng get current => LatLng(lat, lng);

  static void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
