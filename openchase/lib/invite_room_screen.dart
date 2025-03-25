import 'dart:math';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';
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
  late WebSocketChannel _channel;
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
    _connectWebSocket(); // ✅ Establish WebSocket connection
    listen(); // ✅ Start listening for messages
  }

  void _connectWebSocket() {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [OpenChaseKey.public],
        since: currentUnixTimestampSeconds() - 5 * 60,
      ),
    ]);

    _channel = WebSocketChannel.connect(Uri.parse(OpenChaseKey.nostrRelay));
    _channel.sink.add(requestWithFilter.serialize());
  }

  Future<void> listen() async {
    _channel.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);
        dev.log("(listen) Received message: $decodedMessage");

        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // Extract event object
          String content = eventData["content"];
          Map<String, dynamic> jsonData = json.decode(content);
          if (content.contains("name")) {
            setState(() {
              _receivedMessages.insert(
                0,
                jsonData,
              ); // Add new message to the list
            });
          }
        }
      } catch (e) {
        dev.log("⚠️ Error decoding message: $e");
      }
    });
  }

  @override
  void dispose() {
    _channel.sink.close(); // ✅ Close WebSocket when screen is closed
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
