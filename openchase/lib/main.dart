import 'package:flutter/material.dart';
import 'package:openchase/main_screen.dart';

void main() {
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
      home: const MainScreen(),
    );
  }
}
