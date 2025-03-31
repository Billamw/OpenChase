import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openchase/setup_playArea_map.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/nostr/player_room_nostr.dart';
import 'package:openchase/utils/ui_helper.dart';

class PlayerInvitateScreen extends StatefulWidget {
  const PlayerInvitateScreen({super.key});

  @override
  State<PlayerInvitateScreen> createState() => _PlayerInvitateScreenState();
}

class _PlayerInvitateScreenState extends State<PlayerInvitateScreen> {
  late PlayerRoomNostr _roomNostr;
  // ignore: prefer_final_fields
  List _players = [GameManager.roomHost];

  @override
  void initState() {
    super.initState();
    // GameManager.players.add(GameManager.userName);

    // ✅ Initialize ContinuousNostr and listen for messages
    _roomNostr = PlayerRoomNostr(
      onMessageReceived: (message) {
        if (message.containsKey("joined")) {
          GameManager.players.add(message["joined"]);
          setState(() {
            _players = GameManager.players;
          });
        }
        if (message.containsKey("left")) {
          GameManager.players.remove(message["left"]);
          dev.log(
            "Player left: ${message["left"]}",
            name: "log.Test.PlayerLeft.listened",
          );
          setState(() {
            _players = GameManager.players;
          });
        }
        if (message.containsKey("gamePrivateKey")) {
          GameManager.gamePublicKey = message["gamePublicKey"];
          GameManager.gamePrivateKey = message["gamePrivateKey"];
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
    GameManager.removeAllData();
    _roomNostr.close(); // ✅ Close WebSocket when screen is closed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevents direct back navigation
      onPopInvokedWithResult: (didPop, Object? content) async {
        if (didPop) return;

        await showDialog(
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
                      _roomNostr.leaveGameNostr();
                      GameManager.removeAllData(); // Cleanup before leaving
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
                  Clipboard.setData(ClipboardData(text: GameManager.roomCode));
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
                      GameManager.roomCode,
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
