import 'dart:math';
import 'package:flutter/material.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  _CreateRoomScreenState createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _generatedCode = '';

  // Generate a random 4-letter code (A-Z)
  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
    _generatedCode =
        List.generate(4, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    // Generate code when the screen is opened
    _generateRandomCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Room'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          double padding =
              constraints.maxWidth > 600 ? 100 : 16; // Adjust based on width

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Column(
              children: [
                // Display the generated code
                Container(
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

                const SizedBox(height: 20),

                // Name input field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Room Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a room name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Action buttons
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
                      child: const Text('Create Room'),
                      onPressed: () async {
                        String name = _nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a room name'),
                            ),
                          );
                          return;
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Room created! Code: $_generatedCode',
                            ),
                          ),
                        );

                        Navigator.pop(context);

                        //TODO: navigate to the room screen and open webrtc connection
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
