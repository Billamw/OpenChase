import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:openchase/wege.dart';

class SetupPage extends StatefulWidget {
  @override
  _SetupPageState createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late MapController mapController;
  LatLng? currentLocation;
  LatLng circleLocation = LatLng(51.5, -0.09); // Initial position of the circle
  double radius = 500.0; // Initial radius (100m)
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

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return; // Location access denied
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      currentLocation = LatLng(position.latitude, position.longitude);
      isLocationSet = true;
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
      circleLocation = LatLng(
        circleLocation.latitude + dy / 100000,
        circleLocation.longitude + dx / 100000,
      );
      mapController.move(
        circleLocation,
        currentZoom,
      ); // Move the map view as well
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
      double newLon =
          lon + (radiusInDegrees * sin(angleRad) / cos(lat * pi / 180.0));

      circlePoints.add(LatLng(newLat, newLon));
    }

    return circlePoints;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Setup Page")),
      body:
          !isLocationSet
              ? Center(
                child: Text("Sending location data to NSA..."),
              ) // Meldung während der Standortsuche
              : Column(
                children: [
                  Expanded(
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter:
                            currentLocation ??
                            LatLng(51.5, -0.09), // Startcenter
                        initialZoom: currentZoom, // Initial zoom level
                        onTap: (tapPosition, latLng) {
                          _onMapTap(latLng); // Update circle position
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                          tileProvider: CancellableNetworkTileProvider(),
                        ),
                        if (isLocationSet && currentLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: circleLocation,
                                width: 40,
                                height: 40,
                                rotate: true,
                                //alignment: Alignment(0,-0.8),
                                // Use a GestureDetector for dragging the marker
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    _onPanUpdate(details);
                                  },
                                  child: Icon(
                                    Icons.location_searching,
                                    color: Colors.red,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (isLocationSet && currentLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: currentLocation!,
                                width: 40,
                                height: 40,
                                rotate: true,
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.lightBlue,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        if (isLocationSet && currentLocation != null)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _generateCircle(
                                  circleLocation,
                                  radius,
                                ), // Generate circle as a polygon
                                color: Colors.red.withOpacity(0.5),
                                borderColor: Colors.red,
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
                          Text(
                            "Tap on the map to set the center of the play area",
                          ),
                          Text("Radius: ${radius.toInt()} meters"),
                          Slider(
                            value: radius,
                            min: 200.0,
                            max: 5000.0,
                            divisions: 48,
                            label: "${radius.toInt()} meters",
                            onChanged: _onRadiusChanged,
                          ),
                        ],
                      ),
                    ),
                  if (isLocationSet && currentLocation != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ItemsTest(
                                    playAreaCenter: circleLocation,
                                    playareaRadius: radius.toInt(),
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
