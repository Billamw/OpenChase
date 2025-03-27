import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:openchase/utils/nostrConnections/initial_nostr.dart';
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

      _webSocket?.sink.add(
        NostrHelper.getSerializedRequest(NostrSettings.roomPublicKey),
      );
      _webSocket?.stream.listen((message) {
        String content = NostrHelper.getContentFromMessage(message);
        if (content.isEmpty) return;
        Map<String, dynamic> jsonData = json.decode(content);
        if (jsonData.containsKey("name")) {
          dev.log(
            "listened data: $jsonData",
            name: "log.Test.NostrDataInfo.containsName",
          );
          dev.log(
            "Notr Players before: ${NostrSettings.players}",
            name: "log.Test.NostrDataInfo.PlayerCheck",
          );
          NostrSettings.players.add(NostrSettings.roomHost);
          NostrSettings.players.add(jsonData["name"]);
          dev.log(
            "Notr Players after: ${NostrSettings.players}",
            name: "log.Test.NostrDataInfo.PlayerCheck",
          );
          onMessageReceived(jsonData["name"]); // Send data to the UI
          updatePlayers(NostrSettings.players);
          dev.log(
            "📡 ${NostrSettings.getFormattedRoomInfo()}",
            name: "log.Test.NostrDataInfo.sendJoinNostr",
          );
        } else if (jsonData.containsKey("players") &&
            !jsonData.containsKey("name")) {
          dev.log(
            "📡 ${NostrSettings.getFormattedRoomInfo()}",
            name: "log.Test.NostrDataInfo.playersNostrFound",
          );
        }
      });
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
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

  Future<void> updatePlayers(List players) async {
    if (_webSocket == null) await _connect();
    var jsonString = json.encode({"players": players});
    _webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, NostrSettings.roomPrivateKey),
    );
    dev.log(
      "📡 $players to json -> sending $jsonString to ${NostrSettings.players}",
      name: "log.Test.NostrDataInfo.updatedPlayers",
    );
  }

  static Future<void> sendJoinNostr() async {
    if (_webSocket == null) await _connect();
    var jsonString = json.encode({"name": NostrSettings.userName});
    _webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, NostrSettings.roomPrivateKey),
    );
    dev.log(
      "📡 ${NostrSettings.getFormattedRoomInfo()}",
      name: "log.Test.NostrDataInfo.sendJoinNostr",
    );
  }
}
