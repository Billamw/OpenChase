import 'dart:math';
import 'package:flutter/material.dart';
// import 'package:openchase/utils/deeplink.dart';
import 'package:url_launcher/url_launcher.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _CreateRoomScreenState createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  String _generatedCode = '';

  // Generate a random 4-letter code (A-Z)
  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _generatedCode =
        List.generate(4, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    // Generate code when the screen is opened
    _generateRandomCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          double padding =
              constraints.maxWidth > 600 ? 100 : 16; // Adjust based on width

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Column(
              children: [
                // Display the generated code
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      _generatedCode,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 163, 73, 164),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Invite link display
                SelectableText(
                  "openchase://invite?roomId=$_generatedCode&password=${1234}",
                  style: TextStyle(fontSize: 16, color: Colors.blue),
                  textAlign: TextAlign.center,
                  onTap: () async {
                    final Uri uri = Uri.parse(
                      "openchase://invite?roomId=$_generatedCode&password=${1234}",
                    );

                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not launch invite link'),
                        ),
                      );
                    }
                  },
                ),

                const SizedBox(height: 20),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    ElevatedButton(
                      child: const Text('Start'),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Room created! Code: $_generatedCode',
                            ),
                          ),
                        );

                        Navigator.pop(context);

                        //TODO: navigate to the room screen and open webrtc connection
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
