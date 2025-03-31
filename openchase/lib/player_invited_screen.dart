import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openchase/setup_playArea_map.dart';
import 'package:openchase/utils/nostr_settings.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/utils/nostr/room_nostr.dart';

class PlayerInvitateScreen extends StatefulWidget {
  const PlayerInvitateScreen({super.key});

  @override
  State<PlayerInvitateScreen> createState() => _PlayerInvitateScreenState();
}

class _PlayerInvitateScreenState extends State<PlayerInvitateScreen> {
  late RoomNostr _nostrListener;
  // ignore: prefer_final_fields
  List _players = [NostrSettings.roomHost];

  @override
  void initState() {
    super.initState();
    // NostrSettings.players.add(NostrSettings.userName);

    // ✅ Initialize ContinuousNostr and listen for messages
    _nostrListener = RoomNostr(
      onMessageReceived: (message) {
        if (message.containsKey("name")) {
          setState(() {
            _players = NostrSettings.players;
          });
        }
        if (message.containsKey("gamePrivateKey")) {
          NostrSettings.gamePublicKey = message["gamePublicKey"];
          NostrSettings.gamePrivateKey = message["gamePrivateKey"];
          dev.log("Game started", name: "log.Test.StartGame.listened");
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SetupPage()),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    NostrSettings.removeAllData();
    _nostrListener.close(); // ✅ Close WebSocket when screen is closed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevents direct back navigation
      onPopInvokedWithResult: (didPop, Object? content) async {
        if (didPop) return;

        bool shouldLeave = await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text("Leave Room?"),
                content: const Text(
                  "Are you sure you want to leave the room and return to the main screen?",
                ),
                actions: [
                  TextButton(
                    onPressed:
                        () => Navigator.of(
                          context,
                        ).pop(false), // Stay on the screen
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () {
                      NostrSettings.removeAllData(); // Cleanup before leaving
                      Navigator.of(context).pop(true); // Close dialog
                      Navigator.of(
                        context,
                      ).pop(); // Navigate (join screen pop up)
                      Navigator.of(context).pop(); // Navigate (join screen)
                      Navigator.of(context).pop(); // Navigate (main screen)
                    },
                    child: const Text("Leave"),
                  ),
                ],
              ),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Room Created')),
        body: Padding(
          padding: UiHelper.getResponsivePadding(context),
          child: Column(
            children: [
              // Display the generated code
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: NostrSettings.roomCode),
                  );
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
                      NostrSettings.roomCode,
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
                  itemCount: _players.length,
                  itemBuilder: (context, index) {
                    return ListTile(title: Text(_players[index]));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
