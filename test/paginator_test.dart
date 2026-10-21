import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_reader/models/book.dart';
import 'package:rune_reader/services/paginator.dart';
import 'package:rune_reader/services/text_document.dart';

TextLayoutSpec spec({
  double width = 300,
  double scaleX = 1,
  double indent = 0,
  double spacing = 0,
}) =>
    TextLayoutSpec(
      // The test font (FlutterTest) renders every glyph as a 1em square.
      style: const TextStyle(fontSize: 10, height: 1.5),
      textAlign: TextAlign.left,
      viewportWidth: width,
      scaleX: scaleX,
      indent: indent,
      paragraphSpacing: spacing,
    );

TextDocument sampleDoc() => TextDocument([
      for (var i = 0; i < 60; i++)
        List.filled(10 + (i * 7) % 90, 'w$i').join(' '),
      '',
      'end',
    ]);

/// Asserts that pages cover every line exactly once, in order.
void expectContiguous(Paginator p) {
  final doc = p.cache.document;
  var para = 0;
  var top = 0.0;
  for (final page in p.pages) {
    expect(page.slices, isNotEmpty);
    var y = 0.0;
    for (final s in page.slices) {
      expect(s.paragraph, para, reason: 'paragraph order');
      expect(s.top, closeTo(top, 0.01), reason: 'no gap or overlap');
      expect(s.y, greaterThanOrEqualTo(y - 0.01));
      expect(s.y + s.height, lessThanOrEqualTo(p.pageHeight + 0.6));
      y = s.y + s.height;
      final h = p.cache.painter(s.paragraph).height;
      if ((s.bottom - h).abs() < 0.01) {
        para++;
        top = 0;
      } else {
        top = s.bottom;
      }
    }
  }
  expect(para, doc.length, reason: 'all paragraphs paginated');
}

void main() {
  testWidgets('pages are contiguous and fit the page height', (tester) async {
    final doc = sampleDoc();
    final p = Paginator(ParagraphLayoutCache(doc, spec(spacing: 6)), 200)
      ..runSync();
    expect(p.done, isTrue);
    expect(p.pages.length, greaterThan(5));
    expectContiguous(p);
    expect(p.pages.first.start, const ReadingPosition(0));
  });

  testWidgets('pageIndexFor finds the page containing a position',
      (tester) async {
    final doc = sampleDoc();
    final p = Paginator(ParagraphLayoutCache(doc, spec()), 150)..runSync();
    for (var i = 0; i < p.pages.length; i++) {
      expect(p.pageIndexFor(p.pages[i].start), i);
    }
    final last = ReadingPosition(doc.length - 1, 2);
    expect(p.pageIndexFor(last), p.pages.length - 1);
    // A position inside page 3 maps to page 3.
    final s = p.pages[3].start;
    expect(p.pageIndexFor(ReadingPosition(s.paragraph, s.offset + 1)),
        anyOf(3, 4));
  });

  testWidgets('horizontal scale (장평) changes line capacity', (tester) async {
    final doc = sampleDoc();
    final normal = Paginator(ParagraphLayoutCache(doc, spec()), 200)..runSync();
    final narrow =
        Paginator(ParagraphLayoutCache(doc, spec(scaleX: 0.5)), 200)..runSync();
    final wide =
        Paginator(ParagraphLayoutCache(doc, spec(scaleX: 1.5)), 200)..runSync();
    expect(narrow.cache.spec.layoutWidth, 600);
    expect(narrow.pages.length, lessThan(normal.pages.length));
    expect(wide.pages.length, greaterThan(normal.pages.length));
    expectContiguous(narrow);
    expectContiguous(wide);
  });

  testWidgets('indent placeholder shifts the first line only', (tester) async {
    final doc = TextDocument(['abcdefghij' * 10]);
    final plain = ParagraphLayoutCache(doc, spec(width: 100));
    final indented = ParagraphLayoutCache(doc, spec(width: 100, indent: 20));
    expect(indented.prefixLength(0), 1);
    final first = indented.painter(0).getOffsetForCaret(
        const TextPosition(offset: 1), Rect.zero);
    expect(first.dx, closeTo(20, 0.01));
    // Indent pushes text so the paragraph needs at least as many lines.
    expect(indented.painter(0).height,
        greaterThanOrEqualTo(plain.painter(0).height));
    // Offsets exclude the placeholder.
    expect(indented.offsetAtY(0, 0), 0);
    final y = indented.yForOffset(0, 50);
    expect(indented.offsetAtY(0, y), lessThanOrEqualTo(50));
  });

  testWidgets('a line taller than the page is still placed', (tester) async {
    final doc = TextDocument(['big', 'small']);
    final tall = TextLayoutSpec(
      style: const TextStyle(fontSize: 100),
      textAlign: TextAlign.left,
      viewportWidth: 500,
      scaleX: 1,
      indent: 0,
      paragraphSpacing: 0,
    );
    final p = Paginator(ParagraphLayoutCache(doc, tall), 50)..runSync();
    expect(p.done, isTrue);
    expect(p.pages.length, 2);
  });
}
