import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rune_reader/app_state.dart';
import 'package:rune_reader/models/book.dart';
import 'package:rune_reader/models/reader_settings.dart';
import 'package:rune_reader/services/folder_service.dart';
import 'package:rune_reader/services/font_service.dart';
import 'package:rune_reader/services/library_service.dart';
import 'package:rune_reader/services/storage.dart';

FolderItem item(String name, {bool dir = false, int size = 0, int day = 1}) =>
    FolderItem(
      path: '/x/$name',
      kind: dir ? FileKind.directory : fileKindOf(name),
      size: size,
      modified: DateTime(2026, 1, day),
    );

List<String> names(List<FolderItem> items) => [for (final i in items) i.name];

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('rr_folder_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String rel, [String content = 'x']) {
    final f = File(p.join(tmp.path, rel))..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  group('sortFolderItems', () {
    final items = [
      item('b10.txt', size: 5, day: 3),
      item('zdir', dir: true, day: 1),
      item('b2.txt', size: 50, day: 1),
      item('a.zip', size: 10, day: 2),
      item('adir', dir: true, day: 5),
    ];

    test('name: directories first, natural order', () {
      expect(names(sortFolderItems(items, FolderSort.name)),
          ['adir', 'zdir', 'a.zip', 'b2.txt', 'b10.txt']);
    });

    test('name descending keeps directories first', () {
      expect(names(sortFolderItems(items, FolderSort.name, descending: true)),
          ['zdir', 'adir', 'b10.txt', 'b2.txt', 'a.zip']);
    });

    test('modified, size, and type', () {
      expect(names(sortFolderItems(items, FolderSort.modified)),
          ['zdir', 'adir', 'b2.txt', 'a.zip', 'b10.txt']);
      expect(names(sortFolderItems(items, FolderSort.size, descending: true)),
          ['zdir', 'adir', 'b2.txt', 'a.zip', 'b10.txt']);
      expect(names(sortFolderItems(items, FolderSort.type)),
          ['adir', 'zdir', 'b2.txt', 'b10.txt', 'a.zip']);
    });
  });

  test('listFolder skips hidden and unsupported files', () async {
    write('1화.txt');
    write('.hidden.txt');
    write('cover.jpg');
    write('book.cbz');
    write('notes.pdf');
    Directory(p.join(tmp.path, 'sub')).createSync();
    Directory(p.join(tmp.path, '.git')).createSync();
    final list = await listFolder(tmp.path);
    expect(names(list), ['sub', '1화.txt', 'book.cbz', 'cover.jpg']);
  });

  test('neighborTextFile walks text files in folder order', () async {
    final a = write('ep1.txt');
    final b = write('ep2.txt');
    write('ep2.jpg');
    final c = write('ep10.txt');
    expect(await neighborTextFile(a.path, 1), b.path);
    expect(await neighborTextFile(b.path, 1), c.path);
    expect(await neighborTextFile(c.path, 1), isNull);
    expect(await neighborTextFile(a.path, -1), isNull);
    expect(await neighborTextFile(c.path, -1), b.path);
    // Descending order reverses the direction.
    expect(await neighborTextFile(c.path, 1, descending: true), b.path);
  });

  test('sortLibraryEntries', () {
    LibraryEntry e(String title, int added, double progress, [int? opened]) =>
        LibraryEntry(
          id: title,
          title: title,
          kind: BookKind.text,
          path: '/$title',
          addedAt: DateTime(2026, 1, added),
          lastOpenedAt: opened == null ? null : DateTime(2026, 2, opened),
          progress: progress,
        );
    final list = [e('b', 1, 0.5, 3), e('a10', 2, 0.1), e('a2', 3, 0.9, 1)];
    List<String> t(List<LibraryEntry> l) => [for (final x in l) x.title];
    expect(t(sortLibraryEntries(list, LibrarySort.recent)), ['b', 'a2', 'a10']);
    expect(t(sortLibraryEntries(list, LibrarySort.added)), ['a2', 'a10', 'b']);
    expect(t(sortLibraryEntries(list, LibrarySort.title, descending: false)),
        ['a2', 'a10', 'b']);
    expect(t(sortLibraryEntries(list, LibrarySort.progress)),
        ['a2', 'b', 'a10']);
  });

  group('AppState folders', () {
    late AppState state;
    setUp(() async {
      state = AppState(
        store: MemoryStore(),
        library: LibraryService(Directory(p.join(tmp.path, 'library'))),
        fonts: FontService(Directory(p.join(tmp.path, 'fonts')),
            systemFontDirs: const []),
      );
      await state.load();
    });

    test('defaults: scroll mode, volume paging, auto next file', () {
      expect(state.settings.readingMode, ReadingMode.scroll);
      expect(state.settings.volumeKeyPaging, isTrue);
      expect(state.settings.autoNextFile, isTrue);
    });

    test('entryForPath is idempotent and does not copy', () async {
      final f = write('novels/a.txt', '본문');
      final e1 = await state.entryForPath(f.path, BookKind.text);
      final e2 = await state.entryForPath(f.path, BookKind.text);
      expect(e1.id, e2.id);
      expect(e1.path, f.path);
      expect(state.isExternal(e1), isTrue);
      await state.removeEntry(e1);
      expect(f.existsSync(), isTrue, reason: 'external file must survive');
    });

    test('neighborText: external files use the folder', () async {
      final a = write('novels/01.txt');
      final b = write('novels/02.txt');
      final ea = await state.entryForPath(a.path, BookKind.text);
      final next = await state.neighborText(ea, 1);
      expect(p.equals(next!.path, b.path), isTrue);
      expect(await state.neighborText(next, 1), isNull);
      expect((await state.neighborText(next, -1))!.id, ea.id);
    });

    test('neighborText: imported files use library order', () async {
      Future<LibraryEntry> imp(String name) async {
        final e = await state.library
            .importFile(name, Stream.value(utf8.encode(name)), BookKind.text);
        await state.addEntry(e);
        return e;
      }

      final x = await imp('x.txt');
      final y = await imp('y.txt');
      state.updateSettings(state.settings
          .copyWith(librarySort: LibrarySort.title, librarySortDescending: false));
      expect((await state.neighborText(x, 1))!.id, y.id);
      expect(await state.neighborText(y, 1), isNull);
      await state.flush();
    });

    test('register, unregister, and current folder persist', () async {
      state.registerFolder('/storage/emulated/0/Novels');
      state.registerFolder('/storage/emulated/0/Novels'); // no duplicate
      state.setCurrentFolder('/storage/emulated/0/Novels/A');
      expect(state.settings.registeredFolders, ['/storage/emulated/0/Novels']);
      final json = state.settings.toJson();
      final back = ReaderSettings.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, Object?>);
      expect(back.registeredFolders, ['/storage/emulated/0/Novels']);
      expect(back.currentFolder, '/storage/emulated/0/Novels/A');
      state.unregisterFolder('/storage/emulated/0/Novels');
      expect(state.settings.registeredFolders, isEmpty);
      await state.flush();
    });
  });
}
