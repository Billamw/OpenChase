import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openchase/utils/inistial_nostr.dart';
import 'package:openchase/utils/ui_helper.dart';
import 'package:openchase/utils/continuous_nostr.dart';

class HostInviteScreen extends StatefulWidget {
  final String playerName;

  const HostInviteScreen({super.key, required this.playerName});

  @override
  State<HostInviteScreen> createState() => _HostInviteScreenState();
}

class _HostInviteScreenState extends State<HostInviteScreen> {
  String _generatedCode = '';
  late ContinuousNostr _nostrListener;
  // ignore: prefer_final_fields
  List _players = [];

  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _generatedCode =
        List.generate(4, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _generateRandomCode();
    _players.add(widget.playerName);
    InitialNostr.connect(); // ✅ Open WebSocket when screen loads
    InitialNostr.sendInitialNostr(_players, widget.playerName, _generatedCode);

    // ✅ Initialize ContinuousNostr and listen for messages
    _nostrListener = ContinuousNostr(
      onMessageReceived: (message) {
        setState(() {
          _players.add(message);
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

            // ✅ Display received messages
            Expanded(
              child: ListView.builder(
                itemCount: _players.length,
                itemBuilder: (context, index) {
                  return ListTile(title: Text(_players[index]));
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
