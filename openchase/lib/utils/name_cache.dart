import 'package:shared_preferences/shared_preferences.dart';
import 'package:openchase/utils/game_manager.dart';

/// Player name persisted across sessions (localStorage on web, prefs native).
class NameCache {
  static const _key = 'openchase.player_name';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key) ?? '';
    GameManager.userName = name;
    return name;
  }

  static Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name.trim());
    GameManager.userName = name.trim();
  }
}
