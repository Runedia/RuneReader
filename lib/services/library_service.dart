import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/book.dart';

const imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
const archiveExtensions = {'.zip', '.cbz'};
const textExtensions = {'.txt', '.text', '.log', '.md'};

bool isImageName(String name) =>
    imageExtensions.contains(p.extension(name).toLowerCase());

/// Imported files live under [root]; the index is `library.json`.
class LibraryService {
  LibraryService(this.root);

  final Directory root;
  final _random = Random();

  File get _indexFile => File(p.join(root.path, 'library.json'));

  Future<List<LibraryEntry>> load() async {
    final f = _indexFile;
    if (!await f.exists()) return [];
    try {
      final json = jsonDecode(await f.readAsString());
      if (json is! List) return [];
      return [
        for (final e in json)
          if (e is Map) LibraryEntry.fromJson(e.cast<String, Object?>()),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<LibraryEntry> entries) async {
    await root.create(recursive: true);
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(
        jsonEncode([for (final e in entries) e.toJson()]),
        flush: true);
    await tmp.rename(_indexFile.path);
  }

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';

  Future<LibraryEntry> importFile(
    String fileName,
    Stream<List<int>> data,
    BookKind kind,
  ) async {
    final id = newId();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, _safeName(fileName)));
    await _write(target, data);
    return LibraryEntry(
      id: id,
      title: p.basenameWithoutExtension(fileName),
      kind: kind,
      path: target.path,
      addedAt: DateTime.now(),
    );
  }

  /// Copies several images into one directory to view them as a set.
  Future<LibraryEntry> importImages(
    String title,
    List<({String name, Stream<List<int>> data})> files,
  ) async {
    final id = newId();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    final used = <String>{};
    for (final f in files) {
      var name = _safeName(f.name);
      var n = 1;
      while (!used.add(name.toLowerCase())) {
        name = '${p.basenameWithoutExtension(f.name)}_$n${p.extension(f.name)}';
        n++;
      }
      await _write(File(p.join(dir.path, name)), f.data);
    }
    return LibraryEntry(
      id: id,
      title: title,
      kind: BookKind.images,
      path: dir.path,
      addedAt: DateTime.now(),
    );
  }

  /// Deletes the entry's copied files. Only paths inside [root] are touched.
  Future<void> deleteFiles(LibraryEntry entry) async {
    final dir = Directory(p.join(root.path, entry.id));
    if (p.isWithin(root.path, dir.path) && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Writes [data] to [file]. `Stream<Uint8List>.pipe(IOSink)` fails a
  /// runtime type check, so the sink consumes the stream via `addStream`.
  static Future<void> _write(File file, Stream<List<int>> data) async {
    final sink = file.openWrite();
    try {
      await sink.addStream(data);
    } finally {
      await sink.close();
    }
  }

  static String _safeName(String name) {
    final base = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return base.isEmpty ? 'file' : base;
  }
}
