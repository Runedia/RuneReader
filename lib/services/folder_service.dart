import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/reader_settings.dart';
import 'library_service.dart';
import 'natural_sort.dart';

enum FileKind { directory, text, image, archive, other }

FileKind fileKindOf(String path) {
  final ext = p.extension(path).toLowerCase();
  if (textExtensions.contains(ext)) return FileKind.text;
  if (imageExtensions.contains(ext)) return FileKind.image;
  if (archiveExtensions.contains(ext)) return FileKind.archive;
  return FileKind.other;
}

class FolderItem {
  const FolderItem({
    required this.path,
    required this.kind,
    required this.size,
    required this.modified,
  });

  final String path;
  final FileKind kind;
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
  bool get isDirectory => kind == FileKind.directory;
}

/// Sorts folder items. Directories always come first; [descending] reverses
/// the order inside each group. Ties fall back to natural name order.
List<FolderItem> sortFolderItems(
  Iterable<FolderItem> items,
  FolderSort sort, {
  bool descending = false,
}) {
  int byName(FolderItem a, FolderItem b) => naturalCompare(a.name, b.name);
  int compare(FolderItem a, FolderItem b) {
    final c = switch (sort) {
      FolderSort.name => 0,
      FolderSort.modified => a.modified.compareTo(b.modified),
      FolderSort.size => a.size.compareTo(b.size),
      FolderSort.type => p
          .extension(a.name)
          .toLowerCase()
          .compareTo(p.extension(b.name).toLowerCase()),
    };
    final r = c != 0 ? c : byName(a, b);
    return descending ? -r : r;
  }

  final dirs = items.where((i) => i.isDirectory).toList()..sort(compare);
  final files = items.where((i) => !i.isDirectory).toList()..sort(compare);
  return [...dirs, ...files];
}

/// Lists readable entries of [dir]: subdirectories, text, image, and
/// archive files. Hidden entries (dot-prefixed) are skipped.
Future<List<FolderItem>> listFolder(
  String dir, {
  FolderSort sort = FolderSort.name,
  bool descending = false,
}) async {
  final out = <FolderItem>[];
  await for (final e in Directory(dir).list(followLinks: true)) {
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    try {
      final stat = await e.stat();
      if (stat.type == FileSystemEntityType.directory) {
        out.add(FolderItem(
            path: e.path,
            kind: FileKind.directory,
            size: 0,
            modified: stat.modified));
        continue;
      }
      final kind = fileKindOf(e.path);
      if (kind == FileKind.other) continue;
      out.add(FolderItem(
          path: e.path, kind: kind, size: stat.size, modified: stat.modified));
    } on FileSystemException {
      continue;
    }
  }
  return sortFolderItems(out, sort, descending: descending);
}

/// Path of the text file [delta] positions away from [path] in its folder,
/// using the folder sort order. Null when there is none.
Future<String?> neighborTextFile(
  String path,
  int delta, {
  FolderSort sort = FolderSort.name,
  bool descending = false,
}) async {
  final List<FolderItem> items;
  try {
    items = await listFolder(p.dirname(path),
        sort: sort, descending: descending);
  } on FileSystemException {
    return null;
  }
  final texts = items.where((i) => i.kind == FileKind.text).toList();
  final index = texts.indexWhere((i) => p.equals(i.path, path));
  if (index < 0) return null;
  final target = index + delta;
  if (target < 0 || target >= texts.length) return null;
  return texts[target].path;
}

/// Sorts library entries. Ties fall back to natural title order.
List<LibraryEntry> sortLibraryEntries(
  Iterable<LibraryEntry> entries,
  LibrarySort sort, {
  bool descending = true,
}) {
  int compare(LibraryEntry a, LibraryEntry b) {
    final c = switch (sort) {
      LibrarySort.recent =>
        (a.lastOpenedAt ?? a.addedAt).compareTo(b.lastOpenedAt ?? b.addedAt),
      LibrarySort.added => a.addedAt.compareTo(b.addedAt),
      LibrarySort.title => naturalCompare(a.title, b.title),
      LibrarySort.progress => a.progress.compareTo(b.progress),
    };
    final r = c != 0 ? c : naturalCompare(a.title, b.title);
    return descending ? -r : r;
  }

  return [...entries]..sort(compare);
}
