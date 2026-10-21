import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/library_service.dart';
import '../services/natural_sort.dart';
import '../services/volume_keys.dart';
import 'reader_settings_sheet.dart';

/// A sequence of images loaded on demand.
abstract class ImageSequence {
  int get length;
  String nameAt(int index);
  Future<Uint8List> load(int index);
  void close() {}

  static Future<ImageSequence> open(LibraryEntry entry) async {
    if (entry.kind == BookKind.archive) {
      return ArchiveImageSequence.open(entry.path);
    }
    return DirectoryImageSequence.open(entry.path);
  }
}

class DirectoryImageSequence extends ImageSequence {
  DirectoryImageSequence(this.files);

  final List<File> files;

  static Future<DirectoryImageSequence> open(String path) async {
    final files = <File>[];
    await for (final f in Directory(path).list()) {
      if (f is File && isImageName(f.path)) files.add(f);
    }
    files.sort((a, b) => naturalCompare(a.path, b.path));
    return DirectoryImageSequence(files);
  }

  @override
  int get length => files.length;

  @override
  String nameAt(int index) => files[index].uri.pathSegments.last;

  @override
  Future<Uint8List> load(int index) => files[index].readAsBytes();
}

class ArchiveImageSequence extends ImageSequence {
  ArchiveImageSequence(this._input, this.files);

  final InputFileStream _input;
  final List<ArchiveFile> files;

  static Future<ArchiveImageSequence> open(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final files = archive.files
          .where((f) => f.isFile && isImageName(f.name))
          .where((f) => !f.name.split('/').any((s) => s.startsWith('.') || s == '__MACOSX'))
          .toList()
        ..sort((a, b) => naturalCompare(a.name, b.name));
      return ArchiveImageSequence(input, files);
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  @override
  int get length => files.length;

  @override
  String nameAt(int index) => files[index].name.split('/').last;

  @override
  Future<Uint8List> load(int index) async =>
      files[index].readBytes() ?? Uint8List(0);

  @override
  void close() {
    _input.close();
  }
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.entryId});

  final String entryId;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final AppState _state;
  ImageSequence? _images;
  String? _error;
  PageController? _controller;
  int _index = 0;
  bool _menu = false;
  bool? _volumeOn;
  bool? _wakelockOn;
  final _cache = <int, Future<Uint8List>>{}; // insertion-ordered: LRU

  @override
  void initState() {
    super.initState();
    _state = AppScope.read(context);
    _state.addListener(_onState);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _applySystem();
    _open();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _images?.close();
    _controller?.dispose();
    if (_volumeOn == true) VolumeKeys.disable();
    if (_wakelockOn == true) WakelockPlus.disable().catchError((Object _) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _state.flush();
    super.dispose();
  }

  Future<void> _open() async {
    final entry = _state.entryById(widget.entryId);
    if (entry == null) {
      setState(() => _error = '서재에서 항목을 찾을 수 없습니다');
      return;
    }
    try {
      final images = await ImageSequence.open(entry);
      if (!mounted) {
        images.close();
        return;
      }
      if (images.length == 0) {
        images.close();
        setState(() => _error = '표시할 이미지가 없습니다');
        return;
      }
      final start = entry.position.paragraph.clamp(0, images.length - 1);
      setState(() {
        _images = images;
        _index = start;
        _controller = PageController(initialPage: start);
      });
      _state.updateEntry(entry.copyWith(lastOpenedAt: DateTime.now()));
    } catch (e) {
      if (mounted) setState(() => _error = '열 수 없습니다: $e');
    }
  }

  void _onState() {
    if (!mounted) return;
    _applySystem();
    setState(() {});
  }

  void _applySystem() {
    final s = _state.settings;
    if (_wakelockOn != s.keepScreenOn) {
      _wakelockOn = s.keepScreenOn;
      WakelockPlus.toggle(enable: s.keepScreenOn).catchError((Object _) {});
    }
    if (_volumeOn != s.volumeKeyPaging) {
      _volumeOn = s.volumeKeyPaging;
      if (s.volumeKeyPaging) {
        VolumeKeys.enable((next) => _turn(next ? 1 : -1));
      } else {
        VolumeKeys.disable();
      }
    }
  }

  Future<Uint8List> _bytes(int index) {
    final hit = _cache.remove(index);
    final future = hit ?? _images!.load(index);
    _cache[index] = future;
    while (_cache.length > 6) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  void _onPageChanged(int index) {
    _index = index;
    final images = _images;
    final entry = _state.entryById(widget.entryId);
    if (images == null || entry == null) return;
    _state.updateEntry(entry.copyWith(
      position: ReadingPosition(index),
      progress: images.length <= 1 ? 1 : index / (images.length - 1),
      lastOpenedAt: DateTime.now(),
    ));
    setState(() {});
  }

  void _turn(int delta) {
    final images = _images;
    final controller = _controller;
    if (images == null || controller == null || !controller.hasClients) return;
    final target = (_index + delta).clamp(0, images.length - 1);
    if (target == _index) return;
    if (_state.settings.pageAnimation == PageAnimation.slide) {
      controller.animateToPage(target,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      controller.jumpToPage(target);
    }
  }

  void _onTap(Offset local, Size size) {
    if (_menu) {
      _toggleMenu();
      return;
    }
    final x = local.dx / size.width;
    final rtl = _state.settings.imageRightToLeft;
    if (x < 0.3) {
      _turn(rtl ? 1 : -1);
    } else if (x > 0.7) {
      _turn(rtl ? -1 : 1);
    } else {
      _toggleMenu();
    }
  }

  void _toggleMenu() {
    setState(() => _menu = !_menu);
    SystemChrome.setEnabledSystemUIMode(
        _menu ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _addBookmark() {
    final entry = _state.entryById(widget.entryId);
    final images = _images;
    if (entry == null || images == null) return;
    _state.updateEntry(entry.copyWith(bookmarks: [
      ...entry.bookmarks,
      Bookmark(
        position: ReadingPosition(_index),
        label: '${_index + 1}쪽 · ${images.nameAt(_index)}',
        createdAt: DateTime.now(),
      ),
    ]));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('북마크를 추가했습니다'), duration: Duration(seconds: 1)));
  }

  Future<void> _openBookmarks() async {
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = AppScope.of(context);
        final entry = state.entryById(widget.entryId);
        final marks = entry?.bookmarks ?? const <Bookmark>[];
        if (marks.isEmpty) {
          return const SizedBox(
              height: 160, child: Center(child: Text('북마크가 없습니다')));
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: marks.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(marks[i].label),
            onTap: () => Navigator.pop(context, marks[i].position.paragraph),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => state.updateEntry(
                  entry!.copyWith(bookmarks: [...marks]..removeAt(i))),
            ),
          ),
        );
      },
    );
    if (page != null) _controller?.jumpToPage(page);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = state.theme;
    final images = _images;
    final controller = _controller;
    if (_error != null || images == null || controller == null) {
      return Scaffold(
        backgroundColor: theme.background,
        body: Center(
          child: _error == null
              ? CircularProgressIndicator(color: theme.accent)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: TextStyle(color: theme.text)),
                    TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('돌아가기')),
                  ],
                ),
        ),
      );
    }
    final s = state.settings;
    final entry = state.entryById(widget.entryId);
    return Scaffold(
      backgroundColor: theme.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d.localPosition, size),
                  child: PageView.builder(
                    controller: controller,
                    reverse: s.imageRightToLeft,
                    itemCount: images.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) => _ImagePage(
                      bytes: _bytes(i),
                      fit: s.imageFit,
                      textColor: theme.text,
                    ),
                  ),
                ),
              ),
              if (_menu) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          const BackButton(),
                          Expanded(
                            child: Text(entry?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          IconButton(
                            tooltip: '북마크 목록',
                            icon: const Icon(Icons.bookmarks_outlined),
                            onPressed: _openBookmarks,
                          ),
                          IconButton(
                            tooltip: '북마크 추가',
                            icon: const Icon(Icons.bookmark_add_outlined),
                            onPressed: _addBookmark,
                          ),
                          IconButton(
                            tooltip: '설정',
                            icon: const Icon(Icons.tune),
                            onPressed: () => showReaderSettingsSheet(context,
                                imageMode: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: images.length > 1
                                  ? Slider(
                                      value: _index.toDouble(),
                                      max: (images.length - 1).toDouble(),
                                      divisions: images.length - 1,
                                      label: '${_index + 1}',
                                      onChanged: (v) =>
                                          controller.jumpToPage(v.round()),
                                    )
                                  : const SizedBox(height: 48),
                            ),
                            Text('${_index + 1} / ${images.length}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  const _ImagePage({
    required this.bytes,
    required this.fit,
    required this.textColor,
  });

  final Future<Uint8List> bytes;
  final ImageFit fit;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text('이미지를 읽을 수 없습니다',
                  style: TextStyle(color: textColor)));
        }
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        Widget errorBuilder(BuildContext c, Object e, StackTrace? s) => Center(
            child: Text('지원하지 않는 이미지 형식입니다',
                style: TextStyle(color: textColor)));
        switch (fit) {
          case ImageFit.contain:
            return InteractiveViewer(
              maxScale: 6,
              child: SizedBox.expand(
                child: Image.memory(data,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: errorBuilder),
              ),
            );
          case ImageFit.fitWidth:
            return SingleChildScrollView(
              child: Image.memory(data,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  errorBuilder: errorBuilder),
            );
          case ImageFit.fitHeight:
            return LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Image.memory(data,
                    height: c.maxHeight,
                    fit: BoxFit.fitHeight,
                    gaplessPlayback: true,
                    errorBuilder: errorBuilder),
              ),
            );
        }
      },
    );
  }
}
