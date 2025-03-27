import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';
import 'package:openchase/utils/nostr_helper.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr_settings.dart';

class InitialNostr {
  static WebSocketChannel? _webSocket;
  static final Keychain key = Keychain.generate();

  static Future<void> _connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      dev.log('✅ WebSocket connected to ${NostrSettings.nostrRelay}');
    } catch (e) {
      dev.log('❌ Failed to connect WebSocket: $e');
    }
  }

  static Future<void> close({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null;
    dev.log('❌($message) WebSocket manually closed');
  }

  /// Host sends the initial Nostr over initialPrivateKey event with room specific keys and data
  /// Saves the room code, host name, and keys in NostrSettings for the host
  static Future<void> sendInitialNostr(
    List players,
    String hostName,
    String roomCode,
  ) async {
    NostrSettings.roomPrivateKey = key.private;
    NostrSettings.roomPublicKey = key.public;
    NostrSettings.roomCode = roomCode;
    NostrSettings.roomHost = hostName;

    if (_webSocket == null) await _connect();

    var jsonString = json.encode({
      "private": key.private,
      "public": key.public,
      "players": players,
      "roomCode": roomCode,
      "host": hostName,
    });

    _webSocket?.sink.add(
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

  /// Player send initial request to get room keys and data
  static Future<Map<String, dynamic>> requestInitialMessage(
    String roomCode,
  ) async {
    if (_webSocket == null) await _connect(); // Ensure WebSocket connection

    _webSocket?.sink.add(
      NostrHelper.getSerializedRequest(NostrSettings.initialPublicKey),
    );

    Completer<Map<String, dynamic>> completer = Completer();
    StreamSubscription? sub;

    sub = _webSocket?.stream.listen((message) {
      String content = NostrHelper.getContentFromMessage(message);
      if (content.isEmpty) return;
      var jsonData = json.decode(content);
      String roomCodeMessage = jsonData["roomCode"];
      String hostName = jsonData["host"];
      String privateKey = jsonData["private"];
      String publicKey = jsonData["public"];
      List players = jsonData["players"];

      // stores the room keys for the player
      NostrSettings.roomPrivateKey = privateKey;
      NostrSettings.roomPublicKey = publicKey;

      if (roomCodeMessage == roomCode) {
        dev.log("✅ Room found! Host: $hostName");
        sub?.cancel();
        completer.complete({
          "exists": true,
          "host": hostName,
          "players": players,
          "private": privateKey,
          "public": publicKey,
        });
      }
    });

    // Timeout after 3 seconds if no response is received
    Future.delayed(Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        dev.log("❌ No valid room found.");
        completer.complete({"exists": false, "host": "", "private": ""});
      }
    });

    return completer.future;
  }
}
