import 'dart:convert';
import 'dart:io';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/caesar_cipher.dart';
import 'package:openchase/utils/open_chase_key.dart';

final String nostrRelay = 'wss://relay.damus.io';
Keychain key = Keychain.generate();
String roomCode = "ABCD";
int since = currentUnixTimestampSeconds();

Future<void> sendNostr() async {
  print("🔑 Public Key: ${key.public}");
  print("🔑 Private Key: ${key.private}");
  var jsonString = json.encode({
    "private": CaesarCipher.encrypt(key.private, roomCode),
    "public": CaesarCipher.encrypt(key.public, roomCode),
    "content": "Hello, World!",
  });
  Event testEvent = Event.from(
    kind: 1,
    content: jsonString,
    privkey: OpenChaseKey.private,
    verify: true,
  );

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(nostrRelay);

  // Send an event to the WebSocket server
  webSocket.add(testEvent.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(Duration(seconds: 1));
  webSocket.listen((event) {
    print('Event status: $event');
  });

  // Close the WebSocket connection
  await webSocket.close();
}

Future<void> requestMessage() async {
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(authors: [OpenChaseKey.public]),
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

        String content = eventData["content"];

        try {
          var jsonData = json.decode(content);
          JsonEncoder encoder = JsonEncoder.withIndent('  ');
          String prettyprint = encoder.convert(jsonData);
          print(prettyprint);
          var publicKey = CaesarCipher.decrypt(jsonData["public"], roomCode);
          var privateKey = CaesarCipher.decrypt(jsonData["private"], roomCode);
          print("Public Key: $publicKey");
          print("Private Key: $privateKey");
        } catch (e) {
          print("⚠️ Error decoding message: $e");
        }

        // print("📩 New message from $pubkey at $createdAt: $content");
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
