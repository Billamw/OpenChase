import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:openchase/utils/nostr_helper.dart';
import 'package:openchase/utils/nostr_settings.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RoomNostr {
  static WebSocketChannel? _webSocket;
  final Function(String) onMessageReceived;

  RoomNostr({required this.onMessageReceived}) {
    connect();
  }

  /// Connects to the WebSocket
  Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections

    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      _listen();
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
  }

  void _listen() {
    _webSocket?.sink.add(
      NostrHelper.getSerializedRequest(NostrSettings.roomPublicKey),
    );
    _webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;
      Map<String, dynamic> jsonName = json.decode(
        content,
      ); // returns like {"name":"playerName"}
      if (jsonName.containsKey("name")) {
        onMessageReceived(jsonName["name"]); // Send data to the UI
        dev.log("message: $jsonName", name: "log.Test.playersCheck.initState");
      }
    });
  }

  /// Closes the WebSocket connection
  Future<void> close({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null; // Reset WebSocket after closing
    dev.log('❌($message) WebSocket manually closed');
  }

  /// Connects to the WebSocket
  static Future<void> _connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      _webSocket?.sink.add(
        NostrHelper.getSerializedRequest(NostrSettings.roomPublicKey),
      );
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
  }
}
