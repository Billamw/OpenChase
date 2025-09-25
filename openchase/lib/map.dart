import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/utils/player.dart';
import 'package:openchase/utils/circle_generator.dart';
import 'package:openchase/utils/location_service.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/nostr/game_nostr.dart';

class MapScreen extends StatefulWidget {
  final List<Player> players;
  final LatLng playAreaCenter;
  final int playareaRadius;

  MapScreen({
    required this.players,
    required this.playAreaCenter,
    required this.playareaRadius,
  });

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late Player _user;
  LatLng _currentPosition = LatLng(0, 0);
  bool _loading = true;
  bool _followUser = true;
  late Timer _locationUpdateTimer;
  final GeolocatorService geolocatorService = GeolocatorService();
  late GameNostr _gameNostr;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Find the current user in the player list from GameManager
    _user = widget.players.firstWhere((p) => p.name == GameManager.userName);
    _currentPosition = widget.playAreaCenter;

    // Initialize GameNostr and listen for messages
    _gameNostr = GameNostr(
      onMessageReceived: (message) {
        if (message.containsKey("user") &&
            message.containsKey("lat") &&
            message.containsKey("lng")) {
          final playerName = message["user"];
          final lat = message["lat"];
          final lng = message["lng"];
          final newPosition = LatLng(lat, lng);

          if (mounted) {
            setState(() {
              // Find the player in the list and update their position
              try {
                final player = widget.players.firstWhere(
                  (p) => p.name == playerName,
                );
                player.updatePosition(newPosition);
                player.revealPosition();
                player.revealPositionHistory();
              } catch (e) {
                print("Player not found: $playerName");
              }
            });
          }
        }
      },
    );

    _locationUpdateTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      _updateLocation();
    });
  }

  Future<void> _updateLocation() async {
    try {
      LatLng position = await geolocatorService.getCurrentLocation();
      _gameNostr.sendLocation(position); // Send location to backend
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _user.updatePosition(position);
          _user.revealPosition();
          _user.revealPositionHistory();
          _loading = false;
        });

        if (_followUser) {
          _animatedMapMove(_currentPosition, null);
        }
      }
    } catch (e) {
      print("Fehler beim Abrufen des Standorts: $e");
    }
  }

  void _animatedMapMove(LatLng destLocation, double? destZoom) {
    // ... (rest of the _animatedMapMove method remains the same)
  }

  @override
  void dispose() {
    _locationUpdateTimer.cancel();
    _gameNostr.close();
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
                      points: CircleGenerator.generateCircle(
                        widget.playAreaCenter,
                        widget.playareaRadius.toDouble(),
                      ), // Circle as Polyline
                      strokeWidth: 8.0,
                      color: Colors.red, // Randfarbe
                    ),
                  ],
                ),
                // Polyline für Spieler
                ...widget.players.map((player) {
                  return PolylineLayer(
                    polylines: [
                      if (player.shownPositionHistory.length > 1 &&
                          player.trailVisible)
                        Polyline(
                          points: player.shownPositionHistory,
                          strokeWidth: 5.0,
                          color: player.color,
                        ),
                    ],
                  );
                }).toList(),
                // Marker für Spieler
                MarkerLayer(
                  markers:
                      widget.players.map((player) {
                        return Marker(
                          point: player.shownPosition,
                          width: 200,
                          height: 114,
                          alignment: Alignment(0, -0.75),
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              SizedBox(height: 5),
                              GestureDetector(
                                onTap: () {
                                  _animatedMapMove(player.shownPosition, 17.0);
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
                                          size: 75,
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
              IconButton(
                icon: Icon(Icons.inventory, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.map, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.settings, color: Colors.white),
                onPressed: () {},
              ),
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
