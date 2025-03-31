import 'dart:convert';
import 'dart:developer' as dev;
import 'package:nostr/nostr.dart';

class NostrHelper {
  static const String initialPublicKey =
      "b32dfd2fecc15b89e20bc819241cfd4f60606143bd72b4928bbb4f6d1d60f335";
  static const String initialPrivateKey =
      "fed429982fe5b5df232332650db1831796268d894e560ca0255a49ff60665e6f";
  static const String nostrRelay = "wss://relay.damus.io";

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
