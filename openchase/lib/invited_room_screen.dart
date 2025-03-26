import 'dart:math';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openchase/utils/inistial_nostr.dart';
import 'package:openchase/utils/nostr_settings.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/utils/continuous_nostr.dart';

class InvitedRoomScreen extends StatefulWidget {
  final String playerName;
  final String code;

  const InvitedRoomScreen({
    super.key,
    required this.playerName,
    required this.code,
  });

  @override
  State<InvitedRoomScreen> createState() => _InvitedRoomScreenState();
}

class _InvitedRoomScreenState extends State<InvitedRoomScreen> {
  late ContinuousNostr _nostrListener;
  // ignore: prefer_final_fields
  List<Map<String, dynamic>> _receivedMessages = [];

  @override
  void initState() {
    dev.log(
      "test nostrData ${NostrSettings.roomCode} host: ${NostrSettings.roomHost}",
    );
    super.initState();
    _receivedMessages.add({"name": widget.playerName});

    // ✅ Initialize ContinuousNostr and listen for messages
    _nostrListener = ContinuousNostr(
      onMessageReceived: (message) {
        setState(() {
          _receivedMessages.add(message);
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
                Clipboard.setData(ClipboardData(text: widget.code));
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
                    widget.code,
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
