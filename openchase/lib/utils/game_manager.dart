import 'package:latlong2/latlong.dart';
import 'package:openchase/utils/protocol/room_client.dart';

class GameManager {
  /// Live protocol client, shared across the room flow (lobby → setup → game).
  static RoomClient? roomClient;

  static String roomCode = "";
  static String roomHost = "";
  static String userName = "";
  static List players = [];

  /// Round parameters as received/published via round_start.
  static LatLng? roundCenter;
  static int roundRadius = 0;

  /// Host-chosen round settings (round settings screen).
  static int roundDurationMin = 30;
  static Set<String> roundHiders = {};

  static void addPlayersWithoutDuplicates(List newPlayers) {
    players = {...players, ...newPlayers}.toList();
  }

  static void removeAllData() {
    roomClient?.close();
    roomClient = null;
    roomCode = "";
    roomHost = "";
    userName = "";
    players = [];
    roundCenter = null;
    roundRadius = 0;
  }
}
