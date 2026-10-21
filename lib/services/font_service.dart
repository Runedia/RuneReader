import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

enum FontSource { builtIn, system, user }

class FontEntry {
  const FontEntry({
    required this.id,
    required this.label,
    required this.source,
    this.family,
    this.path,
  });

  /// Stable identifier stored in settings: `system`, `alias:<name>`,
  /// `sys:<file>`, or `user:<file>`.
  final String id;
  final String label;
  final FontSource source;

  /// Family name passed to [TextStyle.fontFamily]. For file fonts this is
  /// assigned when the file is loaded.
  final String? family;
  final String? path;
}

const _fontExtensions = {'.ttf', '.otf', '.ttc', '.otc'};

/// Lists, imports, and loads fonts.
///
/// Android exposes its bundled font families through aliases such as
/// `serif`; individual font files in `/system/fonts` are loaded on demand
/// with [FontLoader]. For TrueType/OpenType collections (`.ttc`) the engine
/// uses the first face in the collection.
class FontService {
  FontService(this.userFontDir, {List<String>? systemFontDirs})
      : systemFontDirs =
            systemFontDirs ?? const ['/system/fonts', '/product/fonts'];

  final Directory userFontDir;
  final List<String> systemFontDirs;

  static const builtIns = <FontEntry>[
    FontEntry(id: 'system', label: '시스템 기본', source: FontSource.builtIn),
    FontEntry(
        id: 'alias:sans-serif',
        label: '고딕 (sans-serif)',
        source: FontSource.builtIn,
        family: 'sans-serif'),
    FontEntry(
        id: 'alias:serif',
        label: '명조 (serif)',
        source: FontSource.builtIn,
        family: 'serif'),
    FontEntry(
        id: 'alias:monospace',
        label: '고정폭 (monospace)',
        source: FontSource.builtIn,
        family: 'monospace'),
    FontEntry(
        id: 'alias:sans-serif-condensed',
        label: '좁은 고딕 (condensed)',
        source: FontSource.builtIn,
        family: 'sans-serif-condensed'),
  ];

  final Map<String, String> _loaded = {};
  List<FontEntry>? _systemCache;

  Future<List<FontEntry>> systemFonts() async {
    final cached = _systemCache;
    if (cached != null) return cached;
    final out = <FontEntry>[];
    for (final dirPath in systemFontDirs) {
      final dir = Directory(dirPath);
      try {
        if (!await dir.exists()) continue;
        await for (final f in dir.list(followLinks: false)) {
          if (f is! File) continue;
          final ext = p.extension(f.path).toLowerCase();
          if (!_fontExtensions.contains(ext)) continue;
          final name = p.basename(f.path);
          out.add(FontEntry(
            id: 'sys:${f.path}',
            label: p.basenameWithoutExtension(name),
            source: FontSource.system,
            path: f.path,
          ));
        }
      } on FileSystemException {
        continue;
      }
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return _systemCache = out;
  }

  Future<List<FontEntry>> userFonts() async {
    if (!await userFontDir.exists()) return const [];
    final out = <FontEntry>[];
    await for (final f in userFontDir.list()) {
      if (f is! File) continue;
      if (!_fontExtensions.contains(p.extension(f.path).toLowerCase())) {
        continue;
      }
      out.add(FontEntry(
        id: 'user:${p.basename(f.path)}',
        label: p.basenameWithoutExtension(f.path),
        source: FontSource.user,
        path: f.path,
      ));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  /// Copies a font file into the user font directory.
  Future<FontEntry> importFont(String fileName, Uint8List bytes) async {
    if (!isFontData(bytes)) {
      throw const FormatException('TTF/OTF/TTC 글꼴 파일이 아닙니다');
    }
    await userFontDir.create(recursive: true);
    var name = p.basename(fileName);
    if (!_fontExtensions.contains(p.extension(name).toLowerCase())) {
      name = '$name${_extensionFor(bytes)}';
    }
    var target = File(p.join(userFontDir.path, name));
    var n = 1;
    while (await target.exists()) {
      target = File(p.join(userFontDir.path,
          '${p.basenameWithoutExtension(name)} ($n)${p.extension(name)}'));
      n++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return FontEntry(
      id: 'user:${p.basename(target.path)}',
      label: p.basenameWithoutExtension(target.path),
      source: FontSource.user,
      path: target.path,
    );
  }

  Future<void> deleteUserFont(FontEntry entry) async {
    if (entry.source != FontSource.user || entry.path == null) return;
    final f = File(entry.path!);
    if (p.isWithin(userFontDir.path, f.path) && await f.exists()) {
      await f.delete();
    }
  }

  /// Display label for a stored font id.
  String labelFor(String id) {
    for (final b in builtIns) {
      if (b.id == id) return b.label;
    }
    final colon = id.indexOf(':');
    if (colon < 0) return id;
    return p.basenameWithoutExtension(id.substring(colon + 1));
  }

  /// Returns the family name to use for [id], loading the file if needed.
  /// Returns null for the system default or when the font cannot be loaded.
  Future<String?> resolveFamily(String id) async {
    for (final b in builtIns) {
      if (b.id == id) return b.family;
    }
    final loaded = _loaded[id];
    if (loaded != null) return loaded;

    final String? path;
    if (id.startsWith('sys:')) {
      path = id.substring(4);
    } else if (id.startsWith('user:')) {
      path = p.join(userFontDir.path, id.substring(5));
    } else {
      path = null;
    }
    if (path == null) return null;
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (!isFontData(bytes)) return null;
      final family = 'rr_${_loaded.length}_${p.basenameWithoutExtension(path)}';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loaded[id] = family;
      return family;
    } on FileSystemException {
      return null;
    }
  }

  /// Checks the sfnt / collection magic number.
  static bool isFontData(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final tag = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return tag == 0x00010000 || // TrueType
        tag == 0x4F54544F || // 'OTTO'
        tag == 0x74727565 || // 'true'
        tag == 0x74746366; // 'ttcf'
  }

  static String _extensionFor(Uint8List bytes) {
    final tag = String.fromCharCodes(bytes.sublist(0, 4));
    if (tag == 'ttcf') return '.ttc';
    if (tag == 'OTTO') return '.otf';
    return '.ttf';
  }
}
