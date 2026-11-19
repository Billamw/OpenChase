import 'package:flutter/material.dart';
import 'package:openchase/main_screen.dart';
import 'package:openchase/theme.dart';
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
      debugShowCheckedModeBanner: false,
      theme: ocTheme(),
      darkTheme: ocTheme(),
      themeMode: ThemeMode.dark,
      home: MainScreen(),
      // Desktop web: cap the app column and let the slate background
      // breathe on both sides; phones are below the cap anyway.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return ColoredBox(
          color: OcColors.bg,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1024),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
