class NostrSettings {
  static const String initialPublicKey =
      "b32dfd2fecc15b89e20bc819241cfd4f60606143bd72b4928bbb4f6d1d60f335";
  static const String initialPrivateKey =
      "fed429982fe5b5df232332650db1831796268d894e560ca0255a49ff60665e6f";
  static const String nostrRelay = "wss://relay.damus.io";

  static String roomPublicKey = "";
  static String roomPrivateKey = "";
  static String userName = "";
  static String roomHost = "";
  static String roomCode = "";
  static List players = [];

  static String gamePublicKey = "";
  static String gamePrivateKey = "";

  static void removeAllData() {
    roomPublicKey = "";
    roomPrivateKey = "";
    userName = "";
    roomHost = "";
    roomCode = "";
    players = [];

    gamePublicKey = "";
    gamePrivateKey = "";
  }

  static String getFormattedRoomInfo() {
    return '''
{
  "roomPublicKey": "$roomPublicKey",
  "roomPrivateKey": "$roomPrivateKey",
  "userName": "$userName",
  "roomHost": "$roomHost",
  "roomCode": "$roomCode",
  "players": ${players.toString()}
}
''';
  }
}
