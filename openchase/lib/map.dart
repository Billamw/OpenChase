import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:openchase/utils/player.dart';

class MapScreen extends StatefulWidget {
  final List<Player> players; // Liste der Spieler wird übergeben

  // Konstruktor, um die Liste der Spieler zu erhalten
  MapScreen({required this.players});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late Player _user; // Der eigene Benutzer
  LatLng _currentPosition = LatLng(48.1351, 11.5820); // Standard: München
  bool _loading = true;
  bool _followUser = true;
  late Timer _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _user = widget.players[0]; // Setze den eigenen Benutzer (z.B. Spieler 3)

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      _checkLocationPermission();
    } else {
      _setDefaultLocation();
    }

    // Timer starten, um alle 3 Sekunden den Standort zu aktualisieren
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 3), (timer) {
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
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Standortdienste sind deaktiviert. Bitte aktivieren Sie sie in den Einstellungen.',
            ),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _user.currentPosition=_currentPosition;
        _user.positionHistory.add(_currentPosition); // Position speichern
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

    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destLocation.longitude,
    );

    final zoomTween =
        destZoom != null ? Tween<double>(begin: camera.zoom, end: destZoom) : Tween<double>(begin: camera.zoom, end: camera.zoom);

    final controller = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(
          animation,
        ),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karte mit Standort')),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
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
                // Polyline wird nur gezeichnet, wenn mindestens 2 Punkte vorhanden sind
                if (_user.positionHistory.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _user.positionHistory,
                        strokeWidth: 5.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                // MarkerLayer für alle Spieler
                MarkerLayer(
                  markers: widget.players.map((player) {
                    return Marker(
                      point: player.currentPosition,
                      width: 50,
                      height: 50,
                      alignment: Alignment(0, -1),
                      rotate: true,
                      child: player.isMrX
                          ? Image.asset(
                              'images/mrx.png', // Bild für MrX
                              width: 50,
                              height: 50,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: player.color, // Farbe des Spielers
                                shape: BoxShape.circle,
                              ),
                              width: 30,
                              height: 30,
                            ),
                    );
                  }).toList(),
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
            onPressed:
                _loading
                    ? null
                    : () {
                        setState(() {
                          _followUser = true; // Setze followUser auf true
                        });
                        _animatedMapMove(
                          _currentPosition,
                          null,
                        ); // Bewege die Karte zur aktuellen Position
                        _rotateMapBackToNorth();
                      },
            child: Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // Map rotation animation to North
  void _rotateMapBackToNorth() {
    _mapController.rotate(0);
  }
}
