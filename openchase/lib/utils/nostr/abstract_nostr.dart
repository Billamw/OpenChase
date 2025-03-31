import 'dart:async';
import 'dart:developer' as dev;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:openchase/utils/nostr_settings.dart';

abstract class BaseNostr {
  WebSocketChannel? _webSocket;

  Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections

    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      dev.log('✅ WebSocket connected to ${NostrSettings.nostrRelay}');
      onConnected(); // Call the overridden method
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
  }

  Future<void> close({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null;
    dev.log('❌($message) WebSocket manually closed');
  }

  WebSocketChannel? get webSocket => _webSocket;

  /// Called when the WebSocket connects, should be overridden
  void onConnected();
}
