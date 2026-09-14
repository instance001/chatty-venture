import 'package:shared_preferences/shared_preferences.dart';

/// A player-facing style note layered over both narration lanes. It shapes
/// delivery, never the app-owned story packet or route reducer.
class NarratorStyleSettings {
  static const _key = 'narrator_style_note';

  Future<String> load() async =>
      (await SharedPreferences.getInstance()).getString(_key) ?? '';

  Future<void> save(String note) async {
    final value = note.trim();
    final preferences = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, value);
    }
  }
}
