import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:openchase/utils/nostr_settings.dart';

class ContinuousNostr {
  static WebSocketChannel? _webSocket;
  final Function(String) onMessageReceived;

  ContinuousNostr({required this.onMessageReceived});

  /// Connects to the WebSocket
  Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      dev.log('✅ WebSocket connected to ${NostrSettings.nostrRelay}');
      _sendInitialRequest();
      _listen();
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
  }

  void _sendInitialRequest() {
    _webSocket?.sink.add(
      NostrSettings.getSerializedRequest(NostrSettings.roomPublicKey),
    );
  }

  /// Listens for incoming messages
  void _listen() {
    _webSocket?.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);

        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // Extract event object
          String content = eventData["content"];
          Map<String, dynamic> jsonData = json.decode(content);
          if (jsonData.containsKey("name")) {
            onMessageReceived(jsonData["name"]); // Send data to the UI
          }
        }
      } catch (e) {
        dev.log("⚠️ Error decoding message: $e");
      }
    });
  }

  /// Closes the WebSocket connection
  Future<void> close({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null; // Reset WebSocket after closing
    dev.log('❌($message) WebSocket manually closed');
  }

  Future<void> sendNostr(String playerName) async {
    if (_webSocket == null) await connect();
    var jsonString = json.encode({
      "name": playerName,
      "location": [0, 0],
    });

    _webSocket?.sink.add(
      NostrSettings.getSerializedEvent(
        jsonString,
        NostrSettings.roomPrivateKey,
      ),
    );
  }
}
