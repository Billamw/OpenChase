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

  static Future<void> sendInitialNostr(
    String playerName,
    String roomCode,
  ) async {
    if (_webSocket == null) await connect(); // Ensure connection before sending
    NostrSettings.roomPrivateKey = key.private;
    NostrSettings.roomPublicKey = key.public;
    var jsonString = json.encode({
      "private": NostrSettings.roomPrivateKey,
      "public": NostrSettings.roomPublicKey,
      "roomCode": roomCode,
      "host": playerName,
    });

    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: NostrSettings.initialPrivateKey,
      verify: true,
    );

    _webSocket?.sink.add(testEvent.serialize());
  }

  static Future<void> sendJoinNostr(String playerName) async {
    if (_webSocket == null) await connect(); // Ensure connection before sending

    var jsonString = json.encode({
      "name": playerName,
      "location": [0, 0],
    });
    log(
      "Sending with private key: ${NostrSettings.roomPrivateKey}",
      name: "Key Check",
    );
    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: NostrSettings.roomPrivateKey,
      verify: true,
    );

    _webSocket?.sink.add(testEvent.serialize());
    log("📡 Sent Nostr event: ${testEvent.serialize()}");
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
