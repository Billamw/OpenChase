// ignore_for_file: use_build_context_synchronously

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:openchase/invited_room_screen.dart';
import 'package:openchase/utils/inistial_nostr.dart';
import 'package:openchase/utils/ui_helper.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _JoinRoomScreenState createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();

  String? _nameError;
  String? _codeError;

  void _clearErrors() {
    setState(() {
      _nameError = null;
      _codeError = null;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
    InitialNostr.closeWebSocket(message: "join dispose");
    super.dispose();
  }

  Future<void> _joinRoom(BuildContext context) async {
    // Clear previous errors
    _clearErrors();

    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    Map hostData = await InitialNostr.requestInitialMessage(code);

    if (name.isEmpty) {
      setState(() => _nameError = "Name can't be empty");
      return;
    }

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

    if (hostData["exists"]) {
      await _showJoinConfirmationDialog(context, hostData, code);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Room not found")));
      InitialNostr.closeWebSocket();
    }
  }

  Future<bool?> _showJoinConfirmationDialog(
    BuildContext context,
    Map hostdata,
    String code,
  ) async {
    String hostName = hostdata["host"];
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("Join $code?"),
            content: Text("Are you sure you want to join $hostName's room?"),
            actions: [
              TextButton(
                child: Text("Cancel"),
                onPressed: () {
                  Navigator.pop(context);
                  InitialNostr.closeWebSocket(message: "Cancel join");
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(foregroundColor: Colors.green),
                child: Text("Join"),
                onPressed: () {
                  log("joined pressed");
                  InitialNostr.sendJoinNostr(_nameController.text.trim());
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => InvitedRoomScreen(
                            playerName: _nameController.text.trim(),
                            code: code,
                          ),
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

            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                labelText: "Your Name",
                errorText: _nameError,
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() {}),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                FocusScope.of(context).requestFocus(_codeFocus);
              },
            ),
            SizedBox(height: 16),

            TextField(
              maxLength: 4,
              controller: _codeController,
              textInputAction: TextInputAction.done,
              focusNode: _codeFocus,
              onSubmitted: (_) => _joinRoom(context),
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
