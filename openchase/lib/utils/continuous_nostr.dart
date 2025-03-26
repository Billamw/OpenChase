import 'dart:convert';
import 'dart:developer' as dev;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr_settings.dart';

class ContinuousNostr {
  late WebSocketChannel _channel;
  final Function(Map<String, dynamic>) onMessageReceived;

  ContinuousNostr({required this.onMessageReceived});

  /// Connects to the WebSocket
  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(NostrSettings.nostrRelay));
    _channel.sink.add(
      NostrSettings.getSerializedRequest(NostrSettings.roomPublicKey),
    );

    _listen();
  }

  /// Listens for incoming messages
  void _listen() {
    _channel.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);

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

  Future<void> sendNostr(String playerName) async {
    var jsonString = json.encode({
      "name": playerName,
      "location": [0, 0],
    });

    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: NostrSettings.roomPrivateKey,
      verify: true,
    );

    _channel.sink.add(testEvent.serialize());
  }
}
