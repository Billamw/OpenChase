import 'package:nostr/nostr.dart';

class NostrSettings {
  static const String initialPublicKey =
      "b32dfd2fecc15b89e20bc819241cfd4f60606143bd72b4928bbb4f6d1d60f335";
  static const String initialPrivateKey =
      "fed429982fe5b5df232332650db1831796268d894e560ca0255a49ff60665e6f";
  static const String nostrRelay = "wss://relay.damus.io";

  static String roomPublicKey = "";
  static String roomPrivateKey = "";

  static String getSerializedRequest(String pubKey) {
    Request requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(authors: [pubKey], since: currentUnixTimestampSeconds() - 5 * 60),
    ]);
    return requestWithFilter.serialize();
  }
}
