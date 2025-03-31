import 'dart:convert';
import 'dart:developer' as dev;

import 'package:nostr/nostr.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/nostr/abstract_nostr.dart';
import 'package:openchase/utils/nostr/nostr_helper.dart';
import 'package:openchase/utils/game_manager.dart';

class HostRoomNostr extends BaseNostr {
  late Keychain gameKeys;
  final Function(Map) onMessageReceived;

  HostRoomNostr({required this.onMessageReceived}) {
    gameKeys = Keychain.generate();
    connect();
  }

  @override
  void onConnected() {
    dev.log('🔄 RoomNostr is now connected.');
    listenForNewPlayer();
  }

  void listenForNewPlayer() {
    webSocket?.sink.add(
      NostrHelper.getSerializedRequest(GameManager.roomPublicKey),
    );

    webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;

      Map<String, dynamic> jsonName = json.decode(content);
      dev.log("message: $jsonName", name: "log.Test.RoomNostr.listen");

      if (jsonName.containsKey("name")) {
        GameManager.players.add(jsonName["name"]);
        onMessageReceived(jsonName);
        dev.log(
          "Players in Settings: ${GameManager.players}",
          name: "log.Test.ArrayCheck.listen",
        );
      }
    });
  }

  void sendGameStartNostr() async {
    GameManager.gamePublicKey = gameKeys.public;
    GameManager.gamePrivateKey = gameKeys.private;

    var jsonString = json.encode({
      "gamePrivateKey": gameKeys.private,
      "gamePublicKey": gameKeys.public,
    });

    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, GameManager.roomPrivateKey),
    );

    dev.log("Sent Game Nostr", name: "log.Test.sendGameNostr");
  }
}
