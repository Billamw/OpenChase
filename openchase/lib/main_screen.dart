import 'package:flutter/material.dart';
import 'package:openchase/create_room_screen.dart';
import 'package:openchase/map.dart'; // Importiere die Map-Seite

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final String logoPath =
        brightness == Brightness.light
            ? 'images/logo_light_1024.png'
            : 'images/logo_dark_1024.png';

    return Scaffold(
      body: Column(
        children: [
          // Logo at the top
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Image.asset(logoPath, width: 200),
          ),
          // Create Room, Join Room, and Map buttons
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateRoomScreen(),
                        ),
                      );
                    },
                    child: const Text('Create Room'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle join room button press
                    },
                    child: const Text('Join Room'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(),
                        ),
                      );
                    },
                    child: const Text('Map'),
                  ),
                ),
              ],
            ),
          ),

          // Settings icon at the bottom
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: IconButton(
                iconSize: 32,
                onPressed: () {
                  // Handle settings button press
                },
                icon: const Icon(Icons.settings),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
