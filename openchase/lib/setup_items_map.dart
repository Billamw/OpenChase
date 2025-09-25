import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart'; // Import für DragMarker
import 'package:openchase/utils/circle_generator.dart';
import 'package:openchase/map.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/player.dart';

class ItemsTest extends StatefulWidget {
  final LatLng playAreaCenter;
  final int playareaRadius;
  final int itemCount;

  ItemsTest({
    required this.playAreaCenter,
    required this.playareaRadius,
    this.itemCount = 6,
  });

  @override
  _ItemsTestState createState() => _ItemsTestState();
}

class _ItemsTestState extends State<ItemsTest> {
  final MapController _mapController = MapController();
  List<DragMarker> _dragMarkers = [];
  bool _isLoading = true;

  // Zufällige Marker-Positionen
  List<LatLng> _markerPositions = [];

  @override
  void initState() {
    super.initState();
    _fetchWaysAndGenerateMarkers();
  }

  Future<void> _fetchWaysAndGenerateMarkers() async {
    double lat = widget.playAreaCenter.latitude;
    double lng = widget.playAreaCenter.longitude;
    int radius = widget.playareaRadius;
    String overpassUrl =
        "https://overpass-api.de/api/interpreter?data=[out:json];way(around:$radius,$lat,$lng)['highway'~'footway|path|pedestrian|cycleway|residential|tertiary|primary|secondary']['foot'!='no']['access'!='private'];(._;>;);out;";

    try {
      final response = await http.get(Uri.parse(overpassUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<LatLng> wayPoints = _parseWays(data);
        _generateRandomMarkers(wayPoints);
      }
    } catch (e) {
      print("Fehler beim Laden der Wege: $e");
    }
  }

  List<LatLng> _parseWays(dynamic data) {
    Map<int, LatLng> nodes = {};
    List<LatLng> wayPoints = [];

    for (var element in data['elements']) {
      if (element['type'] == 'node') {
        nodes[element['id']] = LatLng(element['lat'], element['lon']);
      }
    }

    for (var element in data['elements']) {
      if (element['type'] == 'way' && element['nodes'] is List) {
        for (var nodeId in element['nodes']) {
          if (nodes.containsKey(nodeId)) {
            wayPoints.add(nodes[nodeId]!);
          }
        }
      }
    }
    return wayPoints;
  }

  void _generateRandomMarkers(List<LatLng> wayPoints) {
    if (wayPoints.isEmpty) return;

    Random random = Random();
    Set<LatLng> selectedMarkers = {};
    final Distance distance = Distance();

    while (selectedMarkers.length < widget.itemCount) {
      int index = random.nextInt(wayPoints.length);
      LatLng candidate = wayPoints[index];

      double distanceToCenter = distance(widget.playAreaCenter, candidate);

      if (distanceToCenter <= widget.playareaRadius) {
        selectedMarkers.add(candidate);
      }
    }

    setState(() {
      _markerPositions = selectedMarkers.toList();
      _dragMarkers =
          _markerPositions.map((pos) {
            return DragMarker(
              key: GlobalKey<DragMarkerWidgetState>(),
              point: pos,
              size: Size(50, 50), // Marker-Größe
              offset: Offset(0, -20),
              builder: (_, currentPosition, isDragging) {
                // Bild anstelle eines Icons verwenden
                return Image.asset(
                  'images/test-item.png', // Bild für den Marker
                  width: 50,
                  height: 50,
                );
              },
              scrollMapNearEdge: true,
              scrollNearEdgeRatio: 1.5,
              scrollNearEdgeSpeed: 5.0,
              onDragEnd: (details, newPosition) {
                setState(() {
                  // Aktualisiere die Marker-Position nach dem Ziehen
                  int index = _markerPositions.indexOf(pos);
                  if (index != -1) {
                    _markerPositions[index] = newPosition;
                    print("Neue Position: $newPosition");
                  }
                });
              },
            );
          }).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ... (AppBar, etc.)
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // ... (rest of the widget tree)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: () {
                        // Create Player objects from GameManager
                        List<Player> players =
                            GameManager.players.map((playerName) {
                              // You might want to assign colors and other properties here
                              return Player(
                                name: playerName,
                                isMrX:
                                    playerName ==
                                    GameManager
                                        .roomHost, // Example logic for Mr. X
                                color: Colors.blue, // Example color
                                positionHistory: [],
                                currentPosition:
                                    widget.playAreaCenter, // Initial position
                              );
                            }).toList();

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => MapScreen(
                                  players: players, // Pass the real player list
                                  playAreaCenter: widget.playAreaCenter,
                                  playareaRadius: widget.playareaRadius,
                                ),
                          ),
                        );
                      },
                      child: Text("Ready"),
                    ),
                  ),
                ],
              ),
    );
  }
}
