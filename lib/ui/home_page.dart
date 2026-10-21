import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/library_service.dart';
import 'folder_page.dart';
import 'font_page.dart';
import 'open_entry.dart';
import 'theme_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _busy = false;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'RuneReader' : '폴더'),
        actions: [
          if (_tab == 0)
            _SortMenu<LibrarySort>(
              values: LibrarySort.values,
              selected: s.librarySort,
              descending: s.librarySortDescending,
              label: (v) => v.label,
              onSelected: (v) =>
                  state.updateSettings(s.copyWith(librarySort: v)),
              onDescending: (v) =>
                  state.updateSettings(s.copyWith(librarySortDescending: v)),
            )
          else
            _SortMenu<FolderSort>(
              values: FolderSort.values,
              selected: s.folderSort,
              descending: s.folderSortDescending,
              label: (v) => v.label,
              onSelected: (v) =>
                  state.updateSettings(s.copyWith(folderSort: v)),
              onDescending: (v) =>
                  state.updateSettings(s.copyWith(folderSortDescending: v)),
            ),
          IconButton(
            tooltip: '테마',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ThemePage())),
          ),
          IconButton(
            tooltip: '글꼴',
            icon: const Icon(Icons.font_download_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FontPage())),
          ),
        ],
      ),
      body: _tab == 0 ? _buildLibrary(state) : const FolderBrowser(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.local_library_outlined),
              selectedIcon: Icon(Icons.local_library),
              label: '서재'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '폴더'),
        ],
      ),
      floatingActionButton: _tab != 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _showOpenMenu,
              icon: const Icon(Icons.add),
              label: const Text('가져오기'),
            ),
    );
  }

  Widget _buildLibrary(AppState state) {
    final theme = state.theme;
    final entries = state.entries;
    return Stack(
        children: [
          if (entries.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '서재가 비어 있습니다.\n가져오기 버튼이나 폴더 탭에서 파일을 여세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.text.withValues(alpha: 0.7)),
                ),
              ),
            )
          else
            ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: entries.length,
              separatorBuilder: (_, _) => Divider(
                  height: 1, color: theme.text.withValues(alpha: 0.1)),
              itemBuilder: (context, i) => _EntryTile(
                entry: entries[i],
                onOpen: () => _open(entries[i]),
                onDelete: () => _confirmDelete(entries[i]),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      );
  }

  void _showOpenMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('텍스트 파일 (TXT)'),
              onTap: () {
                Navigator.pop(context);
                _importText();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('이미지 (여러 장 선택 가능)'),
              onTap: () {
                Navigator.pop(context);
                _importImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('압축 이미지 (ZIP / CBZ)'),
              onTap: () {
                Navigator.pop(context);
                _importArchive();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<LibraryEntry?> Function() task) async {
    setState(() => _busy = true);
    LibraryEntry? entry;
    try {
      entry = await task();
    } catch (e) {
      _snack('파일을 가져오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (entry != null && mounted) _open(entry);
  }

  Future<void> _importText() => _run(() async {
        final state = AppScope.read(context);
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['txt'],
        );
        if (files.isEmpty) return null;
        LibraryEntry? first;
        for (final f in files) {
          final entry = await state.library
              .importFile(f.name, f.readAsByteStream(), BookKind.text);
          await state.addEntry(entry);
          first ??= entry;
        }
        return first;
      });

  Future<void> _importImages() => _run(() async {
        final state = AppScope.read(context);
        final files = await FilePicker.pickFiles(type: FileType.image);
        final images = files.where((f) => isImageName(f.name)).toList();
        if (images.isEmpty) return null;
        final title = images.length == 1
            ? p.basenameWithoutExtension(images.first.name)
            : '${p.basenameWithoutExtension(images.first.name)} 외 ${images.length - 1}장';
        final entry = await state.library.importImages(title, [
          for (final f in images) (name: f.name, data: f.readAsByteStream()),
        ]);
        await state.addEntry(entry);
        return entry;
      });

  Future<void> _importArchive() => _run(() async {
        final state = AppScope.read(context);
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['zip', 'cbz'],
        );
        if (files.isEmpty) return null;
        LibraryEntry? first;
        for (final f in files) {
          final entry = await state.library
              .importFile(f.name, f.readAsByteStream(), BookKind.archive);
          await state.addEntry(entry);
          first ??= entry;
        }
        return first;
      });

  void _open(LibraryEntry entry) => openEntry(context, entry);

  Future<void> _confirmDelete(LibraryEntry entry) async {
    final external = AppScope.read(context).isExternal(entry);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('서재에서 삭제'),
        content: Text('"${entry.title}"을(를) 서재에서 삭제합니다.\n'
            '${external ? '읽은 위치·북마크만 지워지고 폴더의 파일은 유지됩니다.' : '앱에 복사된 파일도 삭제되며 원본 파일은 유지됩니다.'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.read(context).removeEntry(entry);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SortMenu<T> extends StatelessWidget {
  const _SortMenu({
    required this.values,
    required this.selected,
    required this.descending,
    required this.label,
    required this.onSelected,
    required this.onDescending,
  });

  final List<T> values;
  final T selected;
  final bool descending;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final ValueChanged<bool> onDescending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: '정렬',
      icon: const Icon(Icons.sort),
      onSelected: (v) {
        if (v == #descending) {
          onDescending(!descending);
        } else {
          onSelected(v as T);
        }
      },
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<Object>(
            value: v,
            checked: v == selected,
            child: Text(label(v)),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: #descending,
          checked: descending,
          child: const Text('내림차순'),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    final icon = switch (entry.kind) {
      BookKind.text => Icons.description_outlined,
      BookKind.images => Icons.photo_library_outlined,
      BookKind.archive => Icons.folder_zip_outlined,
    };
    final last = entry.lastOpenedAt;
    final subtitle = [
      '${(entry.progress * 100).toStringAsFixed(1)}%',
      if (last != null)
        '${last.year}.${last.month.toString().padLeft(2, '0')}.${last.day.toString().padLeft(2, '0')}',
    ].join(' · ');
    return ListTile(
      leading: Icon(icon, color: theme.accent),
      title: Text(entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.text)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: entry.progress,
              minHeight: 3,
              color: theme.accent,
              backgroundColor: theme.text.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(color: theme.text.withValues(alpha: 0.6))),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        iconColor: theme.text,
        onSelected: (v) {
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'delete', child: Text('서재에서 삭제')),
        ],
      ),
      onTap: onOpen,
    );
  }
}
