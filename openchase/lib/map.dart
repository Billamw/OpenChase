import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:openchase/utils/player.dart';
import 'package:openchase/utils/location_service.dart';
import 'package:openchase/utils/circle_generator.dart';

class MapScreen extends StatefulWidget {
  final List<Player> players;
  final LatLng playAreaCenter;
  final int playareaRadius;

  MapScreen({required this.players, required this.playAreaCenter, required this.playareaRadius});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late Player _user;
  LatLng _currentPosition = LatLng(0, 0);
  bool _loading = true;
  bool _followUser = true;
  final GeolocatorService _geolocatorService = GeolocatorService(); // 🔹 Instanz des GeolocatorService

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _user = widget.players[0];
    _currentPosition = widget.playAreaCenter;

    // 🔹 Aktuellen Standort abrufen und regelmäßige Updates starten
    _initializeLocation();
  }

  /// Holt die aktuelle Position und startet das Tracking
  void _initializeLocation() async {
    LatLng position = await _geolocatorService.getCurrentLocation();
    setState(() {
      _currentPosition = position;
      _loading = false;
    });

    // 🔹 Starte regelmäßige Standortaktualisierung
    _geolocatorService.startLocationUpdates();
  }

  // Animierte Bewegung der Karte
  void _animatedMapMove(LatLng destLocation, double? destZoom) {
    final camera = _mapController.camera;

    final latTween = Tween<double>(begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom ?? camera.zoom);

    final controller = AnimationController(duration: Duration(milliseconds: 500), vsync: this);
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }



  @override
  void dispose() {
    _geolocatorService.stopLocationUpdates(); // 🔹 Stoppe Standortupdates
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karte mit Standort')),
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) {
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
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: CircleGenerator.generateCircle(widget.playAreaCenter, widget.playareaRadius.toDouble()),
                      strokeWidth: 8.0,
                      color: Colors.red,
                    ),
                  ],
                ),
                // Spieler-Polylines
                ...widget.players.map((player) {
                  return PolylineLayer(
                    polylines: [
                      if (player.positionHistory.length > 1)
                        Polyline(points: player.positionHistory, strokeWidth: 5.0, color: player.color),
                    ],
                  );
                }).toList(),
                // Spieler-Marker
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

  void _rotateMapBackToNorth() {
    _mapController.rotate(0);
  }
}
