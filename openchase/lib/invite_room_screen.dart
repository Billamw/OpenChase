import 'dart:math';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:openchase/utils/nostr_helper.dart';
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
  // ignore: prefer_final_fields
  List<String> _receivedMessages = [];

  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _generatedCode =
        List.generate(4, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _generateRandomCode();
    NostrHelper.connect(); // ✅ Open WebSocket when screen loads
    NostrHelper.sendInitialNostr(
      widget.playerName,
      _generatedCode,
    ); // ✅ Send room creation event
    listen(); // ✅ Listen for incoming messages
  }

  Future<void> listen() async {
    await NostrHelper.listenForMessages((message) {
      dev.log("(listen)ceived message: $message");
      setState(() {
        _receivedMessages.add(message); // Add new message to list
      });
    });
  }

  @override
  void dispose() {
    NostrHelper.closeWebSocket(); // ✅ Close WebSocket when screen is closed
    super.dispose();
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

            // ✅ Display received messages
            Expanded(
              child: ListView.builder(
                itemCount: _receivedMessages.length,
                itemBuilder: (context, index) {
                  return ListTile(title: Text(_receivedMessages[index]));
                },
              ),
            ),

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
