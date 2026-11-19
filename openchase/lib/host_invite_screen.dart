import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/setup_playArea_map.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/protocol/room_client.dart';
import 'package:openchase/utils/protocol/room_keys.dart';

class HostInviteScreen extends StatefulWidget {
  final String playerName;

  /// Reload-resume: reuse the previous room code and player session key so
  /// this device rejoins its own room as the same identity instead of hosting
  /// a fresh one.
  final String? resumeCode;
  final String? resumePriv;

  const HostInviteScreen({
    super.key,
    required this.playerName,
    this.resumeCode,
    this.resumePriv,
  });

  @override
  State<HostInviteScreen> createState() => _HostInviteScreenState();
}

class _HostInviteScreenState extends State<HostInviteScreen> {
  String _generatedCode = '';
  RoomClient? _client;
  List _players = [];
  int _readyRelays = 0;
  bool _collision = false;

  RoomClient _createClient(String code) {
    late final RoomClient client;
    client = RoomClient(
      host: true,
      roomKeys: RoomKeys.fromCode(code),
      playerName: widget.playerName,
      playerKeychain: widget.resumePriv == null
          ? null
          : Keychain(widget.resumePriv!),
      onRosterChanged: () {
        if (!mounted) return;
        setState(() {
          _players = List.of(client.playerNames);
        });
      },
    );
    return client;
  }

  Future<void> _ensureFreeCode() async {
    // Room identity is derived from the code, so an already-live room with the
    // same code means a collision: it will echo room events back to us.
    _generatedCode = RoomKeys.randomRoomCode();
    _collision = false;
    _client = _createClient(_generatedCode);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    if (_client!.readyRelays == 0) {
      _collision = true; // no relay reachable — cannot safely claim a room
      return;
    }
    _client!.publishRoomInit();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    // Another room keypair speaking on this identity = code already live.
    if (_client!.sawForeignRoomTraffic) {
      _collision = true;
    }
  }

  @override
  void initState() {
    super.initState();
    GameManager.userName = widget.playerName;
    unawaited(_start());
  }

  Future<void> _start() async {
    if (widget.resumeCode != null) {
      // Resume our own room: fixed code + fixed session key, no collision
      // hunt (our own pre-reload traffic would look like a collision).
      _generatedCode = widget.resumeCode!;
      _client = _createClient(_generatedCode);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      _client!.publishRoomInit();
      GameManager.roomClient = _client;
      GameManager.roomCode = _generatedCode;
      GameManager.roomHost = widget.playerName;
      setState(() {
        _players = List.of(_client!.playerNames);
        _readyRelays = _client!.readyRelays;
      });
      return;
    }
    await _ensureFreeCode();
    if (!mounted) return;
    if (_collision) {
      // Retry with a fresh code while disconnected states persist.
      _client?.close();
      await _start();
      return;
    }
    GameManager.roomClient = _client;
    GameManager.roomCode = _generatedCode;
    GameManager.roomHost = widget.playerName;
    setState(() {
      _players = List.of(_client!.playerNames);
      _readyRelays = _client!.readyRelays;
    });
  }

  @override
  void dispose() {
    // NOTE: client intentionally survives this screen (shared via GameManager)
    // unless the user cancels — handled by PopScope-free back button below.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        GameManager.removeAllData();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Room Created')),
        body: Padding(
          padding: UiHelper.getResponsivePadding(context),
          child: Column(
            children: [
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
                      _generatedCode.isEmpty ? '····' : _generatedCode,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 163, 73, 164),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _readyRelays == 0
                    ? 'Connecting to relays…'
                    : 'Connected: $_readyRelays relay(s)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
              SelectableText(
                "Now invite your friends!",
                style: const TextStyle(fontSize: 16, color: Colors.blue),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      GameManager.removeAllData();
                      Navigator.pop(context);
                    },
                  ),
                  ElevatedButton(
                    child: const Text('Start'),
                    onPressed:
                        _players.isEmpty || _client == null
                            ? null
                            : () {
                              dev.log(
                                "Host proceeds to area setup",
                                name: "log.HostInvite.start",
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SetupPage(),
                                ),
                              );
                            },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
