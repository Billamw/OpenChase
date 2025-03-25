import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:convert';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/open_chase_key.dart';

class NostrHelper {
  static WebSocket? _webSocket; // Nullable WebSocket to avoid issues
  static final StreamController<String> _messageStreamController =
      StreamController.broadcast();
  static final Keychain key = Keychain.generate();

  static Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = await WebSocket.connect(OpenChaseKey.nostrRelay);
      log('✅ WebSocket connected to ${OpenChaseKey.nostrRelay}');
    } catch (e) {
      log('❌ Failed to connect WebSocket: $e');
    }
  }

  static Future<void> sendInitialNostr(
    String playerName,
    String roomCode,
  ) async {
    if (_webSocket == null) await connect(); // Ensure connection before sending
    var jsonString = json.encode({
      // "private": key.private,
      // "public": key.public,
      "private": OpenChaseKey.private,
      "public": OpenChaseKey.public,
      "roomCode": roomCode,
      "content": "Swag",
      "host": playerName,
    });

    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: OpenChaseKey.private,
      verify: true,
    );

    _webSocket?.add(testEvent.serialize());
  }

  static Future<void> sendNostr(String playerName) async {
    if (_webSocket == null) await connect(); // Ensure connection before sending
    log("sending nostr");
    var jsonString = json.encode({
      "name": playerName,
      "location": [0, 0],
      "host": playerName,
    });

    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: OpenChaseKey.private,
      verify: true,
    );

    _webSocket?.add(testEvent.serialize());
    log("📡 Sent Nostr event ${testEvent.serialize()}");
    final completer = Completer<void>();
    StreamSubscription? sub;
    try {
      sub = _webSocket?.listen((event) {
        log('Event status: $event');
        if (sub != null) {
          sub.cancel();
        }
        completer.complete();
      });

      await completer.future;
    } catch (e) {
      log("⚠️ Error on listener");
    }
  }

  static Future<void> closeWebSocket() async {
    await _webSocket?.close();
    _webSocket = null; // Reset WebSocket after closing
    log('❌ WebSocket manually closed');
  }

  static Future<void> listenForMessages(Function(String) message) async {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(authors: [key.public]),
    ]);

    WebSocket webSocket = await WebSocket.connect(OpenChaseKey.nostrRelay);

    // Send a request message to the WebSocket server
    webSocket.add(requestWithFilter.serialize());

    // Listen for events from the WebSocket server
    webSocket.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);

        // Check if the message is an "EVENT" type
        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // The actual event object

          String content = eventData["content"];

          try {
            var jsonData = json.decode(content);
            JsonEncoder encoder = JsonEncoder.withIndent('  ');
            String prettyprint = encoder.convert(jsonData);
            print(prettyprint);
          } catch (e) {
            print("⚠️ Error decoding message: $e");
          }
        }
      } catch (e) {
        print("⚠️ Error decoding message: $e");
      }
    });
    // await Future.delayed(Duration(seconds: 5));
    // await webSocket.close();
  }

  static Future<Map<String, dynamic>> requestInitialMessage(
    String roomCode,
  ) async {
    if (_webSocket == null) await connect(); // Ensure WebSocket connection

    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [OpenChaseKey.public],
        since: currentUnixTimestampSeconds() - 5 * 60, // 5 minutes ago
        limit: 5,
      ),
    ]);

    _webSocket?.add(requestWithFilter.serialize());
    log("📡 Sent request for room: $roomCode");

    Completer<Map<String, dynamic>> completer = Completer();
    StreamSubscription? sub;

    sub = _webSocket?.listen((message) {
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
