import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';

final String nostrRelay = 'wss://relay.damus.io';
Keychain key = Keychain.generate();
String roomCode = "ABCD";
int since = currentUnixTimestampSeconds();

Future<void> requestMessage() async {
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: [OpenChaseKey.public],
      since: currentUnixTimestampSeconds() - 5 * 60,
    ),
  ]);

  WebSocket webSocket = await WebSocket.connect(nostrRelay);

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  // Listen for events from the WebSocket server
  webSocket.listen((message) {
    try {
      var decodedMessage = jsonDecode(message);
      log("📡 Received message (Signaling): $decodedMessage");
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
        } catch (e) {
          print("⚠️ Error decoding message: $e");
        }
      }
    } catch (e) {
      print("⚠️ Error decoding message: $e");
    }
  });
  // await Future.delayed(Duration(seconds: 5));
  // await webSocket.close();
}

void main() async {
  print("📡 Requesting messages...");
  await requestMessage(); // Request messages
}
