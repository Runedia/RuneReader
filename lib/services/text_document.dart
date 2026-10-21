/// A plain-text book split into paragraphs (one per line).
class TextDocument {
  TextDocument(this.paragraphs) : _starts = _computeStarts(paragraphs);

  /// Splits [text] (newline-normalized) into paragraphs.
  factory TextDocument.parse(
    String text, {
    bool collapseBlankLines = true,
    bool trimParagraphs = false,
  }) {
    final lines = text.split('\n');
    final out = <String>[];
    var previousBlank = true; // drop leading blank lines
    for (final rawLine in lines) {
      final line = trimParagraphs ? rawLine.trim() : rawLine.trimRight();
      final blank = line.trim().isEmpty;
      if (blank) {
        if (collapseBlankLines && previousBlank) continue;
        out.add('');
      } else {
        out.add(line);
      }
      previousBlank = blank;
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) out.add('');
    return TextDocument(out);
  }

  final List<String> paragraphs;

  /// Cumulative character offset of each paragraph start (+1 per newline).
  final List<int> _starts;

  int get length => paragraphs.length;

  int get totalChars =>
      _starts.isEmpty ? 0 : _starts.last + paragraphs.last.length;

  /// Absolute character offset of a paragraph position.
  int absoluteOffset(int paragraph, int offset) {
    if (paragraphs.isEmpty) return 0;
    final p = paragraph.clamp(0, paragraphs.length - 1);
    return _starts[p] + offset.clamp(0, paragraphs[p].length);
  }

  /// Fraction of the document read at a paragraph position (0..1).
  double progressAt(int paragraph, int offset) {
    final total = totalChars;
    if (total == 0) return 0;
    return absoluteOffset(paragraph, offset) / total;
  }

  /// Paragraph containing the absolute character offset [absolute].
  ({int paragraph, int offset}) positionAt(int absolute) {
    if (paragraphs.isEmpty) return (paragraph: 0, offset: 0);
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= absolute) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final offset = (absolute - _starts[lo]).clamp(0, paragraphs[lo].length);
    return (paragraph: lo, offset: offset);
  }

  /// Case-insensitive search. Returns up to [limit] hits.
  List<SearchHit> search(String query, {int limit = 500}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <SearchHit>[];
    for (var i = 0; i < paragraphs.length && hits.length < limit; i++) {
      final lower = paragraphs[i].toLowerCase();
      var from = 0;
      while (hits.length < limit) {
        final idx = lower.indexOf(q, from);
        if (idx < 0) break;
        hits.add(SearchHit(i, idx, _snippet(paragraphs[i], idx, q.length)));
        from = idx + q.length;
      }
    }
    return hits;
  }

  static String _snippet(String text, int index, int length) {
    final start = (index - 20).clamp(0, text.length);
    final end = (index + length + 40).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).trim()}$suffix';
  }

  static List<int> _computeStarts(List<String> paragraphs) {
    final starts = List<int>.filled(paragraphs.length, 0);
    var acc = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      starts[i] = acc;
      acc += paragraphs[i].length + 1;
    }
    return starts;
  }
}

class SearchHit {
  const SearchHit(this.paragraph, this.offset, this.snippet);
  final int paragraph;
  final int offset;
  final String snippet;
}
