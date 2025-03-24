import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
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
    _user = widget.players[1]; // Setze den eigenen Benutzer (z.B. Spieler 1)

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
    _user = widget.players[1];
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
        _user.currentPosition = _currentPosition;
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
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                // Polyline für jeden Spieler
                ...widget.players.map((player) {
                  return PolylineLayer(
                    polylines: [
                      if (player.positionHistory.length > 1)
                        Polyline(
                          points: player.positionHistory,
                          strokeWidth: 5.0,
                          color: player.color, // Farbe des Spielers
                        ),
                    ],
                  );
                }).toList(),
                // MarkerLayer für alle Spieler
                MarkerLayer(
                  markers:
                      widget.players.map((player) {
                        return Marker(
                          point: player.currentPosition,
                          width: 200, // Breiter für bessere Sichtbarkeit
                          height:
                              114, // Höhe angepasst, damit Spitze genau sitzt
                          alignment: Alignment(
                            0,
                            -0.75,
                          ), // Wichtig für korrekte Positionierung
                          rotate: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 3,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  player.name,
                                  maxLines: 1, // Verhindert Umbruch
                                  overflow:
                                      TextOverflow
                                          .ellipsis, // Schneidet mit "..." ab
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 5,
                              ), // Reduzierter Abstand für bessere Position
                              GestureDetector(
                                onTap: () {
                                  _animatedMapMove(
                                    player.currentPosition,
                                    17.0,
                                  );
                                },
                                child:
                                    player.isMrX
                                        ? Image.asset(
                                          'images/mrx.png',
                                          width: 75,
                                          height: 68,
                                        )
                                        : Icon(
                                          Icons.location_on_rounded,
                                          color: player.color,
                                          size:
                                              75, // Etwas größer für perfekte Position
                                        ),
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
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
