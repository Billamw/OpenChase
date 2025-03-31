import 'dart:convert';
import 'dart:developer' as dev;

import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr/abstract_nostr.dart';
import 'package:openchase/utils/nostr_helper.dart';
import 'package:openchase/utils/nostr_settings.dart';

class PlayerRoomNostr extends BaseNostr {
  late Keychain gameKeys;
  final Function(Map) onMessageReceived;

  PlayerRoomNostr({required this.onMessageReceived}) {
    gameKeys = Keychain.generate();
    connect();
  }

  @override
  void onConnected() {
    dev.log('🔄 RoomNostr is now connected.');
    listenForMessages();
  }

  void listenForMessages() {
    webSocket?.sink.add(
      NostrHelper.getSerializedRequest(NostrSettings.roomPublicKey),
    );

    webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;

      Map<String, dynamic> jsonName = json.decode(content);
      dev.log("message: $jsonName", name: "log.Test.RoomNostr.listen");

      if (jsonName.containsKey("name")) {
        NostrSettings.players.add(jsonName["name"]);
        onMessageReceived(jsonName);
        dev.log(
          "Players in Settings: ${NostrSettings.players}",
          name: "log.Test.ArrayCheck.listen",
        );
      }

      if (jsonName.containsKey("gamePrivateKey")) {
        onMessageReceived(jsonName);
        dev.log("Game started", name: "log.Test.StartGame.listen");
      }
    });
  }
}
