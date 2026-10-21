import 'package:flutter_test/flutter_test.dart';
import 'package:rune_reader/services/natural_sort.dart';
import 'package:rune_reader/services/text_document.dart';
import 'package:rune_reader/services/toc.dart';

void main() {
  group('TextDocument.parse', () {
    test('collapses blank-line runs and drops leading/trailing blanks', () {
      final d = TextDocument.parse('\n\n첫 줄\n\n\n\n둘째 줄  \n\n');
      expect(d.paragraphs, ['첫 줄', '', '둘째 줄']);
    });

    test('keeps blank lines when collapsing is off', () {
      final d = TextDocument.parse('a\n\n\nb', collapseBlankLines: false);
      expect(d.paragraphs, ['a', '', '', 'b']);
    });

    test('trims paragraphs when requested', () {
      final d = TextDocument.parse('   들여쓴 줄\n\t탭', trimParagraphs: true);
      expect(d.paragraphs, ['들여쓴 줄', '탭']);
    });

    test('empty input yields a single empty paragraph', () {
      expect(TextDocument.parse('').paragraphs, ['']);
    });
  });

  test('offsets, progress, and positionAt round-trip', () {
    final d = TextDocument(['abc', 'de', 'fghij']);
    expect(d.totalChars, 3 + 1 + 2 + 1 + 5);
    expect(d.absoluteOffset(2, 1), 8); // 'abc\n' + 'de\n' + 'f'
    final pos = d.positionAt(8);
    expect(pos.paragraph, 2);
    expect(pos.offset, 1);
    expect(d.progressAt(0, 0), 0);
    expect(d.progressAt(2, 5), 1);
  });

  test('search is case-insensitive and reports offsets', () {
    final d = TextDocument(['Hello world', 'say hello again', 'nothing']);
    final hits = d.search('HELLO');
    expect(hits.map((h) => (h.paragraph, h.offset)), [(0, 0), (1, 4)]);
    expect(d.search('   '), isEmpty);
  });

  test('detectToc finds common Korean and English headings', () {
    final paragraphs = [
      '프롤로그',
      '본문입니다.',
      '제 1 장 시작',
      '제2화',
      '12화',
      'Chapter 3',
      '〈4〉',
      '이 문장은 제1장이라는 단어를 포함하지만 제목이 아니다.',
      '1화를 보았다고 말했다',
      '에필로그',
    ];
    final toc = detectToc(paragraphs);
    expect(toc.map((e) => e.paragraph), [0, 2, 3, 4, 5, 6, 9]);
  });

  test('naturalCompare orders embedded numbers numerically', () {
    final names = ['img10.jpg', 'img2.jpg', 'IMG1.jpg', 'img02.jpg', 'a.jpg'];
    names.sort(naturalCompare);
    expect(names, ['a.jpg', 'IMG1.jpg', 'img2.jpg', 'img02.jpg', 'img10.jpg']);
  });
}
