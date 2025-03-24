import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  LatLng _currentPosition = LatLng(48.1351, 11.5820); // Standard: München
  bool _loading = true;
  bool _followUser = true;
  late Timer _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      _checkLocationPermission();
    } else {
      _setDefaultLocation();
    }

    // Timer starten, um alle 1 Sekunde den Standort zu aktualisieren
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _getCurrentLocation();
    });
  }

  // Methode für nicht-mobile Plattformen (z.B. Web, Desktop)
  void _setDefaultLocation() {
    setState(() {
      _currentPosition = LatLng(51.1657, 10.4515); // Beispiel: Deutschland
      _loading = false;
    });
    _animatedMapMove(_currentPosition, 16.0);
  }

  // Standortberechtigung prüfen
  Future<void> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Standortberechtigung wurde abgelehnt.')),
        );
        return;
      }
    }
    _getCurrentLocation();
  }

  // Aktuellen Standort abrufen
  Future<void> _getCurrentLocation() async {
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Standortdienste sind deaktiviert. Bitte aktivieren Sie sie in den Einstellungen.')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
      if (_followUser) {
        _animatedMapMove(_currentPosition, null);
      }
    } else {
      _setDefaultLocation();
    }
  }

  // Animierte Bewegung der Karte
  void _animatedMapMove(LatLng destLocation, double? destZoom) {
    final camera = _mapController.camera;
    
    // Position Tween
    final latTween = Tween<double>(begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: destLocation.longitude);

    // Wenn destZoom null ist, wird der Zoom nicht verändert
    final zoomTween = destZoom != null 
        ? Tween<double>(begin: camera.zoom, end: destZoom) 
        : Tween<double>(begin: camera.zoom, end: camera.zoom);

    final controller = AnimationController(duration: Duration(milliseconds: 500), vsync: this);
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),  // Nur anpassen, wenn destZoom nicht null ist
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  

// Map rotation animation to North
void _rotateMapBackToNorth() {
  _mapController.rotate(0);
}

  @override
  void dispose() {
    _locationUpdateTimer.cancel();  // Timer stoppen
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karte mit Standort')),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
              // Hier setzen wir _followUser auf false, wenn auf die Karte getippt wird.
              setState(() {
                _followUser = false;
              });
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 16,
                maxZoom: 19.6,
                minZoom: 4.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 100,
                      height: 100,
                      alignment: Alignment(0, -1),
                      rotate: true,
                      child: Image.asset('images/mrx.png', width: 100, height: 100),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _loading ? null : () {
              setState(() {
                _followUser = true;  // Setze followUser auf true
              });
              _animatedMapMove(_currentPosition, null);  // Bewege die Karte zur aktuellen Position
              _rotateMapBackToNorth();
            },
            child: Icon(Icons.my_location),
          )
        ],
      ),
    );
  }
}