import 'package:flutter/material.dart';
import 'package:openchase/join_room_screen.dart';
import 'package:openchase/setup_room_screen.dart';
import 'package:openchase/nostr_test_page.dart';
import 'package:openchase/map.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/utils/player.dart';
import 'package:latlong2/latlong.dart';
import 'package:openchase/wege.dart';

class MainScreen extends StatelessWidget {
  MainScreen({super.key});

  // Für Testzwecke:
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
  Widget build(BuildContext context) {
    final String logoPath = UiHelper.getLogoPath(context);

    return Scaffold(
      body: Column(
        children: [
          // Logo oben
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Image.asset(logoPath, width: 200),
          ),
          // Buttons: Create Room, Join Room, Map
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
                          builder: (context) => SetupRoomScreen(),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => JoinRoomScreen(),
                        ),
                      );
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
                          builder: (context) => MapScreen(players: players),
                        ),
                      );
                    },
                    child: const Text('Map'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ItemsTest()),
                      );
                    },
                    child: const Text('Items-Test'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WebSocketMessagesPage(),
                        ),
                      );
                    },
                    child: const Text('Nostr Test'),
                  ),
                ),
              ],
            ),
          ),
          // Settings-Symbol unten rechts
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: IconButton(
                iconSize: 32,
                onPressed: () {
                  // Settings-Button-Press-Logik
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
