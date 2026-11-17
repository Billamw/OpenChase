import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:openchase/map.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/protocol/room_client.dart';
import 'package:openchase/utils/ui_helper.dart';

class PlayerInvitateScreen extends StatefulWidget {
  const PlayerInvitateScreen({super.key});

  @override
  State<PlayerInvitateScreen> createState() => _PlayerInvitateScreenState();
}

class _PlayerInvitateScreenState extends State<PlayerInvitateScreen> {
  List<String> _players = [];

  RoomClient? get _client => GameManager.roomClient;

  @override
  void initState() {
    super.initState();
    final client = _client;
    if (client == null) return;
    _players = List.of(client.playerNames);
    client.onRosterChanged = () {
      if (!mounted) return;
      setState(() {
        _players = List.of(client.playerNames);
      });
    };
    client.onRoundStart = (round) {
      dev.log(
        "Round started: center=${round.centerLat},${round.centerLng} r=${round.radiusM}",
        name: "log.PlayerInvited.roundStart",
      );
      if (!mounted) return;
      GameManager.roundCenter = LatLng(round.centerLat, round.centerLng);
      GameManager.roundRadius = round.radiusM;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => MapScreen(
                players: const [],
                playAreaCenter: GameManager.roundCenter!,
                playareaRadius: GameManager.roundRadius,
              ),
        ),
      );
    };
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
                      _client?.sendLeave();
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
        appBar: AppBar(title: const Text('Room')),
        body: Padding(
          padding: UiHelper.getResponsivePadding(context),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: GameManager.roomCode),
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

              Expanded(
                child: ListView.builder(
                  itemCount: _players.length,
                  itemBuilder: (context, index) {
                    return ListTile(title: Text(_players[index]));
                  },
                ),
              ),

              Text(
                _client != null && _client!.readyRelays > 0
                    ? 'Waiting for host to start the round…'
                    : 'Connecting…',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
