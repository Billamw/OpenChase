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

  // Round settings chosen at session start.
  int _durationMin = 30;
  static const _durations = [15, 30, 45, 60, 90];
  final Set<String> _hiderSel = {};

  // Zufällige Marker-Positionen
  List<LatLng> _markerPositions = [];

  @override
  void initState() {
    super.initState();
    _fetchWaysAndGenerateMarkers();
  }

  /// Hiders must stay a minority: at most (n-1)/2 of the roster.
  int _maxHiders(int n) => max(1, (n - 1) ~/ 2);

  void _toggleHider(String pk) {
    final roster = GameManager.roomClient?.playerPubkeys.length ?? 0;
    if (!_hiderSel.contains(pk) && _hiderSel.length >= _maxHiders(roster)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hiders must stay fewer than chasers')),
      );
      return;
    }
    setState(() {
      if (_hiderSel.contains(pk)) {
        _hiderSel.remove(pk);
      } else {
        _hiderSel.add(pk);
      }
    });
  }

  void _randomHiders() {
    final client = GameManager.roomClient;
    if (client == null) return;
    final pks = client.playerPubkeys.keys.toList()..shuffle();
    final k = _maxHiders(pks.length);
    setState(() {
      _hiderSel
        ..clear()
        ..addAll(pks.take(k));
    });
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 4.0,
                    ),
                    child: Row(
                      children: [
                        const Text('Round duration: '),
                        DropdownButton<int>(
                          value: _durationMin,
                          items: const [
                            DropdownMenuItem(
                              value: 15,
                              child: Text('15 min'),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('30 min'),
                            ),
                            DropdownMenuItem(
                              value: 45,
                              child: Text('45 min'),
                            ),
                            DropdownMenuItem(
                              value: 60,
                              child: Text('60 min'),
                            ),
                            DropdownMenuItem(
                              value: 90,
                              child: Text('90 min'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _durationMin = v ?? 30),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hiders (pick ${GameManager.roomClient != null ? '1-${_maxHiders(GameManager.roomClient!.playerPubkeys.length)}' : '—'}):',
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final entry
                                in GameManager
                                    .roomClient
                                    ?.playerPubkeys
                                    .entries ??
                                <MapEntry<String, String>>[])
                              ChoiceChip(
                                label: Text(entry.value),
                                selected: _hiderSel.contains(entry.key),
                                onSelected: (selected) =>
                                    _toggleHider(entry.key),
                              ),
                            ActionChip(
                              label: const Text('Random'),
                              avatar: const Icon(Icons.shuffle, size: 16),
                              onPressed: _randomHiders,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: () {
                        // Host publishes the round: area + placed items go out
                        // over the room channel; players auto-navigate.
                        final client = GameManager.roomClient;
                        final rosterSize =
                            client?.playerPubkeys.length ?? 0;
                        if (_hiderSel.isEmpty ||
                            _hiderSel.length > _maxHiders(rosterSize)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Pick 1-${_maxHiders(rosterSize)} hiders (or press Random)',
                              ),
                            ),
                          );
                          return;
                        }
                        GameManager.roundCenter = widget.playAreaCenter;
                        GameManager.roundRadius = widget.playareaRadius;
                        client?.publishRoundStart(
                          center: [
                            widget.playAreaCenter.latitude,
                            widget.playAreaCenter.longitude,
                          ],
                          radiusM: widget.playareaRadius,
                          durationSec: _durationMin * 60,
                          hiders: _hiderSel.toList(),
                          items:
                              _markerPositions
                                  .map(
                                    (p) => {
                                      'type': 'item',
                                      'lat': p.latitude,
                                      'lng': p.longitude,
                                    },
                                  )
                                  .toList(),
                        );

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => MapScreen(
                                  players: const [],
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
