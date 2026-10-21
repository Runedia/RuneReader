import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rune_reader/models/book.dart';
import 'package:rune_reader/models/reader_settings.dart';
import 'package:rune_reader/models/reader_theme.dart';
import 'package:rune_reader/services/theme_io.dart';

void main() {
  const custom = ReaderTheme(
    id: 'custom_1',
    name: '나의 테마',
    background: Color(0xFF101820),
    text: Color(0xFFFEE715),
    accent: Color(0x80FF0000),
    dark: true,
  );

  group('colors', () {
    test('hex round-trip and short forms', () {
      expect(colorToHex(const Color(0x80FF0000)), '#80FF0000');
      expect(colorFromHex('#80FF0000'), const Color(0x80FF0000));
      expect(colorFromHex('ff0000'), const Color(0xFFFF0000));
      expect(colorFromHex('#abc'), const Color(0xFFAABBCC));
      expect(() => colorFromHex('#12345'), throwsFormatException);
      expect(() => colorFromHex('zzzzzz'), throwsFormatException);
    });
  });

  group('theme bundle', () {
    test('export/import round-trip with typography', () {
      const settings = ReaderSettings(fontSize: 22, scaleX: 0.9);
      final json = encodeThemeBundle(
          ThemeBundle([custom], typography: settings.typographyJson()));
      final decoded = decodeThemeBundle(json);
      expect(decoded.themes, [custom]);
      expect(decoded.typography!['fontSize'], 22);
      expect(decoded.typography!['scaleX'], 0.9);
      expect(jsonDecode(json)['format'], themeFileFormat);
    });

    test('built-in flag is never imported', () {
      final json = encodeThemeBundle(ThemeBundle([builtInThemes.first]));
      expect(decodeThemeBundle(json).themes.single.builtIn, isFalse);
    });

    test('accepts a bare theme object and a list', () {
      final one = jsonEncode(custom.toJson());
      expect(decodeThemeBundle(one).themes.single, custom);
      final list = jsonEncode([custom.toJson(), custom.toJson()]);
      expect(decodeThemeBundle(list).themes, hasLength(2));
    });

    test('rejects invalid files', () {
      expect(() => decodeThemeBundle('not json'), throwsFormatException);
      expect(() => decodeThemeBundle('{"themes": []}'), throwsFormatException);
      expect(() => decodeThemeBundle('{"format":"other","themes":[]}'),
          throwsFormatException);
      expect(
          () => decodeThemeBundle(
              '{"format":"rune-reader-theme","version":99,"themes":[]}'),
          throwsFormatException);
      expect(() => decodeThemeBundle('{"id":"x","name":"y","background":"#000"}'),
          throwsFormatException); // text color missing
    });

    test('built-in theme ids are unique', () {
      final ids = builtInThemes.map((t) => t.id).toSet();
      expect(ids.length, builtInThemes.length);
      expect(ids, containsAll(['light', 'dark']));
    });
  });

  group('ReaderSettings', () {
    test('JSON round-trip', () {
      const s = ReaderSettings(
        fontId: 'user:My.ttf',
        fontSize: 20,
        fontWeight: 700,
        scaleX: 0.85,
        letterSpacing: 1.5,
        lineHeight: 1.9,
        paragraphSpacing: 12,
        indent: 1,
        textAlign: ReaderTextAlign.left,
        readingMode: ReadingMode.scroll,
        themeId: 'sepia',
        volumeKeyPaging: true,
        imageFit: ImageFit.fitWidth,
      );
      final back = ReaderSettings.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(back.toJson(), s.toJson());
      expect(back.layoutKey, s.layoutKey);
    });

    test('out-of-range and invalid values are clamped or ignored', () {
      final s = ReaderSettings.fromJson({
        'fontSize': 999,
        'scaleX': 0.01,
        'fontWeight': 1234,
        'textAlign': 'diagonal',
        'keepScreenOn': 'yes',
      });
      expect(s.fontSize, ReaderSettings.maxFontSize);
      expect(s.scaleX, ReaderSettings.minScaleX);
      expect(s.fontWeight, 900);
      expect(s.textAlign, const ReaderSettings().textAlign);
      expect(s.keepScreenOn, const ReaderSettings().keepScreenOn);
    });
  });

  test('LibraryEntry JSON round-trip', () {
    final e = LibraryEntry(
      id: 'abc',
      title: '책',
      kind: BookKind.archive,
      path: '/x/abc/book.cbz',
      addedAt: DateTime.utc(2026, 10, 21),
      lastOpenedAt: DateTime.utc(2026, 10, 22),
      progress: 0.5,
      position: const ReadingPosition(3, 7),
      encoding: 'cp949',
      bookmarks: [
        Bookmark(
            position: const ReadingPosition(1, 2),
            label: 'mark',
            createdAt: DateTime.utc(2026, 10, 21)),
      ],
    );
    final back = LibraryEntry.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>);
    expect(back.toJson(), e.toJson());
  });
}
