// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:openchase/invite_room_screen.dart';
import 'package:openchase/utils/ui_helper.dart';

class SetupRoomScreen extends StatefulWidget {
  const SetupRoomScreen({super.key});

  @override
  State<SetupRoomScreen> createState() => _SetupRoomScreenState();
}

class _SetupRoomScreenState extends State<SetupRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 300), () {
      FocusScope.of(context).requestFocus(_nameFocusNode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Room')),
      body: Padding(
        padding: EdgeInsets.symmetric(
          vertical: UiHelper.vertical,
          horizontal: UiHelper.getResponsiveWidth(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Name input field
            TextField(
              textInputAction: TextInputAction.done,
              controller: _nameController,
              focusNode: _nameFocusNode, // Auto-select field on load
              onSubmitted: (value) {
                navigateToInviteRoom();
              },
              decoration: const InputDecoration(
                labelText: 'Enter Your Name',
                border: OutlineInputBorder(),
              ),
            ),

            const Spacer(),

            // Next Button (Bottom Right)
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: () {
                  if (_nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter your name")),
                    );
                    return;
                  }

                  navigateToInviteRoom();
                },
                child: const Text("Next"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void navigateToInviteRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                InviteRoomScreen(playerName: _nameController.text.trim()),
      ),
    );
  }
}
