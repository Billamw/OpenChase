import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class ItemsTest extends StatefulWidget {
  @override
  _ItemsTestState createState() => _ItemsTestState();
}

class _ItemsTestState extends State<ItemsTest> {
  final MapController _mapController = MapController();
  List<LatLng> _markerPositions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchWaysAndGenerateMarkers();
  }

  // Overpass API: Wege im Umkreis holen
  Future<void> _fetchWaysAndGenerateMarkers() async {
    double lat = 50.9375; // Beispiel: Köln
    double lng = 6.9603; // Beispiel: Köln
    double radius = 1000; // 1000 Meter Umkreis
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

    while (selectedMarkers.length < 15) {
      // 15 zufällige Marker
      int index = random.nextInt(wayPoints.length);
      selectedMarkers.add(wayPoints[index]);
    }

    setState(() {
      _markerPositions = selectedMarkers.toList();
      _isLoading = false; // Ladeanzeige abschalten
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karte mit zufälligen Markern')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator()) // Ladeanzeige während des Abrufs
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(50.9375, 6.9603), // Koordinaten für Köln
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                MarkerLayer(
                  markers: _markerPositions.map((pos) {
                    return Marker(
                      point: pos,
                      width: 100,
                      height: 90,
                      rotate: true,
                      alignment: Alignment.topCenter,
                      // Zufällige Farbe
                      child: Icon(
                        Icons.place,
                        color: Colors.primaries[Random().nextInt(Colors.primaries.length)],
                        size: 100,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}
