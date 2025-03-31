import 'dart:convert';
import 'dart:developer' as dev;

import 'package:openchase/utils/nostr/abstract_nostr.dart';
import 'package:openchase/utils/nostr/nostr_helper.dart';
import 'package:openchase/utils/game_manager.dart';

class PlayerRoomNostr extends BaseNostr {
  final Function(Map) onMessageReceived;

  PlayerRoomNostr({required this.onMessageReceived}) {
    connect();
  }

  @override
  void onConnected() {
    dev.log('🔄 RoomNostr is now connected.');
    listenForMessages();
  }

  void listenForMessages() {
    webSocket?.sink.add(
      NostrHelper.getSerializedRequest(GameManager.roomPublicKey),
    );

    webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;

      Map<String, dynamic> jsonName = json.decode(content);
      dev.log("message: $jsonName", name: "log.Test.PlayerRoomNostr.listen");

      if (jsonName.containsKey("joined") ||
          jsonName.containsKey("gamePrivateKey") ||
          jsonName.containsKey("left")) {
        onMessageReceived(jsonName);
      }
    });
  }

  void leaveGameNostr() async {
    var jsonString = json.encode({"left": GameManager.userName});

    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, GameManager.roomPrivateKey),
    );

    dev.log("Sent Game Nostr", name: "log.Test.sendGameNostr");
  }
}
