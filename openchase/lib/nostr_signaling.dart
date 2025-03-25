import 'dart:convert';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';

Future<void> requestMessage() async {
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: [OpenChaseKey.public],
      since: currentUnixTimestampSeconds() - 5 * 60,
    ),
  ]);

  final channel = WebSocketChannel.connect(Uri.parse(OpenChaseKey.nostrRelay));

  // Send a request message to the WebSocket server
  channel.sink.add(requestWithFilter.serialize());

  // Listen for events from the WebSocket server
  channel.stream.listen((message) {
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
}

void main() async {
  print("📡 Requesting messages...");
  await requestMessage(); // Request messages
}
