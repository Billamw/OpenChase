import 'dart:convert';
import 'dart:io';
import 'package:nostr/nostr.dart';

Keychain keys = Keychain.generate();
String subId = generate64RandomHexChars();
final String nostrRelay = 'wss://relay.damus.io';
int createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

Future<void> sendNostr() async {
  Event testEvent = Event.from(
    kind: 1,
    tags: [],
    content: "Hallo Schnucki!",
    privkey: keys.private,
    verify: true,
  );
  // print("Serialized Event: ${anotherEvent.serialize()}");

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(nostrRelay);
  // if the current socket fail try another one
  // wss://nostr.sandwich.farm
  // wss://relay.damus.io

  // Send an event to the WebSocket server
  webSocket.add(testEvent.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(Duration(seconds: 1));
  webSocket.listen(
    (event) {
      print('Event status: $event');
    },
    onError: (error) {
      print('Error: $error');
    },
    onDone: () {
      print('WebSocket is closed');
    },
  );

  print(keys.public);

  // Close the WebSocket connection
  await webSocket.close();
}

Future<void> requestMessage() async {
  Request requestWithFilter = Request(subId, [
    Filter(authors: [keys.public], limit: 5),
  ]);

  WebSocket webSocket = await WebSocket.connect(nostrRelay);

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  // Listen for events from the WebSocket server
  webSocket.listen((message) {
    try {
      var decodedMessage = jsonDecode(message);

      // Check if the message is an "EVENT" type
      if (decodedMessage is List &&
          decodedMessage.isNotEmpty &&
          decodedMessage[0] == "EVENT") {
        var eventData = decodedMessage[2]; // The actual event object

        String pubkey = eventData["pubkey"];
        String content = eventData["content"];
        int createdAt = eventData["created_at"];

        print("📩 New message from $pubkey at $createdAt: $content");
      }
    } catch (e) {
      print("⚠️ Error decoding message: $e");
    }
  });
  await Future.delayed(Duration(seconds: 5));
  await webSocket.close();
}

void main() async {
  print("🚀 Sending a Nostr message...");
  await sendNostr(); // Send a test message

  print("📡 Requesting messages...");
  await requestMessage(); // Request messages
}
