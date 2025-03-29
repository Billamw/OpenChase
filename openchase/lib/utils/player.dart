import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Player {
  final String name;
  final Color color;
  final List<LatLng> positionHistory;
  late List<LatLng> shownPositionHistory = [];
  late LatLng currentPosition;
  bool trailVisible = true;
  bool visible = true;
  late LatLng shownPosition;

  bool isMrX;

  Player({
    required this.name,
    required this.positionHistory,
    required this.currentPosition,
    required this.color,
    this.isMrX = false,
  });

  void updatePosition(LatLng newPosition) {
    positionHistory.add(newPosition);
    newPosition = currentPosition;
  }

  void revealPosition() {
    shownPosition = currentPosition;
  }

  void revealPositionHistory() {
    shownPositionHistory = positionHistory;
  }

void setTrailVisibility(bool visible) {
  trailVisible = visible;
}

void setVisibility (bool visible) {
  this.visible = visible;
}
}
