import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class GeolocatorService {
  LatLng _currentPosition = LatLng(51.1657, 10.4515); // Standardposition (z. B. Deutschland)
  Timer? _locationUpdateTimer;

  static final GeolocatorService _instance = GeolocatorService._internal();
  factory GeolocatorService() => _instance;
  GeolocatorService._internal();

  /// Gibt den aktuellen Standort zurück (einmalige Abfrage)
  Future<LatLng> getCurrentLocation() async {
    return await _updateLocation();
  }

  /// Prüft und fordert die Standortberechtigung an
  Future<bool> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
    }
    return true;
  }

  /// Holt die aktuelle Position, wenn es ein iOS- oder Android-Gerät ist,
  /// ansonsten wird die Standardposition verwendet
  Future<LatLng> _updateLocation() async {
    if (defaultTargetPlatform != TargetPlatform.linux) {
      if (!await _checkLocationPermission()) {
        print("Standortberechtigung verweigert.");
        return _currentPosition;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        print("Standortdienste sind deaktiviert.");
        return _currentPosition;
      }

      try {
        Position position = await Geolocator.getCurrentPosition();
        _currentPosition = LatLng(position.latitude, position.longitude);
      } catch (e) {
        print("Fehler beim Abrufen des Standorts: $e");
      }
    } else {
      print("Nicht-Mobile-Plattform erkannt – Standardposition wird verwendet.");
    }
    return _currentPosition;
  }
}
