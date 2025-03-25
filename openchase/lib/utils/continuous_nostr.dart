import 'dart:convert';
import 'dart:developer' as dev;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';

class ContinuousNostr {
  late WebSocketChannel _channel;
  final Function(Map<String, dynamic>) onMessageReceived;

  ContinuousNostr({required this.onMessageReceived});

  /// Connects to the WebSocket
  void connect() {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [OpenChaseKey.public],
        since: currentUnixTimestampSeconds() - 5 * 60,
      ),
    ]);

    _channel = WebSocketChannel.connect(Uri.parse(OpenChaseKey.nostrRelay));
    _channel.sink.add(requestWithFilter.serialize());

    _listen();
  }

  /// Listens for incoming messages
  void _listen() {
    _channel.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);
        dev.log("(listen) Received message: $decodedMessage");

        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // Extract event object
          String content = eventData["content"];
          Map<String, dynamic> jsonData = json.decode(content);
          if (jsonData.containsKey("name")) {
            onMessageReceived(jsonData); // Send data to the UI
          }
        }
      } catch (e) {
        dev.log("⚠️ Error decoding message: $e");
      }
    });
  }

  /// Closes the WebSocket connection
  void close() {
    _channel.sink.close();
  }
}
