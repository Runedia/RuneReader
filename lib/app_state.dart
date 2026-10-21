import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'models/book.dart';
import 'models/reader_settings.dart';
import 'models/reader_theme.dart';
import 'services/font_service.dart';
import 'services/library_service.dart';
import 'services/storage.dart';

const _settingsKey = 'reader_settings';
const _themesKey = 'custom_themes';

/// Application-wide state: settings, themes, and the library.
class AppState extends ChangeNotifier {
  AppState({required this.store, required this.library, required this.fonts});

  final KeyValueStore store;
  final LibraryService library;
  final FontService fonts;

  ReaderSettings _settings = const ReaderSettings();
  List<ReaderTheme> _customThemes = [];
  List<LibraryEntry> _entries = [];
  Timer? _saveSettingsTimer;
  Timer? _saveLibraryTimer;

  ReaderSettings get settings => _settings;
  List<ReaderTheme> get customThemes => List.unmodifiable(_customThemes);
  List<ReaderTheme> get themes => [...builtInThemes, ..._customThemes];

  ReaderTheme get theme => themeById(_settings.themeId) ?? builtInThemes.first;

  ReaderTheme? themeById(String id) {
    for (final t in themes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Library entries, most recently used first.
  List<LibraryEntry> get entries {
    final list = [..._entries];
    list.sort((a, b) => (b.lastOpenedAt ?? b.addedAt)
        .compareTo(a.lastOpenedAt ?? a.addedAt));
    return list;
  }

  LibraryEntry? entryById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> load() async {
    final rawSettings = await store.getString(_settingsKey);
    if (rawSettings != null) {
      try {
        final json = jsonDecode(rawSettings);
        if (json is Map) {
          _settings = ReaderSettings.fromJson(json.cast<String, Object?>());
        }
      } on FormatException {
        // Keep defaults.
      }
    }
    final rawThemes = await store.getString(_themesKey);
    if (rawThemes != null) {
      try {
        final json = jsonDecode(rawThemes);
        if (json is List) {
          _customThemes = [
            for (final t in json)
              if (t is Map) ReaderTheme.fromJson(t.cast<String, Object?>()),
          ];
        }
      } on FormatException {
        _customThemes = [];
      }
    }
    _entries = await library.load();
    notifyListeners();
  }

  // ---- Settings -----------------------------------------------------------

  void updateSettings(ReaderSettings value) {
    _settings = value;
    notifyListeners();
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer =
        Timer(const Duration(milliseconds: 400), _persistSettings);
  }

  Future<void> _persistSettings() =>
      store.setString(_settingsKey, jsonEncode(_settings.toJson()));

  /// Applies typography from an imported theme file.
  void applyTypography(Map<String, Object?> json) =>
      updateSettings(_settings.mergeJson(json));

  // ---- Themes -------------------------------------------------------------

  void selectTheme(String id) {
    if (themeById(id) == null) return;
    updateSettings(_settings.copyWith(themeId: id));
  }

  String newThemeId() => 'custom_${library.newId()}';

  /// Adds or replaces a custom theme.
  Future<void> saveTheme(ReaderTheme theme) async {
    if (builtInThemes.any((t) => t.id == theme.id)) {
      throw ArgumentError('기본 테마는 수정할 수 없습니다');
    }
    final t = theme.copyWith(builtIn: false);
    final index = _customThemes.indexWhere((x) => x.id == t.id);
    if (index >= 0) {
      _customThemes[index] = t;
    } else {
      _customThemes.add(t);
    }
    notifyListeners();
    await _persistThemes();
  }

  Future<void> deleteTheme(String id) async {
    _customThemes.removeWhere((t) => t.id == id);
    if (_settings.themeId == id) {
      _settings = _settings.copyWith(themeId: builtInThemes.first.id);
      await _persistSettings();
    }
    notifyListeners();
    await _persistThemes();
  }

  /// Adds imported themes. Ids that clash with existing themes get a new
  /// id. Returns the themes as stored.
  Future<List<ReaderTheme>> importThemes(List<ReaderTheme> imported) async {
    final stored = <ReaderTheme>[];
    for (final t in imported) {
      final clash = themeById(t.id) != null;
      final theme = t.copyWith(id: clash ? newThemeId() : t.id, builtIn: false);
      _customThemes.add(theme);
      stored.add(theme);
    }
    notifyListeners();
    await _persistThemes();
    return stored;
  }

  Future<void> _persistThemes() => store.setString(
      _themesKey, jsonEncode([for (final t in _customThemes) t.toJson()]));

  // ---- Library ------------------------------------------------------------

  Future<void> addEntry(LibraryEntry entry) async {
    _entries.add(entry);
    notifyListeners();
    await library.save(_entries);
  }

  /// Updates an entry; disk writes are debounced.
  void updateEntry(LibraryEntry entry) {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    _entries[i] = entry;
    notifyListeners();
    _saveLibraryTimer?.cancel();
    _saveLibraryTimer = Timer(const Duration(milliseconds: 800), flush);
  }

  Future<void> removeEntry(LibraryEntry entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    notifyListeners();
    await library.save(_entries);
    await library.deleteFiles(entry);
  }

  /// Writes pending changes immediately.
  Future<void> flush() async {
    _saveLibraryTimer?.cancel();
    await library.save(_entries);
    if (_saveSettingsTimer?.isActive ?? false) {
      _saveSettingsTimer!.cancel();
      await _persistSettings();
    }
  }

  @override
  void dispose() {
    _saveSettingsTimer?.cancel();
    _saveLibraryTimer?.cancel();
    super.dispose();
  }
}

/// Exposes [AppState] to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Reads the state without subscribing to changes.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
