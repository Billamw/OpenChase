import 'package:latlong2/latlong.dart';
import 'package:openchase/utils/protocol/room_client.dart';

class GameManager {
  /// Live protocol client, shared across the room flow (lobby → setup → game).
  static RoomClient? roomClient;

  /// Feed the host-side round settings (items v1) into the protocol client.
  /// Call once after creating the host RoomClient.
  static void initRoundSettingsProvider() {
    RoomClient.settingsProvider = () => (
      density: roundDensity,
      bankCap: roundBankCap,
      headStartMin: roundHeadStartMin,
    );
  }

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

  // Round settings chosen by the host (items v1). Values ride to the host's
  // round-start publish once the protocol carries them (backend).
  static int roundBankCap = 3;
  static String roundDensity = 'normal'; // less | normal | more
  static int roundHeadStartMin = 5;

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
