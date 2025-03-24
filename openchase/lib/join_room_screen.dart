import 'package:flutter/material.dart';
import 'package:openchase/utils/nostr_helper.dart';
import 'package:openchase/utils/ui_helper.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  _JoinRoomScreenState createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  String? _nameError;
  String? _codeError;

  void _clearErrors() {
    setState(() {
      _nameError = null;
      _codeError = null;
    });
  }

  Future<void> _joinRoom(BuildContext context) async {
    // Clear previous errors
    _clearErrors();

    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      setState(() => _nameError = "Name can't be empty");
      return;
    }

    // Connect to WebSocket
    await NostrHelper.connect();

    // Request message from Nostr
    print("Requesting message for $code");
    await NostrHelper.requestMessage(code);

    // Show loading indicator
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

    // Wait for a response (you might want to implement a timeout here)
    await Future.delayed(Duration(seconds: 1));

    // Close loading indicator
    Navigator.of(context).pop();

    // Check if room exists (you'll need to implement this logic in NostrHelper)
    bool hasHost = await NostrHelper.doesRoomExist(code);

    if (hasHost) {
      await _showJoinConfirmationDialog(context, name, code);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Room not found")));
    }
  }

  Future<bool?> _showJoinConfirmationDialog(
    BuildContext context,
    String name,
    String code,
  ) async {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("Join $code?"),
            content: Text("Are you sure you want to join ${name}'s room?"),
            actions: [
              TextButton(
                child: Text("Cancel"),
                onPressed: () => Navigator.pop(context),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(foregroundColor: Colors.green),
                child: Text("Join"),
                onPressed: () async {
                  await NostrHelper.sendNostr(name, code);
                  print("$name joined $code successfully");
                  Navigator.pop(context);
                  Navigator.pop(context); // Close join screen
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

            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Your Name",
                errorText: _nameError,
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() {}),
            ),
            SizedBox(height: 16),

            TextField(
              maxLength: 4,
              controller: _codeController,
              decoration: InputDecoration(
                labelText: "Room Code",
                hintText: "XXXX",
                errorText: _codeError,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              style: TextStyle(fontSize: 24),
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
                style: ElevatedButton.styleFrom(minimumSize: Size(150, 50)),
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
