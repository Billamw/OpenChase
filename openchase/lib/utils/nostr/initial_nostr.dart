import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr/nostr_helper.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/nostr/abstract_nostr.dart';

class InitialNostr extends BaseNostr {
  late Keychain initialKeys;

  InitialNostr() {
    initialKeys = Keychain.generate();
    connect();
  }

  @override
  void onConnected() {
    dev.log('🔄 InitialNostr is now connected.');
  }

  /// Host sends the initial Nostr over initialPrivateKey event with room specific keys and data
  /// Saves the room code, host name, and keys in GameManager for the host
  Future<void> sendInitialNostr(
    List players,
    String hostName,
    String roomCode,
  ) async {
    GameManager.roomPrivateKey = initialKeys.private;
    GameManager.roomPublicKey = initialKeys.public;
    GameManager.roomCode = roomCode;
    GameManager.roomHost = hostName;

    if (webSocket == null) await connect();

    var jsonString = json.encode({
      "private": initialKeys.private,
      "public": initialKeys.public,
      "players": players,
      "roomCode": roomCode,
      "host": hostName,
    });

    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, NostrHelper.initialPrivateKey),
    );

    dev.log(
      "Send Initial Nostr with players $players",
      name: "log.Test.sendInitialNostr",
    );
  }

  Future<void> sendInitialJoinNostr() async {
    if (webSocket == null) await connect();
    var jsonString = json.encode({"joined": GameManager.userName});
    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, GameManager.roomPrivateKey),
    );
    dev.log(
      "📡 ${GameManager.getFormattedRoomInfo()}",
      name: "log.Test.NostrDataInfo.sendJoinNostr",
    );
  }

  Future<bool> requestInitialMessage(String roomCode) async {
    if (webSocket == null) await connect();

    webSocket?.sink.add(
      NostrHelper.getSerializedRequest(NostrHelper.initialPublicKey),
    );

    Completer<bool> completer = Completer();
    StreamSubscription? sub;

    sub = webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;
      var jsonData = json.decode(content);
      dev.log(
        "Initial message received: $jsonData",
        name: "log.Test.requestInitialMessage",
      );

      if (jsonData["roomCode"] == roomCode) {
        //////////////// TODO Check  these two
        GameManager.players.add(jsonData["host"]);
        GameManager.addPlayersWithoutDuplicates(jsonData["players"]);
        ///////////////////
        GameManager.roomHost = jsonData["host"];
        GameManager.roomPrivateKey = jsonData["private"];
        GameManager.roomPublicKey = jsonData["public"];
        sub?.cancel();
        completer.complete(true);
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        dev.log("❌ No valid room found.");
        completer.complete(false);
      }
    });

    return completer.future;
  }
}
