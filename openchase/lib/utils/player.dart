import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Player {
  final String name;
  final Color color;
  final List<LatLng> positionHistory;
  late LatLng currentPosition;

  bool isMrX;

  Player({
    required this.name,
    required this.positionHistory,
    required this.currentPosition,
    required this.color,
    this.isMrX = false,
  });

  void updatePosition(LatLng newPosition) {
    currentPosition = newPosition;
    positionHistory.add(newPosition);
  }
}
