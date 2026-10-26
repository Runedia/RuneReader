import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../services/paginator.dart';
import '../services/text_decoder.dart';
import '../services/text_document.dart';
import '../services/toc.dart';
import '../services/volume_keys.dart';
import 'reader_settings_sheet.dart';

const _footerHeight = 22.0;

class _ParseArgs {
  const _ParseArgs(this.bytes, this.encoding, this.collapse, this.trim);
  final Uint8List bytes;
  final TextEncodingKind encoding;
  final bool collapse;
  final bool trim;
}

({List<String> paragraphs, TextEncodingKind encoding}) _parse(_ParseArgs a) {
  final decoded = decodeText(a.bytes, encoding: a.encoding);
  final doc = TextDocument.parse(decoded.text,
      collapseBlankLines: a.collapse, trimParagraphs: a.trim);
  return (paragraphs: doc.paragraphs, encoding: decoded.encoding);
}

class TextReaderPage extends StatefulWidget {
  const TextReaderPage({
    super.key,
    required this.entryId,
    this.startAtEnd = false,
  });

  final String entryId;

  /// Start at the end when the book has no saved progress (used when
  /// stepping back into the previous file).
  final bool startAtEnd;

  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  late final AppState _state;
  late LibraryEntry _entry;
  Uint8List? _bytes;
  TextEncodingKind _encoding = TextEncodingKind.auto;
  TextEncodingKind? _detected;
  TextDocument? _doc;
  List<TocEntry> _toc = const [];
  String? _error;
  String? _docSig;

  ReadingPosition _position = const ReadingPosition(0);
  final _positionNotifier = ValueNotifier(const ReadingPosition(0));

  // Font resolution.
  String? _fontId;
  String? _fontFamily;
  bool _fontReady = false;

  // Layout.
  String? _layoutSig;
  String? _renderSig;
  ReadingMode? _layoutMode;
  Size _contentSize = Size.zero;
  ParagraphLayoutCache? _renderCache;
  ParagraphLayoutCache? _measureCache;
  Paginator? _paginator;
  PageController? _pageController;
  int _pageIndex = 0;
  ReadingPosition? _pendingJump;
  Timer? _relayoutTimer;
  bool _forceLayout = false;
  DateTime _lastProgressBuild = DateTime(0);

  // Scroll mode.
  ItemScrollController _itemScroll = ItemScrollController();
  final _itemPositions = ItemPositionsListener.create();
  ScrollOffsetController _scrollOffset = ScrollOffsetController();

  // Chrome.
  bool _menu = false;
  bool? _wakelockOn;
  bool? _volumeOn;
  bool? _immersive;
  final _now = ValueNotifier(DateTime.now());
  Timer? _clock;

  ReaderSettings get _s => _state.settings;

  @override
  void initState() {
    super.initState();
    ReaderChrome.acquire();
    _state = AppScope.read(context);
    final entry = _state.entryById(widget.entryId);
    if (entry == null) {
      _error = '서재에서 항목을 찾을 수 없습니다';
      return;
    }
    _entry = entry;
    _position = entry.position;
    _positionNotifier.value = _position;
    _encoding = TextEncodingKind.byName(entry.encoding);
    _state.addListener(_onState);
    _itemPositions.itemPositions.addListener(_onScrollPositions);
    _clock = Timer.periodic(const Duration(seconds: 20),
        (_) => _now.value = DateTime.now());
    _applySystem();
    _resolveFont();
    _load();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _itemPositions.itemPositions.removeListener(_onScrollPositions);
    _clock?.cancel();
    _relayoutTimer?.cancel();
    _paginator?.cancel();
    _renderCache?.dispose();
    _measureCache?.dispose();
    _pageController?.dispose();
    _positionNotifier.dispose();
    _now.dispose();
    VolumeKeys.disable(this);
    ReaderChrome.release();
    _state.flush();
    // Position updates were silent; let the library list pick them up once.
    final state = _state;
    scheduleMicrotask(state.refresh);
    super.dispose();
  }

  static void _safe(Future<void> Function() action) {
    action().catchError((Object _) {});
  }

  // ---- Loading ------------------------------------------------------------

  Future<void> _load() async {
    try {
      _bytes = await File(_entry.path).readAsBytes();
      await _parseDocument();
      _state.updateEntry(_entry.copyWith(lastOpenedAt: DateTime.now()));
    } catch (e) {
      if (mounted) setState(() => _error = '파일을 열 수 없습니다: $e');
    }
  }

  String get _currentDocSig =>
      '${_encoding.name}|${_s.collapseBlankLines}|${_s.trimParagraphs}';

  Future<void> _parseDocument() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final sig = _currentDocSig;
    final previous = _doc;
    final progress = previous?.progressAt(_position.paragraph, _position.offset);
    final result = await compute(
      _parse,
      _ParseArgs(bytes, _encoding, _s.collapseBlankLines, _s.trimParagraphs),
    );
    if (!mounted) return;
    final doc = TextDocument(result.paragraphs);
    setState(() {
      _doc = doc;
      _docSig = sig;
      _detected = result.encoding;
      _toc = detectToc(doc.paragraphs);
      if (previous != null && progress != null) {
        // Paragraph indices changed; keep the same relative place.
        final pos = doc.positionAt((progress * doc.totalChars).round());
        _position = ReadingPosition(pos.paragraph, pos.offset);
      } else if (widget.startAtEnd && _entry.progress == 0) {
        // Opened backwards from the next file: start at the last line.
        _position =
            ReadingPosition(doc.length - 1, doc.paragraphs.last.length);
      } else if (_position.paragraph >= doc.length) {
        _position = ReadingPosition(doc.length - 1);
      }
      _positionNotifier.value = _position;
      _layoutSig = null; // force relayout
      _forceLayout = true;
    });
  }

  Future<void> _resolveFont() async {
    final id = _s.fontId;
    _fontId = id;
    final family = await _state.fonts.resolveFamily(id);
    if (!mounted || _fontId != id) return;
    setState(() {
      _fontFamily = family;
      _fontReady = true;
    });
  }

  void _onState() {
    if (!mounted) return;
    if (_state.entryById(widget.entryId) == null) return;
    if (_s.fontId != _fontId) _resolveFont();
    if (_doc != null && _docSig != _currentDocSig) _parseDocument();
    _applySystem();
    setState(() {});
  }

  void _applySystem() {
    final s = _s;
    if (_wakelockOn != s.keepScreenOn) {
      _wakelockOn = s.keepScreenOn;
      _safe(() => WakelockPlus.toggle(enable: s.keepScreenOn));
    }
    if (_volumeOn != s.volumeKeyPaging) {
      _volumeOn = s.volumeKeyPaging;
      if (s.volumeKeyPaging) {
        VolumeKeys.enable(this, (next) => _turn(next ? 1 : -1, volume: true));
      } else {
        VolumeKeys.disable(this);
      }
    }
    final immersive = s.fullscreen && !_menu;
    if (_immersive != immersive) {
      _immersive = immersive;
      SystemChrome.setEnabledSystemUIMode(
          immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  // ---- Layout -------------------------------------------------------------

  TextStyle _textStyle(Color color) => TextStyle(
        color: color,
        fontFamily: _fontFamily,
        fontSize: _s.fontSize,
        fontWeight: FontWeight.values[(_s.fontWeight ~/ 100 - 1).clamp(0, 8)],
        letterSpacing: _s.letterSpacing,
        wordSpacing: _s.wordSpacing,
        height: _s.lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
      );

  TextLayoutSpec _spec(Size size, Color color) => TextLayoutSpec(
        style: _textStyle(color),
        textAlign: _s.textAlign.value,
        viewportWidth: size.width,
        scaleX: _s.scaleX,
        indent: _s.indent * _s.fontSize,
        paragraphSpacing: _s.paragraphSpacing,
      );

  /// Rebuilds layout objects when settings, size, or font change. Called
  /// during build; slider drags are debounced.
  void _ensureLayout(Size size, ReaderTheme theme) {
    final doc = _doc;
    if (doc == null || !_fontReady || size.width <= 10 || size.height <= 10) {
      return;
    }
    final layoutSig = [
      _s.layoutKey,
      _s.readingMode.name,
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      _fontFamily,
      identityHashCode(doc),
    ].join('#');
    if (layoutSig != _layoutSig) {
      if (_layoutSig != null && !_forceLayout) {
        _relayoutTimer?.cancel();
        _relayoutTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          setState(() => _forceLayout = true);
        });
        return;
      }
      _forceLayout = false;
      _relayoutTimer?.cancel();
      _layoutSig = layoutSig;
      _renderSig = null;
      _contentSize = size;
      _layoutMode = _s.readingMode;
      _startLayout(doc, size, theme);
    }
    final renderSig = '$layoutSig#${theme.text.toARGB32()}';
    if (renderSig != _renderSig) {
      _renderSig = renderSig;
      _renderCache?.dispose();
      _renderCache = ParagraphLayoutCache(doc, _spec(size, theme.text));
    }
  }

  void _startLayout(TextDocument doc, Size size, ReaderTheme theme) {
    _paginator?.cancel();
    _paginator = null;
    _measureCache?.dispose();
    _measureCache = null;
    if (_layoutMode == ReadingMode.page) {
      final measure =
          ParagraphLayoutCache(doc, _spec(size, theme.text), capacity: 64);
      final paginator = Paginator(measure, size.height);
      _measureCache = measure;
      _paginator = paginator;
      _pendingJump = _position;
      scheduleMicrotask(() => paginator.run(
          onProgress: () => _onPaginationProgress(paginator)));
    } else {
      _itemScroll = ItemScrollController();
      _scrollOffset = ScrollOffsetController();
    }
  }

  void _onPaginationProgress(Paginator paginator) {
    if (!mounted || paginator != _paginator) return;
    final pending = _pendingJump;
    if (pending != null) {
      final index = paginator.pageIndexFor(pending);
      if (index != null) {
        _pendingJump = null;
        final old = _pageController;
        _pageController = PageController(initialPage: index);
        _pageIndex = index;
        WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
        setState(() {});
        return;
      }
    }
    final now = DateTime.now();
    if (paginator.done ||
        now.difference(_lastProgressBuild) > const Duration(milliseconds: 300)) {
      _lastProgressBuild = now;
      setState(() {});
    }
  }

  // ---- Navigation ---------------------------------------------------------

  void _setPosition(ReadingPosition pos) {
    _position = pos;
    _positionNotifier.value = pos;
    final doc = _doc;
    if (doc == null) return;
    final entry = _state.entryById(widget.entryId);
    if (entry == null) return;
    _state.updateEntry(
      entry.copyWith(
        position: pos,
        progress: _progressFor(pos),
        lastOpenedAt: DateTime.now(),
      ),
      notify: false,
    );
  }

  /// Reading progress for a view whose top is [pos], measured at the bottom
  /// edge of the view so that the last screen reads 100 %.
  double _progressFor(ReadingPosition pos) {
    final doc = _doc;
    if (doc == null) return 0;
    if (_layoutMode == ReadingMode.page) {
      final p = _paginator;
      final index = p?.pageIndexFor(pos);
      if (p != null && index != null) {
        if (index + 1 < p.pages.length) {
          final next = p.pages[index + 1].start;
          return doc.progressAt(next.paragraph, next.offset);
        }
        if (p.done) return 1;
      }
    } else {
      final cache = _renderCache;
      if (cache != null && _contentSize.height > 0) {
        return cache.endProgress(pos, _contentSize.height);
      }
    }
    return doc.progressAt(pos.paragraph, pos.offset);
  }

  void _goTo(ReadingPosition pos) {
    final doc = _doc;
    if (doc == null) return;
    final target = ReadingPosition(
        pos.paragraph.clamp(0, doc.length - 1), pos.offset.clamp(0, 1 << 30));
    _setPosition(target);
    if (_layoutMode == ReadingMode.page) {
      final p = _paginator;
      final index = p?.pageIndexFor(target);
      final controller = _pageController;
      if (index != null && controller != null && controller.hasClients) {
        controller.jumpToPage(index);
        _pageIndex = index;
      } else {
        setState(() => _pendingJump = target);
        if (p != null) _onPaginationProgress(p);
      }
    } else if (_itemScroll.isAttached) {
      final cache = _renderCache;
      final y = cache?.yForOffset(target.paragraph, target.offset) ?? 0;
      _itemScroll.jumpTo(
        index: target.paragraph,
        alignment: _contentSize.height > 0 ? -y / _contentSize.height : 0,
      );
    }
  }

  void _next() => _turn(1);
  void _previous() => _turn(-1);
  bool _opening = false;

  /// Moves one page (or one screen in scroll mode). With [volume], hitting
  /// the start or end opens the previous or next text file.
  void _turn(int delta, {bool volume = false}) {
    if (_opening) return;
    if (_layoutMode == ReadingMode.scroll) {
      if (_atScrollEdge(delta)) {
        _onBoundary(delta, volume);
        return;
      }
      _scrollOffset.animateScroll(
        offset: delta * _contentSize.height * 0.92,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }
    final p = _paginator;
    final controller = _pageController;
    if (p == null || controller == null || !controller.hasClients) return;
    final target = _pageIndex + delta;
    if (target < 0) {
      _onBoundary(delta, volume);
      return;
    }
    if (target >= p.pages.length) {
      if (p.done) _onBoundary(delta, volume);
      return;
    }
    if (_s.pageAnimation == PageAnimation.slide) {
      controller.animateToPage(target,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      controller.jumpToPage(target);
    }
  }

  /// Whether the scroll list is at its first (delta < 0) or last
  /// (delta > 0) position.
  bool _atScrollEdge(int delta) {
    final doc = _doc;
    final positions = _itemPositions.itemPositions.value;
    if (doc == null || positions.isEmpty) return false;
    if (delta < 0) {
      return positions.any((p) => p.index == 0 && p.itemLeadingEdge >= -0.001);
    }
    return positions
        .any((p) => p.index == doc.length - 1 && p.itemTrailingEdge <= 1.001);
  }

  void _onBoundary(int delta, bool volume) {
    if (volume && _s.autoNextFile) {
      _openNeighbor(delta);
      return;
    }
    _snack(delta > 0 ? '마지막 페이지입니다' : '첫 페이지입니다');
  }

  Future<void> _openNeighbor(int delta) async {
    final entry = _state.entryById(widget.entryId);
    if (entry == null) return;
    _opening = true;
    try {
      final next = await _state.neighborText(entry, delta);
      if (!mounted) return;
      if (next == null) {
        _snack(delta > 0 ? '마지막 파일입니다' : '첫 파일입니다');
        return;
      }
      _snack('${delta > 0 ? '다음' : '이전'} 파일: ${next.title}');
      await _state.flush();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            TextReaderPage(entryId: next.id, startAtEnd: delta < 0),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ));
    } finally {
      _opening = false;
    }
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(milliseconds: 1500)));
  }

  void _onPageChanged(int index) {
    final p = _paginator;
    _pageIndex = index;
    if (p == null || index >= p.pages.length) return;
    _setPosition(p.pages[index].start);
  }

  void _onScrollPositions() {
    if (_layoutMode != ReadingMode.scroll) return;
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    ItemPosition? top;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0) continue;
      if (top == null || p.itemLeadingEdge < top.itemLeadingEdge) top = p;
    }
    if (top == null) return;
    final cache = _renderCache;
    final y = -top.itemLeadingEdge * _contentSize.height;
    final offset = cache == null ? 0 : cache.offsetAtY(top.index, y);
    final pos = ReadingPosition(top.index, offset);
    if (pos != _position) _setPosition(pos);
  }

  void _onTap(Offset local, Size size) {
    final x = local.dx / size.width;
    if (_menu) {
      _toggleMenu();
    } else if (x < 0.3) {
      _previous();
    } else if (x > 0.7) {
      _next();
    } else {
      _toggleMenu();
    }
  }

  void _toggleMenu() {
    setState(() => _menu = !_menu);
    _applySystem();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    return Scaffold(
      backgroundColor: theme.background,
      body: _error != null
          ? _Message(text: _error!, theme: theme, showBack: true)
          : _doc == null || !_fontReady
              ? _Message(text: '불러오는 중…', theme: theme, busy: true)
              : LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildReader(context, constraints, theme)),
    );
  }

  Widget _buildReader(
      BuildContext context, BoxConstraints constraints, ReaderTheme theme) {
    final pad = MediaQuery.paddingOf(context);
    final s = _s;
    final insets = EdgeInsets.fromLTRB(
      pad.left + s.marginHorizontal,
      pad.top + s.marginVertical,
      pad.right + s.marginHorizontal,
      pad.bottom + s.marginVertical + (s.showFooter ? _footerHeight : 0),
    );
    final size = Size(
      constraints.maxWidth - insets.horizontal,
      constraints.maxHeight - insets.vertical,
    );
    _ensureLayout(size, theme);
    final screen = constraints.biggest;

    Widget body;
    if (_renderCache == null) {
      body = const SizedBox.expand();
    } else if (_layoutMode == ReadingMode.scroll) {
      body = _buildScroll(insets);
    } else {
      body = _buildPages(insets, theme);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTap(d.localPosition, screen),
            child: body,
          ),
        ),
        if (s.showFooter)
          Positioned(
            left: pad.left + s.marginHorizontal,
            right: pad.right + s.marginHorizontal,
            bottom: pad.bottom + 4,
            height: _footerHeight - 4,
            child: IgnorePointer(child: _buildFooter(theme)),
          ),
        if (_menu) ..._buildMenu(context, theme),
      ],
    );
  }

  Widget _buildPages(EdgeInsets insets, ReaderTheme theme) {
    final p = _paginator;
    final controller = _pageController;
    if (p == null || controller == null || _pendingJump != null) {
      return _Message(
        text: '페이지 계산 중… ${p?.pages.length ?? 0}쪽',
        theme: theme,
        busy: true,
      );
    }
    final cache = _renderCache!;
    return PageView.builder(
      controller: controller,
      itemCount: p.done ? p.pages.length : null,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        if (i >= p.pages.length) return null;
        return ColoredBox(
          color: theme.background,
          child: Padding(
            padding: insets,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: _contentSize,
                  painter: TextPagePainter(p.pages[i], cache),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScroll(EdgeInsets insets) {
    final cache = _renderCache!;
    final doc = _doc!;
    final y = cache.yForOffset(_position.paragraph, _position.offset);
    return Padding(
      padding: EdgeInsets.only(
          left: insets.left, right: insets.right, top: insets.top),
      child: ScrollablePositionedList.builder(
        key: ValueKey(_layoutSig),
        itemCount: doc.length,
        itemScrollController: _itemScroll,
        itemPositionsListener: _itemPositions,
        scrollOffsetController: _scrollOffset,
        initialScrollIndex: _position.paragraph.clamp(0, doc.length - 1),
        initialAlignment:
            _contentSize.height > 0 ? -y / _contentSize.height : 0,
        padding: EdgeInsets.only(bottom: insets.bottom),
        itemBuilder: (context, i) {
          final painter = cache.painter(i);
          return Padding(
            padding: EdgeInsets.only(bottom: cache.spec.paragraphSpacing),
            child: CustomPaint(
              size: Size(_contentSize.width, painter.height),
              painter: ParagraphPainter(i, cache),
            ),
          );
        },
      ),
    );
  }

  String? _chapterAt(int paragraph) {
    String? title;
    for (final t in _toc) {
      if (t.paragraph > paragraph) break;
      title = t.title;
    }
    return title;
  }

  Widget _buildFooter(ReaderTheme theme) {
    final style = TextStyle(
        color: theme.text.withValues(alpha: 0.55), fontSize: 11, height: 1.2);
    return ValueListenableBuilder<ReadingPosition>(
      valueListenable: _positionNotifier,
      builder: (context, pos, _) {
        final percent = _progressFor(pos) * 100;
        final p = _paginator;
        final pageText = _layoutMode == ReadingMode.page && p != null
            ? '${_pageIndex + 1} / ${p.done ? p.pages.length : '${p.pages.length}+'}'
            : null;
        return Row(
          children: [
            Expanded(
              child: Text(_chapterAt(pos.paragraph) ?? _entry.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            ValueListenableBuilder<DateTime>(
              valueListenable: _now,
              builder: (context, now, _) => Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                style: style,
              ),
            ),
            const SizedBox(width: 12),
            if (pageText != null) ...[
              Text(pageText, style: style),
              const SizedBox(width: 12),
            ],
            Text('${percent.toStringAsFixed(1)}%', style: style),
          ],
        );
      },
    );
  }

  List<Widget> _buildMenu(BuildContext context, ReaderTheme theme) {
    final scheme = Theme.of(context).colorScheme;
    final pad = MediaQuery.paddingOf(context);
    final doc = _doc!;
    final bookmarked = _entry.bookmarks.isNotEmpty;
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Material(
          color: scheme.surfaceContainer,
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.only(top: pad.top),
            child: Row(
              children: [
                const BackButton(),
                Expanded(
                  child: Text(_entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '검색',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                IconButton(
                  tooltip: '북마크 추가',
                  icon: Icon(bookmarked
                      ? Icons.bookmark_add
                      : Icons.bookmark_add_outlined),
                  onPressed: _addBookmark,
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
          color: scheme.surfaceContainer,
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.only(bottom: pad.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<ReadingPosition>(
                  valueListenable: _positionNotifier,
                  builder: (context, pos, _) => _ProgressSlider(
                    value: doc.progressAt(pos.paragraph, pos.offset),
                    onChangeEnd: (v) {
                      final at = doc.positionAt((v * doc.totalChars).round());
                      _goTo(ReadingPosition(at.paragraph, at.offset));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MenuButton(
                        icon: Icons.list,
                        label: '목차',
                        onTap: _openToc),
                    _MenuButton(
                      icon: _s.readingMode == ReadingMode.page
                          ? Icons.swap_vert
                          : Icons.auto_stories_outlined,
                      label: _s.readingMode == ReadingMode.page ? '스크롤' : '페이지',
                      onTap: () => _state.updateSettings(_s.copyWith(
                          readingMode: _s.readingMode == ReadingMode.page
                              ? ReadingMode.scroll
                              : ReadingMode.page)),
                    ),
                    _MenuButton(
                      icon: theme.dark ? Icons.light_mode : Icons.dark_mode,
                      label: theme.dark ? '라이트' : '다크',
                      onTap: () =>
                          _state.selectTheme(theme.dark ? 'light' : 'dark'),
                    ),
                    _MenuButton(
                      icon: Icons.text_fields,
                      label: '설정',
                      onTap: () => showReaderSettingsSheet(
                        context,
                        encoding: _encoding,
                        onEncoding: _changeEncoding,
                      ),
                    ),
                  ],
                ),
                if (_detected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '인코딩: ${_detected!.label}'
                      '${_encoding == TextEncodingKind.auto ? ' (자동)' : ''}'
                      ' · 문단 ${doc.length}개',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // ---- Actions ------------------------------------------------------------

  void _changeEncoding(TextEncodingKind kind) {
    _encoding = kind;
    final entry = _state.entryById(widget.entryId);
    if (entry != null) {
      _entry = kind == TextEncodingKind.auto
          ? entry.copyWith(clearEncoding: true)
          : entry.copyWith(encoding: kind.name);
      _state.updateEntry(_entry);
    }
    _position = const ReadingPosition(0);
    _doc = null;
    setState(() {});
    _parseDocument();
  }

  void _addBookmark() {
    final doc = _doc;
    final entry = _state.entryById(widget.entryId);
    if (doc == null || entry == null) return;
    final text = doc.paragraphs[_position.paragraph].trim();
    final label = text.isEmpty
        ? '${(doc.progressAt(_position.paragraph, _position.offset) * 100).toStringAsFixed(1)}%'
        : text.substring(_position.offset.clamp(0, text.length)).trim();
    final bookmark = Bookmark(
      position: _position,
      label: label.length > 60 ? '${label.substring(0, 60)}…' : label,
      createdAt: DateTime.now(),
    );
    _entry = entry.copyWith(bookmarks: [...entry.bookmarks, bookmark]);
    _state.updateEntry(_entry);
    _snack('북마크를 추가했습니다');
  }

  Future<void> _openToc() async {
    final doc = _doc;
    if (doc == null) return;
    final target = await showModalBottomSheet<ReadingPosition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TocSheet(
        toc: _toc,
        entryId: widget.entryId,
        currentParagraph: _position.paragraph,
        progressOf: (p) => doc.progressAt(p.paragraph, p.offset),
      ),
    );
    if (target != null) {
      _goTo(target);
      if (_menu) _toggleMenu();
    }
  }

  Future<void> _openSearch() async {
    final doc = _doc;
    if (doc == null) return;
    final hit = await Navigator.of(context).push<SearchHit>(
      MaterialPageRoute(builder: (_) => _SearchPage(document: doc)),
    );
    if (hit != null) {
      _goTo(ReadingPosition(hit.paragraph, hit.offset));
      if (_menu) _toggleMenu();
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.theme,
    this.busy = false,
    this.showBack = false,
  });

  final String text;
  final ReaderTheme theme;
  final bool busy;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) CircularProgressIndicator(color: theme.accent),
            const SizedBox(height: 16),
            Text(text, style: TextStyle(color: theme.text)),
            if (showBack)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('돌아가기'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon), const SizedBox(height: 2), Text(label)],
        ),
      ),
    );
  }
}

class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({required this.value, required this.onChangeEnd});

  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: v,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onChangeEnd(x);
            },
          ),
        ),
        SizedBox(
          width: 64,
          child: Text('${(v * 100).toStringAsFixed(1)}%'),
        ),
      ],
    );
  }
}

class _TocSheet extends StatelessWidget {
  const _TocSheet({
    required this.toc,
    required this.entryId,
    required this.currentParagraph,
    required this.progressOf,
  });

  final List<TocEntry> toc;
  final String entryId;
  final int currentParagraph;
  final double Function(ReadingPosition) progressOf;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entry = state.entryById(entryId);
    final bookmarks = entry?.bookmarks ?? const <Bookmark>[];
    var current = -1;
    for (var i = 0; i < toc.length; i++) {
      if (toc[i].paragraph <= currentParagraph) current = i;
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(tabs: [
              Tab(text: '목차 (${toc.length})'),
              Tab(text: '북마크 (${bookmarks.length})'),
            ]),
            Expanded(
              child: TabBarView(children: [
                toc.isEmpty
                    ? const Center(child: Text('감지된 목차가 없습니다'))
                    : ListView.builder(
                        itemCount: toc.length,
                        itemBuilder: (context, i) => ListTile(
                          selected: i == current,
                          title: Text(toc[i].title),
                          onTap: () => Navigator.pop(
                              context, ReadingPosition(toc[i].paragraph)),
                        ),
                      ),
                bookmarks.isEmpty
                    ? const Center(child: Text('북마크가 없습니다'))
                    : ListView.builder(
                        itemCount: bookmarks.length,
                        itemBuilder: (context, i) {
                          final b = bookmarks[i];
                          return ListTile(
                            title: Text(b.label,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${(progressOf(b.position) * 100).toStringAsFixed(1)}%'),
                            onTap: () => Navigator.pop(context, b.position),
                            trailing: IconButton(
                              tooltip: '삭제',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                if (entry == null) return;
                                state.updateEntry(entry.copyWith(
                                    bookmarks: [...bookmarks]..removeAt(i)));
                              },
                            ),
                          );
                        },
                      ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.document});

  final TextDocument document;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  List<SearchHit> _hits = const [];
  String _query = '';

  void _search(String q) {
    setState(() {
      _query = q.trim();
      _hits = widget.document.search(_query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '본문 검색', border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
        ),
      ),
      body: _query.isEmpty
          ? const SizedBox.shrink()
          : _hits.isEmpty
              ? const Center(child: Text('결과가 없습니다'))
              : ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (context, i) {
                    final h = _hits[i];
                    final pct = widget.document.progressAt(h.paragraph, h.offset);
                    return ListTile(
                      title: Text(h.snippet),
                      subtitle: Text('${(pct * 100).toStringAsFixed(1)}%'),
                      onTap: () => Navigator.pop(context, h),
                    );
                  },
                ),
    );
  }
}
