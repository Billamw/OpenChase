import 'dart:math';
import 'package:flutter/material.dart';
import 'package:openchase/utils/ui_helper.dart';

class InviteRoomScreen extends StatefulWidget {
  final String playerName;
  final int uncoverInterval;
  final List<bool> settings;

  const InviteRoomScreen({
    super.key,
    required this.playerName,
    required this.uncoverInterval,
    required this.settings,
  });

  @override
  State<InviteRoomScreen> createState() => _InviteRoomScreenState();
}

class _InviteRoomScreenState extends State<InviteRoomScreen> {
  String _generatedCode = '';

  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _generatedCode =
        List.generate(4, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _generateRandomCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Room Created')),
      body: Padding(
        padding: UiHelper.getResponsivePadding(context),
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

            // Player name
            Text(
              "Player: ${widget.playerName}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Invite link display
            SelectableText(
              "Now invite your friends!",
              style: const TextStyle(fontSize: 16, color: Colors.blue),
              textAlign: TextAlign.center,
            ),

            const Spacer(),

            // Start Button
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
                        content: Text('Room created! Code: $_generatedCode'),
                      ),
                    );

                    // TODO: Implement the room creation logic
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
