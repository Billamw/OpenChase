import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr_helper.dart';
import 'package:openchase/utils/nostr_settings.dart';
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
  /// Saves the room code, host name, and keys in NostrSettings for the host
  Future<void> sendInitialNostr(
    List players,
    String hostName,
    String roomCode,
  ) async {
    NostrSettings.roomPrivateKey = initialKeys.private;
    NostrSettings.roomPublicKey = initialKeys.public;
    NostrSettings.roomCode = roomCode;
    NostrSettings.roomHost = hostName;

    if (webSocket == null) await connect();

    var jsonString = json.encode({
      "private": initialKeys.private,
      "public": initialKeys.public,
      "players": players,
      "roomCode": roomCode,
      "host": hostName,
    });

    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(
        jsonString,
        NostrSettings.initialPrivateKey,
      ),
    );

    dev.log(
      "Send Initial Nostr with players $players",
      name: "log.Test.sendInitialNostr",
    );
  }

  Future<void> sendInitialJoinNostr() async {
    if (webSocket == null) await connect();
    var jsonString = json.encode({"name": NostrSettings.userName});
    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, NostrSettings.roomPrivateKey),
    );
    dev.log(
      "📡 ${NostrSettings.getFormattedRoomInfo()}",
      name: "log.Test.NostrDataInfo.sendJoinNostr",
    );
  }

  Future<bool> requestInitialMessage(String roomCode) async {
    if (webSocket == null) await connect();

    webSocket?.sink.add(
      NostrHelper.getSerializedRequest(NostrSettings.initialPublicKey),
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
        NostrSettings.players.add(jsonData["host"]);
        NostrSettings.addPlayersWithoutDuplicates(jsonData["players"]);
        ///////////////////
        NostrSettings.roomHost = jsonData["host"];
        NostrSettings.roomPrivateKey = jsonData["private"];
        NostrSettings.roomPublicKey = jsonData["public"];
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
