// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:openchase/player_invited_screen.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/protocol/room_client.dart';
import 'package:openchase/utils/protocol/room_keys.dart';
import 'package:openchase/utils/ui_helper.dart';

class PlayerJoinScreen extends StatefulWidget {
  const PlayerJoinScreen({super.key});

  @override
  State<PlayerJoinScreen> createState() => _PlayerJoinScreenState();
}

class _PlayerJoinScreenState extends State<PlayerJoinScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  String? _codeError;

  void _clearErrors() {
    setState(() {
      _codeError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _codeFocus.requestFocus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _joinRoom(BuildContext context) async {
    _clearErrors();

    final name = GameManager.userName;
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      Navigator.pop(context); // back to name entry on the main screen
      return;
    }
    if (code.length != 5) {
      setState(() => _codeError = "Room code is 5 letters");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Checking room..."),
            ],
          ),
        );
      },
    );

    final client = RoomClient(
      host: false,
      roomKeys: RoomKeys.fromCode(code),
      playerName: name,
      onRosterChanged: () {},
    );
    final hostName = await client.findRoom(const Duration(seconds: 4));

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    if (hostName == null) {
      client.close();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Room not found")));
      return;
    }

    GameManager.roomClient = client;
    GameManager.roomCode = code;
    GameManager.roomHost = hostName;
    GameManager.userName = name;
    await _showJoinConfirmationDialog(context, code, name);
  }

  Future<bool?> _showJoinConfirmationDialog(
    BuildContext context,
    String code,
    String name,
  ) async {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("Join $code?"),
            content: Text(
              "Are you sure you want to join ${GameManager.roomHost}'s room?",
            ),
            actions: [
              TextButton(
                child: Text("Cancel"),
                onPressed: () {
                  Navigator.pop(context);
                  GameManager.roomClient?.close();
                  GameManager.roomClient = null;
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(foregroundColor: Colors.green),
                child: Text("Join"),
                onPressed: () {
                  GameManager.roomClient?.sendJoin(name);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerInvitateScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Join Room")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(UiHelper.getLogoPath(context), height: 80),
            SizedBox(height: 32),

            Text(
              "Joining as ${GameManager.userName}",
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            SizedBox(height: 16),

            TextField(
              maxLength: 5,
              controller: _codeController,
              textInputAction: TextInputAction.done,
              focusNode: _codeFocus,
              onSubmitted: (_) => _joinRoom(context),
              decoration: InputDecoration(
                labelText: "Room Code",
                hintText: "XXXXX",
                errorText: _codeError,
                counterText: '',
              ),
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
              style: TextStyle(
                fontSize: 28,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              onChanged: (text) {
                setState(() {});
                // Enforce uppercase
                if (text != text.toUpperCase()) {
                  _codeController.value = TextEditingValue(
                    text: text.toUpperCase(),
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                }
              },
            ),
            SizedBox(height: 48),

            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: Size(180, 52)),
                onPressed: () => _joinRoom(context),
                child: Text("JOIN ROOM"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
