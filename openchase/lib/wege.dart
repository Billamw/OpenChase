import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class ItemsTest extends StatefulWidget {
  final LatLng playAreaCenter;
  final int playareaRadius;

  ItemsTest({required this.playAreaCenter, required this.playareaRadius});
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
    double lat = widget.playAreaCenter.latitude;
    double lng = widget.playAreaCenter.longitude;
    double radius = 0.9 * widget.playareaRadius; // 1000 Meter Umkreis
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

    return circlePoints;
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
                      points: _generateCircle(widget.playAreaCenter, widget.playareaRadius.toDouble()), // Circle as Polyline
                      strokeWidth: 8.0,
                      color: Colors.red, // Randfarbe
                    ),
                  ],
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
