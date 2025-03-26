import 'dart:math';
import 'package:latlong2/latlong.dart';

class CircleGenerator {
  static List<LatLng> generateCircle(LatLng center, double radiusInMeters) {
    const int sides = 360;
    List<LatLng> circlePoints = [];
    double lat = center.latitude;
    double lon = center.longitude;

    double radiusInDegrees = radiusInMeters / 111320;

    for (int i = 0; i < sides; i++) {
      double angle = (i * 360) / sides;
      double angleRad = angle * pi / 180.0;

      double newLat = lat + (radiusInDegrees * cos(angleRad));
      double newLon = lon + (radiusInDegrees * sin(angleRad) / cos(lat * pi / 180.0));

      circlePoints.add(LatLng(newLat, newLon));
    }
    circlePoints.add(circlePoints[0]); // Kreis schließen
    return circlePoints;
  }
}
