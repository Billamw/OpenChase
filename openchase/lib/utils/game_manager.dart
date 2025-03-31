class GameManager {
  static String roomPublicKey = "";
  static String roomPrivateKey = "";
  static String userName = "";
  static String roomHost = "";
  static String roomCode = "";
  static List players = [];

  static String gamePublicKey = "";
  static String gamePrivateKey = "";

  static void addPlayersWithoutDuplicates(List newPlayers) {
    players = {...players, ...newPlayers}.toList();
  }

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
