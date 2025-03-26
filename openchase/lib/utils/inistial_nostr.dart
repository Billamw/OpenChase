import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/nostr_settings.dart';

class InitialNostr {
  static WebSocketChannel? _webSocket;
  static final Keychain key = Keychain.generate();

  static Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = WebSocketChannel.connect(
        Uri.parse(NostrSettings.nostrRelay),
      );
      log('✅ WebSocket connected to ${NostrSettings.nostrRelay}');
    } catch (e) {
      log('❌ Failed to connect WebSocket: $e');
    }
  }

  static Future<void> closeWebSocket({String message = ""}) async {
    await _webSocket?.sink.close();
    _webSocket = null; // Reset WebSocket after closing
    log('❌($message) WebSocket manually closed');
  }

  /// Host sends the initial Nostr event with room specific keys and data
  /// Saves the room code, host name, and keys in NostrSettings for the host
  static Future<void> sendInitialNostr(String hostName, String roomCode) async {
    if (_webSocket == null) await connect();
    NostrSettings.roomPrivateKey = key.private;
    NostrSettings.roomPublicKey = key.public;
    NostrSettings.roomCode = roomCode;
    NostrSettings.roomHost = hostName;

    var jsonString = json.encode({
      "private": key.private,
      "public": key.public,
      "roomCode": roomCode,
      "host": hostName,
    });

    _webSocket?.sink.add(
      NostrSettings.getSerializedEvent(
        jsonString,
        NostrSettings.initialPrivateKey,
      ),
    );
  }

  static Future<void> sendJoinNostr(String playerName) async {
    if (_webSocket == null) await connect();
    NostrSettings.userName = playerName; // Store the player name
    var jsonString = json.encode({
      "name": playerName,
      "location": [0, 0],
    });

    _webSocket?.sink.add(
      NostrSettings.getSerializedEvent(
        jsonString,
        NostrSettings.roomPrivateKey,
      ),
    );
  }

  static Future<Map<String, dynamic>> requestInitialMessage(
    String roomCode,
  ) async {
    if (_webSocket == null) await connect(); // Ensure WebSocket connection

    _webSocket?.sink.add(
      NostrSettings.getSerializedRequest(NostrSettings.initialPublicKey),
    );
    log("📡 Sent request for room: $roomCode");

    Completer<Map<String, dynamic>> completer = Completer();
    StreamSubscription? sub;

    sub = _webSocket?.stream.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);

        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // The actual event object
          String content = eventData["content"];
          log("📩 Received event content: $content");

          var jsonData = json.decode(content);
          String roomCodeMessage = jsonData["roomCode"];
          String hostName = jsonData["host"];
          String privateKey = jsonData["private"];
          String publicKey = jsonData["public"];

          NostrSettings.roomPrivateKey = privateKey;
          NostrSettings.roomPublicKey = publicKey;

          if (roomCodeMessage == roomCode) {
            log("✅ Room found! Host: $hostName");
            sub?.cancel();
            completer.complete({
              "exists": true,
              "host": hostName,
              "private": privateKey,
              "public": publicKey,
            });
          }
        }
      } catch (e) {
        log("⚠️ Error processing message: $e");
      }
    });

    // Timeout after 3 seconds if no response is received
    Future.delayed(Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        log("❌ No valid room found.");
        completer.complete({"exists": false, "host": "", "private": ""});
      }
    });

    return completer.future;
  }
}
