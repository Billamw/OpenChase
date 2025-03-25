import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/utils/player.dart';
import 'dart:math';


class MapScreen extends StatefulWidget {
  final List<Player> players; // Liste der Spieler wird übergeben
  final LatLng playAreaCenter;
  final int playareaRadius;


  // Konstruktor, um die Liste der Spieler zu erhalten
  MapScreen({required this.players, required this.playAreaCenter, required this.playareaRadius});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late Player _user; // Der eigene Benutzer
  LatLng _currentPosition = LatLng(0, 0);
  bool _loading = true;
  bool _followUser = true;
  late Timer _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _user = widget.players[0];
    _currentPosition = widget.playAreaCenter;

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
      _currentPosition = widget.playAreaCenter;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Standortdienste sind deaktiviert. Bitte aktivieren Sie sie in den Einstellungen.',
            ),
          ),
        );
      }
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _user.currentPosition = _currentPosition;
          _user.positionHistory.add(_currentPosition); // Position speichern
          _loading = false;
        });
      }

      if (_followUser) {
        _animatedMapMove(_currentPosition, null);
      }
    } catch (e) {
      print("Fehler beim Abrufen des Standorts: $e");
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
        destZoom != null
            ? Tween<double>(begin: camera.zoom, end: destZoom)
            : Tween<double>(begin: camera.zoom, end: camera.zoom);

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
        zoomTween.evaluate(animation),
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

  List<LatLng> _generateCircle(LatLng center, double radiusInMeters) {
    const int sides = 360; // The number of sides to simulate a circle
    List<LatLng> circlePoints = [];
    double lat = center.latitude;
    double lon = center.longitude;

    // Radius in degrees (approximate)
    double radiusInDegrees = radiusInMeters / 111320;

    for (int i = 0; i < sides; i++) {
      double angle = (i * 360) / sides;
      double angleRad = angle * pi / 180.0;

      double newLat = lat + (radiusInDegrees * cos(angleRad));
      double newLon = lon + (radiusInDegrees * sin(angleRad) / cos(lat * pi / 180.0));

      circlePoints.add(LatLng(newLat, newLon));
    }
  circlePoints.add(circlePoints[0]); // Ersten Punkt wieder anhängen, um den Kreis zu schließen
print("Kreise");
    return circlePoints;
  }

  @override
void dispose() {
  // Timer abbrechen, um Fehler zu vermeiden, wenn das Widget nicht mehr existiert
  _locationUpdateTimer.cancel();
  super.dispose();}// Ja das mit dem disposen funktioniert auch noch nicht richtig

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
              tileProvider: CancellableNetworkTileProvider(),
            ),
                                PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _generateCircle(widget.playAreaCenter, widget.playareaRadius.toDouble()), // Circle as Polyline
                          strokeWidth: 8.0,
                          color: Colors.red, // Randfarbe
                        ),
                      ],
                    ),
            // Polyline für Spieler
            ...widget.players.map((player) {
              return PolylineLayer(
                polylines: [
                  if (player.positionHistory.length > 1)
                    Polyline(
                      points: player.positionHistory,
                      strokeWidth: 5.0,
                      color: player.color,
                    ),
                ],
              );
            }).toList(),
            // Marker für Spieler
            MarkerLayer(
              markers: widget.players.map((player) {
                return Marker(
                  point: player.currentPosition,
                  width: 200,
                  height: 114,
                  alignment: Alignment(0, -0.75),
                  rotate: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2))],
                        ),
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                      SizedBox(height: 5),
                      GestureDetector(
                        onTap: () {
                          _animatedMapMove(player.currentPosition, 17.0);
                        },
                        child: player.isMrX
                            ? Image.asset('images/mrx.png', width: 75, height: 68)
                            : Icon(Icons.location_on_rounded, color: player.color, size: 75),
                      ),
                    ],
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
  floatingActionButton: FloatingActionButton(
    onPressed: () {
      setState(() {
        _followUser = true;
      });
      _animatedMapMove(_currentPosition, null);
      _rotateMapBackToNorth();
    },
    child: Icon(Icons.my_location),
  ),
  bottomNavigationBar: BottomAppBar(
    color: Colors.blueGrey[900],
    shape: CircularNotchedRectangle(),
    child: Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.inventory, color: Colors.white), onPressed: () {}),
          IconButton(icon: Icon(Icons.map, color: Colors.white), onPressed: () {}),
          IconButton(icon: Icon(Icons.settings, color: Colors.white), onPressed: () {}),
        ],
      ),
    ),
  ),
);
  }

  // Map rotation animation to North
  void _rotateMapBackToNorth() {
    _mapController.rotate(0);
  }
}
