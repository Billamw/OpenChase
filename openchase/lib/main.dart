import 'package:flutter/material.dart';
import 'package:openchase/main_screen.dart';
import 'package:openchase/utils/sim_location.dart';

void main() {
  SimLocation.init();
  runApp(const OpenChaseApp());
}

class OpenChaseApp extends StatelessWidget {
  const OpenChaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Chase',
      theme: ThemeData(
        // Your theme configuration
      ),
      home: MainScreen(),
    );
  }
}
