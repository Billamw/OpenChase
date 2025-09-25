import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/nostr/abstract_nostr.dart';
import 'package:openchase/utils/nostr/nostr_helper.dart';
import 'package:latlong2/latlong.dart';

class GameNostr extends BaseNostr {
  final Function(Map) onMessageReceived;

  GameNostr({required this.onMessageReceived}) {
    connect();
  }

  @override
  void onConnected() {
    dev.log('🔄 GameNostr is now connected.');
    listenForGameMessages();
  }

  void listenForGameMessages() {
    if (webSocket == null) return;
    webSocket!.sink.add(
      NostrHelper.getSerializedRequest(GameManager.gamePublicKey),
    );

    webSocket!.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;

      Map<String, dynamic> jsonData = json.decode(content);
      dev.log(
        "Game message received: $jsonData",
        name: "log.Test.GameNostr.listen",
      );
      onMessageReceived(jsonData);
    });
  }

  Future<void> sendLocation(LatLng location) async {
    if (webSocket == null) await connect();
    var jsonString = json.encode({
      "user": GameManager.userName,
      "lat": location.latitude,
      "lng": location.longitude,
    });
    webSocket?.sink.add(
      NostrHelper.getSerializedEvent(jsonString, GameManager.gamePrivateKey),
    );
    dev.log(
      "📍 Location sent: ${location.latitude}, ${location.longitude}",
      name: "log.Test.GameNostr.sendLocation",
    );
  }
}
