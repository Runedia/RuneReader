import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/folder_service.dart';
import '../services/natural_sort.dart';
import '../services/storage_access.dart';
import 'open_entry.dart';

/// Browses device storage from a working directory (the "current folder")
/// and opens text, image, and archive files in place.
class FolderBrowser extends StatefulWidget {
  const FolderBrowser({super.key});

  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<FolderBrowser>
    with WidgetsBindingObserver {
  bool? _access;
  List<String> _roots = const [];
  List<FolderItem> _items = const [];
  String? _error;
  bool _loading = false;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system permission screen.
    if (state == AppLifecycleState.resumed && _access != true) _init();
  }

  Future<void> _init() async {
    final access = await StorageAccess.hasAccess();
    final roots = await StorageAccess.roots();
    if (!mounted) return;
    setState(() {
      _access = access;
      _roots = roots.isEmpty ? const ['/storage/emulated/0'] : roots;
      _loadedKey = null;
    });
  }

  String _cwd(ReaderSettings s) {
    final current = s.currentFolder;
    if (current != null && Directory(current).existsSync()) return current;
    for (final f in s.registeredFolders) {
      if (Directory(f).existsSync()) return f;
    }
    return _roots.first;
  }

  Future<void> _load(String dir, ReaderSettings s, String key) async {
    setState(() {
      _loading = true;
      _loadedKey = key;
    });
    try {
      final items = await listFolder(dir,
          sort: s.folderSort, descending: s.folderSortDescending);
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _items = const [];
        _error = '폴더를 읽을 수 없습니다: ${e.osError?.message ?? e.message}';
        _loading = false;
      });
    }
  }

  bool _isRoot(String dir) => _roots.any((r) => p.equals(r, dir));

  String _label(String dir) {
    for (final r in _roots) {
      if (p.equals(r, dir)) {
        return r == _roots.first ? '내장 저장소' : 'SD (${p.basename(r)})';
      }
    }
    return p.basename(dir);
  }

  String _displayPath(String dir) {
    for (final r in _roots) {
      if (p.equals(r, dir) || p.isWithin(r, dir)) {
        final rel = p.relative(dir, from: r);
        return rel == '.' ? _label(r) : '${_label(r)}/$rel';
      }
    }
    return dir;
  }

  Future<void> _openItem(FolderItem item) async {
    final state = AppScope.read(context);
    switch (item.kind) {
      case FileKind.directory:
        state.setCurrentFolder(item.path);
        return;
      case FileKind.text:
        final entry = await state.entryForPath(item.path, BookKind.text);
        if (mounted) await openEntry(context, entry);
      case FileKind.archive:
        final entry = await state.entryForPath(item.path, BookKind.archive);
        if (mounted) await openEntry(context, entry);
      case FileKind.image:
        // Open the whole folder as an image set, starting at this image.
        final dir = p.dirname(item.path);
        final images = _items
            .where((i) => i.kind == FileKind.image)
            .map((i) => i.path)
            .toList()
          ..sort(naturalCompare);
        final index = images.indexWhere((x) => p.equals(x, item.path));
        var entry = await state.entryForPath(dir, BookKind.images);
        entry = entry.copyWith(
          position: ReadingPosition(index < 0 ? 0 : index),
          progress: images.length <= 1 ? 1 : index / (images.length - 1),
        );
        state.updateEntry(entry);
        if (mounted) await openEntry(context, entry);
      case FileKind.other:
        return;
    }
  }

  Future<void> _confirmUnregister(String folder) async {
    final state = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('폴더 등록 해제'),
        content: Text('"${p.basename(folder)}" 바로가기를 제거합니다.\n폴더와 파일은 삭제되지 않습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('해제')),
        ],
      ),
    );
    if (ok == true) state.unregisterFolder(folder);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = state.theme;
    final s = state.settings;
    final textColor = theme.text;

    if (_access == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_access == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 48, color: theme.accent),
              const SizedBox(height: 16),
              Text(
                '폴더의 TXT·이미지 파일을 직접 열려면\n"모든 파일 접근" 권한이 필요합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: StorageAccess.requestAccess,
                child: const Text('권한 설정 열기'),
              ),
            ],
          ),
        ),
      );
    }

    final cwd = _cwd(s);
    final key = '$cwd|${s.folderSort.name}|${s.folderSortDescending}';
    if (key != _loadedKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedKey != key) _load(cwd, s, key);
      });
    }
    final registered = state.isRegistered(cwd);
    final muted = textColor.withValues(alpha: 0.6);

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final r in _roots)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.phone_android, size: 18),
                    label: Text(_label(r)),
                    onPressed: () => state.setCurrentFolder(r),
                  ),
                ),
              for (final f in s.registeredFolders)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onLongPress: () => _confirmUnregister(f),
                    child: ActionChip(
                      avatar: const Icon(Icons.star, size: 18),
                      label: Text(p.basename(f)),
                      onPressed: () => state.setCurrentFolder(f),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Material(
          color: textColor.withValues(alpha: 0.05),
          child: Row(
            children: [
              IconButton(
                tooltip: '상위 폴더',
                icon: Icon(Icons.arrow_upward, color: textColor),
                onPressed: _isRoot(cwd)
                    ? null
                    : () => state.setCurrentFolder(p.dirname(cwd)),
              ),
              Expanded(
                child: Text(
                  _displayPath(cwd),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor),
                ),
              ),
              IconButton(
                tooltip: registered ? '폴더 등록 해제' : '이 폴더 등록',
                icon: Icon(registered ? Icons.star : Icons.star_outline,
                    color: registered ? theme.accent : textColor),
                onPressed: () => registered
                    ? state.unregisterFolder(cwd)
                    : state.registerFolder(cwd),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: TextStyle(color: textColor)),
                  ),
                )
              : _items.isEmpty && !_loading
                  ? Center(
                      child: Text('읽을 수 있는 파일이 없습니다',
                          style: TextStyle(color: muted)))
                  : RefreshIndicator(
                      onRefresh: () => _load(cwd, s, key),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _ItemTile(
                          item: _items[i],
                          entry: state.entryByPath(_items[i].path),
                          onTap: () => _openItem(_items[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.entry, required this.onTap});

  final FolderItem item;
  final LibraryEntry? entry;
  final VoidCallback onTap;

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    final icon = switch (item.kind) {
      FileKind.directory => Icons.folder,
      FileKind.text => Icons.description_outlined,
      FileKind.image => Icons.image_outlined,
      FileKind.archive => Icons.folder_zip_outlined,
      FileKind.other => Icons.insert_drive_file_outlined,
    };
    final e = entry;
    final subtitle = item.isDirectory
        ? _date(item.modified)
        : [
            _size(item.size),
            _date(item.modified),
            if (e != null && e.kind == BookKind.text)
              '${(e.progress * 100).toStringAsFixed(1)}%',
          ].join(' · ');
    return ListTile(
      leading: Icon(icon,
          color: item.isDirectory ? theme.accent : theme.text.withValues(alpha: 0.8)),
      title: Text(item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.text)),
      subtitle: Text(subtitle,
          style: TextStyle(color: theme.text.withValues(alpha: 0.6))),
      onTap: onTap,
    );
  }
}
