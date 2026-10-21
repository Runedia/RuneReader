import 'package:flutter/widgets.dart';

import '../models/book.dart';
import 'text_document.dart';

/// Parameters that determine how paragraphs are laid out.
class TextLayoutSpec {
  const TextLayoutSpec({
    required this.style,
    required this.textAlign,
    required this.viewportWidth,
    required this.scaleX,
    required this.indent,
    required this.paragraphSpacing,
  });

  final TextStyle style;
  final TextAlign textAlign;

  /// Width available on screen for text.
  final double viewportWidth;

  /// Horizontal glyph scale. Text is laid out at `viewportWidth / scaleX`
  /// and stretched by `scaleX` when painted.
  final double scaleX;

  /// First-line indent in logical pixels (before scaling).
  final double indent;
  final double paragraphSpacing;

  double get layoutWidth => viewportWidth / scaleX;
}

/// Lazily lays out paragraphs with [TextPainter] and keeps an LRU cache.
class ParagraphLayoutCache {
  ParagraphLayoutCache(this.document, this.spec, {this.capacity = 300});

  final TextDocument document;
  final TextLayoutSpec spec;
  final int capacity;
  final _cache = <int, TextPainter>{}; // insertion-ordered: LRU

  /// Number of code units inserted before the paragraph text (the indent
  /// placeholder).
  int prefixLength(int index) => _hasIndent(index) ? 1 : 0;

  bool _hasIndent(int index) =>
      spec.indent > 0 && document.paragraphs[index].trim().isNotEmpty;

  TextPainter painter(int index) {
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final built = _build(index);
    _cache[index] = built;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first)!.dispose();
    }
    return built;
  }

  TextPainter _build(int index) {
    final text = document.paragraphs[index];
    final indent = _hasIndent(index);
    final painter = TextPainter(
      text: TextSpan(
        style: spec.style,
        children: [
          if (indent)
            const WidgetSpan(
              child: SizedBox.shrink(),
              alignment: PlaceholderAlignment.bottom,
            ),
          // An empty paragraph still occupies one line.
          TextSpan(text: text.isEmpty ? ' ' : text),
        ],
      ),
      textAlign: spec.textAlign,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
    if (indent) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(spec.indent, 0),
          alignment: PlaceholderAlignment.bottom,
        ),
      ]);
    }
    final width = spec.layoutWidth;
    painter.layout(minWidth: width, maxWidth: width);
    return painter;
  }

  /// Character offset within paragraph [index] of the first line at or below
  /// [y] (paragraph coordinates).
  int offsetAtY(int index, double y) {
    if (y <= 0) return 0;
    final p = painter(index);
    final pos = p.getPositionForOffset(Offset(0, y + 1)).offset;
    final len = document.paragraphs[index].length;
    return (pos - prefixLength(index)).clamp(0, len);
  }

  /// Vertical position (paragraph coordinates) of the line containing
  /// character [offset].
  double yForOffset(int index, int offset) {
    if (offset <= 0) return 0;
    final p = painter(index);
    final caret = p.getOffsetForCaret(
      TextPosition(offset: offset + prefixLength(index)),
      Rect.zero,
    );
    return caret.dy;
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

/// A vertical band `[top, bottom)` of one paragraph drawn at [y] on a page.
class PageSlice {
  const PageSlice({
    required this.paragraph,
    required this.top,
    required this.bottom,
    required this.y,
  });

  final int paragraph;
  final double top;
  final double bottom;
  final double y;

  double get height => bottom - top;
}

class TextPage {
  const TextPage(this.slices, this.start);

  final List<PageSlice> slices;

  /// Reading position of the first character on the page.
  final ReadingPosition start;
}

/// Splits a document into pages of a fixed height. Pagination runs
/// incrementally so the reader can show early pages while later ones are
/// still being computed.
class Paginator {
  Paginator(this.cache, this.pageHeight);

  final ParagraphLayoutCache cache;
  final double pageHeight;
  final List<TextPage> pages = [];

  bool get done => _done;
  bool _done = false;
  bool _cancelled = false;

  // Incremental state.
  int _para = 0;
  double _top = 0;

  static const _epsilon = 0.5;

  void cancel() => _cancelled = true;

  /// Runs to completion, yielding to the event loop about every 12 ms.
  Future<void> run({void Function()? onProgress}) async {
    final watch = Stopwatch()..start();
    while (!_done && !_cancelled) {
      _step();
      if (watch.elapsedMilliseconds > 12) {
        onProgress?.call();
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    if (!_cancelled) onProgress?.call();
  }

  /// Computes everything synchronously (used by tests).
  void runSync() {
    while (!_done) {
      _step();
    }
  }

  /// Lays out one page.
  void _step() {
    final doc = cache.document;
    if (_para >= doc.length) {
      _done = true;
      return;
    }
    final slices = <PageSlice>[];
    final start = ReadingPosition(_para, cache.offsetAtY(_para, _top));
    var y = 0.0;
    while (_para < doc.length) {
      final painter = cache.painter(_para);
      final remaining = painter.height - _top;
      final available = pageHeight - y;
      if (remaining <= available + _epsilon) {
        slices.add(PageSlice(
            paragraph: _para, top: _top, bottom: painter.height, y: y));
        y += remaining + cache.spec.paragraphSpacing;
        _para++;
        _top = 0;
        if (y >= pageHeight - _epsilon) break;
        continue;
      }
      // Paragraph overflows: take as many whole lines as fit.
      final cut = _lastFittingBottom(painter, _top, available);
      if (cut != null) {
        slices.add(PageSlice(paragraph: _para, top: _top, bottom: cut, y: y));
        _top = cut;
      } else if (slices.isEmpty) {
        // A single line taller than the page: show it clipped.
        final forced = _firstLineBottom(painter, _top) ?? painter.height;
        slices.add(
            PageSlice(paragraph: _para, top: _top, bottom: forced, y: y));
        _top = forced;
        if (_top >= painter.height - _epsilon) {
          _para++;
          _top = 0;
        }
      }
      break;
    }
    if (slices.isNotEmpty) pages.add(TextPage(slices, start));
    if (_para >= doc.length) _done = true;
  }

  static double? _lastFittingBottom(
      TextPainter painter, double top, double available) {
    double? best;
    var bottom = 0.0;
    for (final line in painter.computeLineMetrics()) {
      bottom += line.height;
      if (bottom <= top + _epsilon) continue;
      if (bottom - top <= available + _epsilon) {
        best = bottom;
      } else {
        break;
      }
    }
    return best;
  }

  static double? _firstLineBottom(TextPainter painter, double top) {
    var bottom = 0.0;
    for (final line in painter.computeLineMetrics()) {
      bottom += line.height;
      if (bottom > top + _epsilon) return bottom;
    }
    return null;
  }

  /// Index of the page containing [position], or null if pagination has not
  /// reached it yet.
  int? pageIndexFor(ReadingPosition position) {
    if (pages.isEmpty) return null;
    if (!_done && pages.last.start.compareTo(position) <= 0) {
      // The last computed page may not be the one; wait for more pages
      // unless the position is strictly before the next page start.
      return null;
    }
    var lo = 0, hi = pages.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (pages[mid].start.compareTo(position) <= 0) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Paints a page's slices from a [ParagraphLayoutCache].
class TextPagePainter extends CustomPainter {
  TextPagePainter(this.page, this.cache);

  final TextPage page;
  final ParagraphLayoutCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = cache.spec.scaleX;
    for (final slice in page.slices) {
      canvas.save();
      canvas.translate(0, slice.y);
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, slice.height));
      canvas.scale(scaleX, 1);
      cache.painter(slice.paragraph).paint(canvas, Offset(0, -slice.top));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(TextPagePainter oldDelegate) =>
      oldDelegate.page != page || oldDelegate.cache != cache;
}

/// Paints a whole paragraph (scroll mode).
class ParagraphPainter extends CustomPainter {
  ParagraphPainter(this.index, this.cache);

  final int index;
  final ParagraphLayoutCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(cache.spec.scaleX, 1);
    cache.painter(index).paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ParagraphPainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.cache != cache;
}
