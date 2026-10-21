import 'dart:convert';

import '../models/reader_theme.dart';

const themeFileFormat = 'rune-reader-theme';
const themeFileVersion = 1;

/// Contents of an exported theme file.
class ThemeBundle {
  const ThemeBundle(this.themes, {this.typography});

  final List<ReaderTheme> themes;

  /// Optional text settings (see `ReaderSettings.typographyJson`).
  final Map<String, Object?>? typography;
}

String encodeThemeBundle(ThemeBundle bundle) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': themeFileFormat,
    'version': themeFileVersion,
    'themes': [for (final t in bundle.themes) t.toJson()],
    if (bundle.typography != null) 'typography': bundle.typography,
  });
}

/// Parses a theme file. Accepts a bundle, a bare theme object, or a list of
/// theme objects.
ThemeBundle decodeThemeBundle(String source) {
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException {
    throw const FormatException('JSON 형식이 아닙니다');
  }
  if (json is List) {
    return ThemeBundle(_parseThemes(json));
  }
  if (json is! Map) {
    throw const FormatException('테마 파일 형식이 아닙니다');
  }
  final map = json.cast<String, Object?>();
  if (map.containsKey('themes')) {
    final format = map['format'];
    if (format != null && format != themeFileFormat) {
      throw FormatException('지원하지 않는 형식: $format');
    }
    final version = map['version'];
    if (version is int && version > themeFileVersion) {
      throw FormatException('더 새로운 버전의 테마 파일입니다 (v$version)');
    }
    final themes = map['themes'];
    if (themes is! List) {
      throw const FormatException('themes 목록이 없습니다');
    }
    final typography = map['typography'];
    return ThemeBundle(
      _parseThemes(themes),
      typography: typography is Map ? typography.cast<String, Object?>() : null,
    );
  }
  return ThemeBundle([ReaderTheme.fromJson(map)]);
}

List<ReaderTheme> _parseThemes(List<Object?> list) {
  final out = <ReaderTheme>[];
  for (final item in list) {
    if (item is! Map) throw const FormatException('잘못된 테마 항목');
    out.add(ReaderTheme.fromJson(item.cast<String, Object?>()));
  }
  if (out.isEmpty) throw const FormatException('테마가 비어 있습니다');
  return out;
}
