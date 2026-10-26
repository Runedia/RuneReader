import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'models/book.dart';
import 'models/reader_settings.dart';
import 'models/reader_theme.dart';
import 'services/folder_service.dart';
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

  /// Library entries in the configured sort order.
  List<LibraryEntry> get entries => sortLibraryEntries(
        _entries,
        _settings.librarySort,
        descending: _settings.librarySortDescending,
      );

  /// Whether the entry refers to a file outside the app library (opened
  /// from the folder browser) rather than an imported copy.
  bool isExternal(LibraryEntry entry) =>
      !p.isWithin(library.root.path, entry.path);

  LibraryEntry? entryByPath(String path) {
    for (final e in _entries) {
      if (p.equals(e.path, path)) return e;
    }
    return null;
  }

  /// Returns the entry for a file or image folder opened in place,
  /// creating it when needed. The file is not copied.
  Future<LibraryEntry> entryForPath(String path, BookKind kind) async {
    final existing = entryByPath(path);
    if (existing != null) return existing;
    final entry = LibraryEntry(
      id: library.newId(),
      title: kind == BookKind.images
          ? p.basename(path)
          : p.basenameWithoutExtension(path),
      kind: kind,
      path: path,
      addedAt: DateTime.now(),
    );
    await addEntry(entry);
    return entry;
  }

  /// The text book [delta] positions away from [entry]: the neighboring
  /// text file in the same folder for external files, otherwise the
  /// neighboring text entry in library order.
  Future<LibraryEntry?> neighborText(LibraryEntry entry, int delta) async {
    if (isExternal(entry)) {
      final path = await neighborTextFile(
        entry.path,
        delta,
        sort: _settings.folderSort,
        descending: _settings.folderSortDescending,
      );
      return path == null ? null : entryForPath(path, BookKind.text);
    }
    final texts = entries
        .where((e) => e.kind == BookKind.text && !isExternal(e))
        .toList();
    final i = texts.indexWhere((e) => e.id == entry.id);
    if (i < 0) return null;
    final target = i + delta;
    if (target < 0 || target >= texts.length) return null;
    return texts[target];
  }

  // ---- Folders ------------------------------------------------------------

  void setCurrentFolder(String path) =>
      updateSettings(_settings.copyWith(currentFolder: path));

  bool isRegistered(String path) =>
      _settings.registeredFolders.any((f) => p.equals(f, path));

  void registerFolder(String path) {
    if (isRegistered(path)) return;
    updateSettings(_settings.copyWith(
        registeredFolders: [..._settings.registeredFolders, path]));
  }

  void unregisterFolder(String path) => updateSettings(_settings.copyWith(
      registeredFolders: [
        for (final f in _settings.registeredFolders)
          if (!p.equals(f, path)) f,
      ]));

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
  /// Replaces [entry] and schedules a save. Pass `notify: false` for
  /// high-frequency updates (reading position while scrolling), which would
  /// otherwise rebuild the whole app every frame.
  void updateEntry(LibraryEntry entry, {bool notify = true}) {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    _entries[i] = entry;
    if (notify) notifyListeners();
    _saveLibraryTimer?.cancel();
    _saveLibraryTimer = Timer(const Duration(milliseconds: 800), flush);
  }

  /// Notifies listeners after silent (`notify: false`) entry updates.
  void refresh() => notifyListeners();

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
