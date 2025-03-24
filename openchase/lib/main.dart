import 'package:flutter/material.dart';
import 'package:openchase/main_screen.dart';
// import 'package:openchase/utils/deeplink.dart';
import 'package:uni_links/uni_links.dart';
// import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenChaseApp());
}

class OpenChaseApp extends StatefulWidget {
  const OpenChaseApp({super.key});

  @override
  State<OpenChaseApp> createState() => _OpenChaseAppState();
}

class _OpenChaseAppState extends State<OpenChaseApp> {
  @override
  void initState() {
    super.initState();
    _initDeepLinks(); // ✅ Now safe to initialize deep links
  }

  Future<void> _initDeepLinks() async {
    try {
      String? initialLink =
          await getInitialLink(); // ✅ Wait for plugin to be available
      if (initialLink != null) {
        _handleUri(Uri.parse(initialLink));
      }

      uriLinkStream.listen((Uri? uri) {
        if (uri != null) {
          _handleUri(uri);
        }
      });
    } catch (e) {
      print("Deep link error: $e");
    }
  }

  void _handleUri(Uri uri) {
    String? roomId = uri.queryParameters['roomId'];
    String? password = uri.queryParameters['password'];

    if (roomId != null && password != null) {
      print("Joining Room: $roomId with Password: $password");
      // Navigate to the correct screen
    }
  }

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
