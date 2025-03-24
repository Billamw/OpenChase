import 'package:flutter/material.dart';
import 'package:openchase/invite_room_screen.dart';
import 'package:openchase/utils/advanced_settings.dart';
import 'package:openchase/utils/ui_helper.dart';

class SetupRoomScreen extends StatefulWidget {
  const SetupRoomScreen({super.key});

  @override
  State<SetupRoomScreen> createState() => _SetupRoomScreenState();
}

class _SetupRoomScreenState extends State<SetupRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool showAdvancedSettings = false;
  double uncoverInterval = 3; // Default value
  bool setting1 = false, setting2 = false, setting3 = false;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name input field
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Enter Your Name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            // Advanced Settings Toggle
            TextButton(
              onPressed: () {
                setState(() {
                  showAdvancedSettings = !showAdvancedSettings;
                });
              },
              child: Text(
                showAdvancedSettings
                    ? "Hide Advanced Settings"
                    : "Show Advanced Settings",
              ),
            ),

            if (showAdvancedSettings) ...[
              const SizedBox(height: 10),
              Text("Uncover Interval: ${uncoverInterval.toInt()}"),
              Slider(
                value: uncoverInterval,
                min: 1,
                max: 5,
                divisions: 4,
                label: uncoverInterval.toInt().toString(),
                onChanged: (value) {
                  setState(() {
                    uncoverInterval = value;
                  });
                },
              ),
              // ✅ Fix: Wrap ListView in SizedBox with a fixed height
              SizedBox(
                height: 200, // Adjust height as needed
                child: ListView(
                  children: List.generate(AdvancedSettings.settings.length, (
                    index,
                  ) {
                    var setting = AdvancedSettings.settings[index];

                    return CheckboxListTile(
                      title: Text(setting.name),
                      value: setting.value,
                      onChanged: (bool? newValue) {
                        setState(() {
                          setting.value = newValue ?? false;
                        });
                      },
                    );
                  }),
                ),
              ),
            ],

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

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => InviteRoomScreen(
                            playerName: _nameController.text.trim(),
                            uncoverInterval: uncoverInterval.toInt(),
                            settings: [setting1, setting2, setting3],
                          ),
                    ),
                  );
                },
                child: const Text("Next"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
