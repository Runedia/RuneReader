import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rune_reader/app_state.dart';
import 'package:rune_reader/models/book.dart';
import 'package:rune_reader/models/reader_theme.dart';
import 'package:rune_reader/services/font_service.dart';
import 'package:rune_reader/services/library_service.dart';
import 'package:rune_reader/services/storage.dart';

void main() {
  late Directory tmp;
  late MemoryStore store;

  AppState newState() => AppState(
        store: store,
        library: LibraryService(Directory(p.join(tmp.path, 'library'))),
        fonts: FontService(Directory(p.join(tmp.path, 'fonts')),
            systemFontDirs: const []),
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rr_state_');
    store = MemoryStore();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('settings and custom themes persist across instances', () async {
    final a = newState();
    await a.load();
    const theme = ReaderTheme(
      id: 'custom_x',
      name: 'X',
      background: Color(0xFF000001),
      text: Color(0xFFFFFFFE),
      accent: Color(0xFF00FF00),
      dark: true,
    );
    await a.saveTheme(theme);
    a.selectTheme('custom_x');
    a.updateSettings(a.settings.copyWith(fontSize: 25));
    await a.flush();

    final b = newState();
    await b.load();
    expect(b.theme, theme);
    expect(b.settings.fontSize, 25);
  });

  test('built-in themes cannot be overwritten', () async {
    final s = newState();
    await s.load();
    expect(() => s.saveTheme(builtInThemes.first), throwsArgumentError);
  });

  test('imported themes with clashing ids get new ids', () async {
    final s = newState();
    await s.load();
    final imported = await s.importThemes([
      builtInThemes[1].copyWith(name: '다크 사본'), // clashes with 'dark'
      const ReaderTheme(
        id: 'fresh',
        name: 'Fresh',
        background: Color(0xFFFFFFFF),
        text: Color(0xFF000000),
        accent: Color(0xFF000000),
        dark: false,
      ),
    ]);
    expect(imported[0].id, isNot('dark'));
    expect(imported[0].builtIn, isFalse);
    expect(imported[1].id, 'fresh');
    expect(s.themes.length, builtInThemes.length + 2);
    // Importing the same file again does not overwrite.
    final again = await s.importThemes([imported[1]]);
    expect(again.single.id, isNot('fresh'));
  });

  test('deleting the selected theme falls back to the default', () async {
    final s = newState();
    await s.load();
    final t = (await s.importThemes([builtInThemes[2]])).single;
    s.selectTheme(t.id);
    await s.deleteTheme(t.id);
    expect(s.theme.id, builtInThemes.first.id);
  });

  test('library import, update, reload, and delete', () async {
    final s = newState();
    await s.load();
    final entry = await s.library.importFile(
      '소설.txt',
      Stream.value(utf8.encode('본문')),
      BookKind.text,
    );
    await s.addEntry(entry);
    expect(File(entry.path).readAsStringSync(), '본문');
    expect(entry.title, '소설');

    s.updateEntry(entry.copyWith(
        progress: 0.25, position: const ReadingPosition(4, 2)));
    await s.flush();

    final reloaded = newState();
    await reloaded.load();
    final e = reloaded.entryById(entry.id)!;
    expect(e.progress, 0.25);
    expect(e.position, const ReadingPosition(4, 2));

    await reloaded.removeEntry(e);
    expect(reloaded.entries, isEmpty);
    expect(File(entry.path).existsSync(), isFalse);
  });

  test('imports from a Stream<Uint8List> like PlatformFile.readAsByteStream',
      () async {
    final s = newState();
    final Stream<Uint8List> data = Stream.fromIterable([
      Uint8List.fromList(utf8.encode('가나')),
      Uint8List.fromList(utf8.encode('다')),
    ]);
    final entry = await s.library.importFile('a.txt', data, BookKind.text);
    expect(File(entry.path).readAsStringSync(), '가나다');
    final set = await s.library.importImages('set', [
      (name: 'x.png', data: Stream.value(Uint8List.fromList([7]))),
    ]);
    expect(Directory(set.path).listSync(), hasLength(1));
  });

  test('image set import keeps every file even with duplicate names',
      () async {
    final s = newState();
    final entry = await s.library.importImages('set', [
      (name: '1.png', data: Stream.value([1])),
      (name: '1.png', data: Stream.value([2])),
      (name: '2.jpg', data: Stream.value([3])),
    ]);
    final files = Directory(entry.path).listSync().whereType<File>().toList();
    expect(files, hasLength(3));
  });

  group('FontService', () {
    final ttf = Uint8List.fromList([0, 1, 0, 0, ...List.filled(20, 0)]);
    final ttc = Uint8List.fromList([...'ttcf'.codeUnits, ...List.filled(20, 0)]);

    test('recognizes font magic numbers', () {
      expect(FontService.isFontData(ttf), isTrue);
      expect(FontService.isFontData(ttc), isTrue);
      expect(
          FontService.isFontData(
              Uint8List.fromList([...'OTTO'.codeUnits, ...List.filled(20, 0)])),
          isTrue);
      expect(FontService.isFontData(Uint8List.fromList(utf8.encode('hello world!!'))),
          isFalse);
    });

    test('imports, lists, and deletes user fonts', () async {
      final fonts = newState().fonts;
      await expectLater(fonts.importFont('bad.ttf', Uint8List(20)),
          throwsFormatException);
      final a = await fonts.importFont('My Font.ttf', ttf);
      final b = await fonts.importFont('My Font.ttf', ttf); // name clash
      final c = await fonts.importFont('Collection.ttc', ttc);
      expect(a.id, 'user:My Font.ttf');
      expect(b.id, isNot(a.id));
      expect(c.id, 'user:Collection.ttc');
      expect((await fonts.userFonts()).length, 3);
      expect(fonts.labelFor(c.id), 'Collection');
      await fonts.deleteUserFont(a);
      expect((await fonts.userFonts()).length, 2);
    });
  });
}
