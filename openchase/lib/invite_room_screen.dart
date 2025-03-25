import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openchase/utils/inistial_nostr.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/utils/continuous_nostr.dart';

class InviteRoomScreen extends StatefulWidget {
  final String playerName;

  const InviteRoomScreen({super.key, required this.playerName});

  @override
  State<InviteRoomScreen> createState() => _InviteRoomScreenState();
}

class _InviteRoomScreenState extends State<InviteRoomScreen> {
  String _generatedCode = '';
  late ContinuousNostr _nostrListener;
  // ignore: prefer_final_fields
  List<Map<String, dynamic>> _receivedMessages = [];

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
    NostrHelper.sendInitialNostr(widget.playerName, _generatedCode);

    // ✅ Initialize ContinuousNostr and listen for messages
    _nostrListener = ContinuousNostr(
      onMessageReceived: (message) {
        setState(() {
          _receivedMessages.insert(0, message);
        });
      },
    );

    _nostrListener.connect(); // Start WebSocket connection
  }

  @override
  void dispose() {
    _nostrListener.close(); // ✅ Close WebSocket when screen is closed
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
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _generatedCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Code copied to clipboard!")),
                );
              },
              child: Container(
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
                  return ListTile(
                    title: Text(_receivedMessages[index]["name"]),
                  );
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
                        content: Text('TODO Implement the room creation logic'),
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
