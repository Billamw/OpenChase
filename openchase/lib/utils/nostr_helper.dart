import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:nostr/nostr.dart';
import 'package:openchase/utils/caesar_cipher.dart';
import 'package:openchase/utils/open_chase_key.dart';

class NostrHelper {
  static WebSocket? _webSocket; // Nullable WebSocket to avoid issues

  static Future<void> connect() async {
    if (_webSocket != null) return; // Prevent multiple connections
    try {
      _webSocket = await WebSocket.connect(OpenChaseKey.nostrRelay);
      print('✅ WebSocket connected to ${OpenChaseKey.nostrRelay}');
    } catch (e) {
      print('❌ Failed to connect WebSocket: $e');
    }
  }

  static Future<void> sendNostr(String playerName, String roomCode) async {
    if (_webSocket == null) await connect(); // Ensure connection before sending
    Keychain key = Keychain.generate();
    var jsonString = json.encode({
      "private": CaesarCipher.encrypt(key.private, roomCode),
      "public": CaesarCipher.encrypt(key.public, roomCode),
      "content": "From Create Room",
      "host": playerName,
    });

    Event testEvent = Event.from(
      kind: 1,
      content: jsonString,
      privkey: OpenChaseKey.private,
      verify: true,
    );

    _webSocket?.add(testEvent.serialize());
    // await Future.delayed(Duration(seconds: 1));
    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = _webSocket?.listen((event) {
      print('Event status: $event');
      if (sub != null) {
        sub.cancel();
      }
      completer.complete();
    });

    await completer.future;
  }

  static Future<void> closeWebSocket() async {
    await _webSocket?.close();
    _webSocket = null; // Reset WebSocket after closing
    print('❌ WebSocket manually closed');
  }

  static bool _roomExists = false;

  static Future<bool> doesRoomExist(String roomCode) async {
    // Wait for the response from the WebSocket
    await Future.delayed(Duration(seconds: 2));
    return _roomExists;
  }

  static Future<void> requestMessage(String roomCode) async {
    if (_webSocket == null) await connect();

    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(authors: [OpenChaseKey.public], limit: 5),
    ]);

    _webSocket?.add(requestWithFilter.serialize());

    _webSocket?.listen((message) {
      try {
        var decodedMessage = jsonDecode(message);

        // Check if the message is an "EVENT" type
        if (decodedMessage is List &&
            decodedMessage.isNotEmpty &&
            decodedMessage[0] == "EVENT") {
          var eventData = decodedMessage[2]; // The actual event object

          String content = eventData["content"];
          print("WTF $content");

          try {
            var jsonData = json.decode(content);

            // If we successfully decoded the message, the room exists
            _roomExists = true;

            print("Room found!");
          } catch (e) {
            print("⚠️ Error decoding message _roomexists");
            _roomExists = false;
          }
        }
      } catch (e) {
        print("⚠️ Error decoding message All");
        _roomExists = false;
      }
    });
  }
}
