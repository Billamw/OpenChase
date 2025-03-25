import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/wege.dart';


void main() {
  runApp(SetupMapScreen());
}

class SetupMapScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SetupPage(),
    );
  }
}

class SetupPage extends StatefulWidget {
  @override
  _SetupPageState createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late MapController mapController;
  LatLng? currentLocation;
  LatLng circleLocation = LatLng(51.5, -0.09); // Initial position of the circle
  double radius = 100.0; // Initial radius (100m)
  bool isLocationSet = false;
  double currentZoom = 13.0; // Initial zoom level

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _getCurrentLocation();
  }

  // Method to get the current location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // If location services are not enabled
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return; // Location access denied
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      currentLocation = LatLng(position.latitude, position.longitude);
      isLocationSet = true;
      // Move map to the user's current location
      mapController.move(currentLocation!, currentZoom);
    });
  }

  // Method to update the radius
  void _onRadiusChanged(double value) {
    setState(() {
      radius = value;
    });
  }

  // Method to handle tapping on the map
  void _onMapTap(LatLng tappedLocation) {
    setState(() {
      circleLocation = tappedLocation;
    });
  }

  // Method to handle dragging of the circle
  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      double dx = details.localPosition.dx;
      double dy = details.localPosition.dy;
      
      // Adjust the map position here (for demonstration purposes, we are not converting to LatLng yet)
      // Ideally, you would need a conversion from screen pixel movements to map coordinates
      // In this example, we are directly updating the circle's location
      circleLocation = LatLng(circleLocation.latitude + dy / 100000, circleLocation.longitude + dx / 100000);
      mapController.move(circleLocation, currentZoom); // Move the map view as well
    });
  }

  // Method to generate a polygon that represents a circle with the given radius
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Setup Page")),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: currentLocation ?? LatLng(51.5, -0.09), // Startcenter
                initialZoom: currentZoom, // Initial zoom level
                onTap: (tapPosition, latLng) {
                  _onMapTap(latLng); // Update circle position
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                if (isLocationSet && currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: circleLocation,
                        width: 40,
                        height: 40,
                        // Use a GestureDetector for dragging the marker
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            _onPanUpdate(details);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withOpacity(0.5),
                              border: Border.all(
                                color: Colors.blue,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (isLocationSet && currentLocation != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _generateCircle(circleLocation, radius), // Generate circle as a polygon
                        color: Colors.blue.withOpacity(0.5),
                        borderColor: Colors.blue,
                        borderStrokeWidth: 2.0,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (isLocationSet)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text("Radius: ${radius.toInt()} meters"),
                  Slider(
                    value: radius,
                    min: 100.0,
                    max: 5000.0,
                    divisions: 49,
                    label: "${radius.toInt()} meters",
                    onChanged: _onRadiusChanged,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () {
                // Logic to navigate to the next page goes here
                print("Ready button pressed, next page logic goes here");
                                     Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ItemsTest(playAreaCenter: circleLocation, playareaRadius: radius.toInt(),)
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
