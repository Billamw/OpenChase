import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';

class WebSocketMessagesPage extends StatefulWidget {
  @override
  _WebSocketMessagesPageState createState() => _WebSocketMessagesPageState();
}

class _WebSocketMessagesPageState extends State<WebSocketMessagesPage> {
  late WebSocketChannel channel;
  List<String> messages = [];

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [OpenChaseKey.public],
        since: currentUnixTimestampSeconds() - 5 * 60,
      ),
    ]);

    channel = WebSocketChannel.connect(Uri.parse(OpenChaseKey.nostrRelay));
    channel.sink.add(requestWithFilter.serialize());

    channel.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);
        log("📡 Received message: $decodedMessage");

        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // The actual event object
          String content = eventData["content"];

          setState(() {
            messages.insert(0, content); // Add new messages at the top
          });
        }
      } catch (e) {
        log("⚠️ Error decoding message: $e");
      }
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Live WebSocket Messages")),
      body: ListView.builder(
        itemCount: messages.length,
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Text(messages[index]),
            ),
          );
        },
      ),
    );
  }
}
