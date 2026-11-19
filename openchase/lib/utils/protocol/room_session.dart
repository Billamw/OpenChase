import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The room the app is currently in, persisted on the device (localStorage on
/// web) so a page reload can resume the session instead of dropping to the
/// landing page. Stores the player session privkey so identity (pubkey) and
/// encrypted targeted publishes survive the reload. Never store this elsewhere:
/// it is the player's signing/decryption key for the room.
class RoomSession {
  static const _key = 'openchase.session.v1';

  final bool host;
  final String code; // 5-letter share code
  final String name;
  final String playerPrivkey; // 64-char hex session key

  RoomSession({
    required this.host,
    required this.code,
    required this.name,
    required this.playerPrivkey,
  });

  static bool _disabled = false;

  /// SharedPrefs is unavailable under `flutter test` (no plugin) — swallow
  /// errors so protocol tests stay pure.
  static Future<void> save(RoomSession s) async {
    if (_disabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'host': s.host,
          'code': s.code,
          'name': s.name,
          'priv': s.playerPrivkey,
        }),
      );
    } catch (_) {
      _disabled = true;
    }
  }

  static Future<RoomSession?> load() async {
    if (_disabled) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final code = m['code'] as String;
      final priv = m['priv'] as String;
      if (code.length != 5 || priv.length != 64) return null;
      return RoomSession(
        host: m['host'] as bool? ?? false,
        code: code,
        name: m['name'] as String? ?? '',
        playerPrivkey: priv,
      );
    } catch (_) {
      _disabled = true;
      return null;
    }
  }

  static Future<void> clear() async {
    if (_disabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      _disabled = true;
    }
  }
}
