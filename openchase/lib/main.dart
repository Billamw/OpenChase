import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const OpenChaseApp());
}

class OpenChaseApp extends StatelessWidget {
  const OpenChaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenChase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const OpenChaseMainScreen(),
    );
  }
}

class OpenChaseMainScreen extends StatelessWidget {
  const OpenChaseMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final String logoPath =
        brightness == Brightness.light
            ? 'images/Logo_light_1024.png'
            : 'images/Logo_dark_1024.png';

    return Scaffold(
      body: Column(
        children: [
          // Logo at the top
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Image.asset(logoPath, width: 200),
          ),
          // Create Room and Join Room buttons
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle create room button press
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
              ],
            ),
          ),

          // Settings icon at the bottom
          Align(
            alignment: Alignment.bottomCenter,
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
