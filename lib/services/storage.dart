import 'package:shared_preferences/shared_preferences.dart';

/// Minimal string key-value store so app state can be tested without
/// platform channels.
abstract interface class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPrefsStore implements KeyValueStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async =>
      values[key] = value;
}
