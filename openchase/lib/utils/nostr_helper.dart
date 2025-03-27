import 'dart:convert';
import 'dart:developer' as dev;
import 'package:nostr/nostr.dart';

class NostrHelper {
  static String getSerializedRequest(String pubKey) {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(authors: [pubKey], since: currentUnixTimestampSeconds() - 5 * 60),
    ]);
    return requestWithFilter.serialize();
  }

  static String getSerializedEvent(String jsonString, String privKey) {
    Event event = Event.from(
      kind: 1,
      content: jsonString,
      privkey: privKey,
      verify: true,
    );
    return event.serialize();
  }

  static String getContentFromMessage(String message) {
    try {
      var decodedMessage = jsonDecode(message);

      if (decodedMessage is List &&
          decodedMessage.isNotEmpty &&
          decodedMessage[0] == "EVENT") {
        Map eventData = decodedMessage[2]; // Extract event object
        String content = eventData["content"];
        return content;
      } else {
        return "";
      }
    } catch (e) {
      dev.log("Error $e", name: "log.Test.getContentFromMessage");
      return "";
    }
  }
}
