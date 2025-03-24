import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late MapController _mapController;
  late AnimationController _animationController;
  late Animation<LatLng> _animation;
  LatLng _currentPosition = LatLng(48.1351, 11.5820); // Standard: München
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2), // Dauer der Animation
    );

    // Prüfen, ob die Plattform iOS oder Android ist
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      _getCurrentLocation();
    } else {
      // Wenn nicht iOS oder Android, setze den Standort manuell
      setState(() {
        _currentPosition = LatLng(51.1657, 10.4515); // Beispiel: Deutschland
        _loading = false;
      });
      // Wenn der Standort manuell gesetzt ist, animiere die Karte
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animatedMapMove(_currentPosition, 15.0);
      });
    }
  }

  // Methode, um den aktuellen Standort zu erhalten
  Future<void> _getCurrentLocation() async {
  if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
    // Für mobile Plattformen (Android/iOS)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Standortdienste sind deaktiviert. Bitte aktivieren Sie sie in den Einstellungen.'),
      ));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Standortberechtigung wurde dauerhaft abgelehnt.'),
        ));
        return;
      }
    }

    // Hole den aktuellen Standort
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _loading = false;
    });

    // Erstelle eine Animation für den Wechsel zur neuen Position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animatedMapMove(_currentPosition, 15.0);
    });
  } else {
    // Für nicht-mobiele Plattformen (z.B. Web, Desktop)
    // Setze manuell einen Standort
    setState(() {
      _currentPosition = LatLng(51.1657, 10.4515); // Beispiel: Deutschland
      _loading = false;
    });

    // Erstelle eine Animation für den Wechsel zur neuen Position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animatedMapMove(_currentPosition, 15.0);
    });
  }
}


  // Animierte Bewegung der Karte
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
        begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Karte mit Standort'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition, // Position der Karte
              initialZoom: 14, // Zoom-Stufe
              maxZoom: 19.6, // Maximaler Zoom
              minZoom: 4.0, // Minimaler Zoom
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                //urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 100,
                    height: 100,
                    child: Image.asset('images/mrx.png', width: 100, height: 100),
                  ),
                ],
              ),
            ],
          ),
          if (_loading)
            Center(child: CircularProgressIndicator()), // Lade-Indikator
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (!_loading) {
            _getCurrentLocation();
          }
        },
        child: Icon(Icons.my_location),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
