import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/map.dart';
import 'package:openchase/utils/player.dart';
import 'package:openchase/utils/circle_generator.dart';

class ItemsTest extends StatefulWidget {
  final LatLng playAreaCenter;
  final int playareaRadius;
  final int itemCount;

  

  ItemsTest({required this.playAreaCenter, required this.playareaRadius, this.itemCount = 6});
  @override
  _ItemsTestState createState() => _ItemsTestState();
}

class _ItemsTestState extends State<ItemsTest> {
  final MapController _mapController = MapController();
  List<LatLng> _markerPositions = [];
  bool _isLoading = true;
  List<Player> players = [
    Player(
      name: "Mr. X",
      isMrX: true,
      color: Colors.black,
      positionHistory: [],
      currentPosition: LatLng(48.1351, 11.5820),
    ),
    Player(
      name: "Detektiv 1",
      isMrX: false,
      color: Colors.blue,
      positionHistory: [],
      currentPosition: LatLng(48.1361, 11.5830),
    ),
    Player(
      name: "Detektiv 2",
      isMrX: false,
      color: Colors.green,
      positionHistory: [],
      currentPosition: LatLng(48.1371, 11.5840),
    ),
    Player(
      name: "Detektiv 3",
      isMrX: false,
      color: Colors.orange,
      positionHistory: [],
      currentPosition: LatLng(48.1381, 11.5850),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchWaysAndGenerateMarkers();
  }

  // Overpass API: Wege im Umkreis holen
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

  // OSM-Daten parsen
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



  // Zufällige Marker auf Wegen platzieren
  void _generateRandomMarkers(List<LatLng> wayPoints) {
  if (wayPoints.isEmpty) return;

  Random random = Random();
  Set<LatLng> selectedMarkers = {};
  final Distance distance = Distance();

  while (selectedMarkers.length < 6) {
    int index = random.nextInt(wayPoints.length);
    LatLng candidate = wayPoints[index];

    // Berechne die Entfernung vom Zentrum des Spielbereichs
    double distanceToCenter = distance(
      widget.playAreaCenter,
      candidate,
    );

    if (distanceToCenter <= widget.playareaRadius) {
      print(distanceToCenter);
      selectedMarkers.add(candidate);
    }
  }

  setState(() {
    _markerPositions = selectedMarkers.toList();
    _isLoading = false;
  });
}



 @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text('Items Setup')),
    body: _isLoading
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,  // Vertikal zentrieren
              crossAxisAlignment: CrossAxisAlignment.center, // Horizontal zentrieren
              mainAxisSize: MainAxisSize.min, // Nur so groß wie nötig
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16), // Abstand zwischen Indikator und Text
                Text("Placing items..."),
              ],
            ),
          )
        : Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.playAreaCenter, // Koordinaten für Köln
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      tileProvider: CancellableNetworkTileProvider(),
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: CircleGenerator.generateCircle(widget.playAreaCenter, widget.playareaRadius.toDouble()), // Circle as Polyline
                          strokeWidth: 8.0,
                          color: Colors.red, // Randfarbe
                        ),
                      ],
                    ),
MarkerLayer(
  markers: _markerPositions.map((pos) {
    return Marker(
      point: pos,  // Ursprüngliche Marker-Position
      width: 60,
      height: 60,
      rotate: true,
      alignment: Alignment.center,
      child: Draggable(
        feedback: Image.asset(
          'images/test-item.png',
          width: 60,
          height: 60,
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: Image.asset(
            'images/test-item.png',
            width: 60,
            height: 60,
          ),
        ),
        onDragEnd: (dragDetails) { // Ja ich weiß, hier stimmt etwas noch nicht. Das item wird immer um einen festen Pixelwert nach unten links verschoben
          setState(() {
            // Errechne den Offset in Bezug auf die Karte
            final Offset screenOffset = dragDetails.offset;

            // Berechne die LatLng-Position aus den Bildschirmkoordinaten
            LatLng newLatLng = _mapController.camera.screenOffsetToLatLng(
              screenOffset,
            );

            // Berechne die relative Verschiebung
            LatLng currentPosition = pos;
            double deltaLat = newLatLng.latitude - currentPosition.latitude;
            double deltaLng = newLatLng.longitude - currentPosition.longitude;

            // Berechne die endgültige neue Position
            LatLng finalPosition = LatLng(
              currentPosition.latitude + deltaLat,
              currentPosition.longitude + deltaLng,
            );

            // Finde den Index des Markers und aktualisiere seine Position
            int index = _markerPositions.indexOf(pos);
            if (index != -1) {
              _markerPositions[index] = finalPosition;
              print("Neue Position: ${_markerPositions[index]}"); // Debugging
            }
          });
        },
        child: Image.asset(
          'images/test-item.png',
          width: 60,
          height: 60,
        ),
      ),
    );
  }).toList(),
),




                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
  setState(() {
    _isLoading = true;
  });
  _fetchWaysAndGenerateMarkers();
},
                  child: Text("Randomize item positions"),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapScreen(players: players, playAreaCenter: widget.playAreaCenter, playareaRadius: widget.playareaRadius),
                      ),
                    );
                  },
                  child: Text("Ready"),
                ),
              ),
            ],
          ),
  );
}}
