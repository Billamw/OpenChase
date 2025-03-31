import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr_helper.dart';
import 'package:openchase/utils/nostr_settings.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RoomNostr {
  static WebSocketChannel? _webSocket;
  late Keychain gameKeys;
  final Function(Map) onMessageReceived;

  RoomNostr({required this.onMessageReceived}) {
    gameKeys = Keychain.generate();
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
      dev.log("message: $jsonName", name: "log.Test.RoomNostr._listen");
      // for everyone adding new players to their list
      if (jsonName.containsKey("name")) {
        NostrSettings.players.add(jsonName["name"]);
        onMessageReceived(jsonName); // Send data to the UI
        dev.log(
          "Players in Settings: ${NostrSettings.players}",
          name: "log.Test.ArrayCheck._listen",
        );
      }
      // Only for player important.
      if (jsonName.containsKey("gamePrivateKey")) {
        onMessageReceived(jsonName);
        dev.log("Game started", name: "log.Test.StartGame.listen");
      }
    });
  }

  /// Closes the WebSocket connection
  Future<void> close({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null; // Reset WebSocket after closing
    dev.log('❌($message) WebSocket manually closed');
  }

  // Host sends the player to start the game
  void sendGameNotr() async {
    NostrSettings.gamePublicKey = gameKeys.public;
    NostrSettings.gamePrivateKey = gameKeys.private;
    var jsonString = json.encode({
      "gamePrivateKey": gameKeys.private,
      "gamePublicKey": gameKeys.public,
    });
    _webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, NostrSettings.roomPrivateKey),
    );
    dev.log("Sended Game Nostr", name: "log.Test.sendGameNostr");
  }
}
