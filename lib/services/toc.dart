class TocEntry {
  const TocEntry(this.title, this.paragraph);
  final String title;
  final int paragraph;
}

const _num = r'[0-9０-９一二三四五六七八九十百千零〇]+';

final _patterns = <RegExp>[
  // 제 1 장, 제1화, 제 3 권, 第一章
  RegExp('^[제第]\\s*$_num\\s*[장화권부편절회章話回卷節]'),
  // 1화, 12장, 3권, 1. 프롤로그 같은 번호 머리
  RegExp('^$_num\\s*[장화권부편회](\\s|\$|[.:\\-—])'),
  RegExp(r'^(chapter|part|book|episode|prologue|epilogue)\b', caseSensitive: false),
  RegExp(r'^(프롤로그|에필로그|서장|종장|서문|후기|작가\s*후기|외전|번외|막간|序章|終章)'),
  // 〈1〉, [1], <1>, 《1화》, #1
  RegExp('^[〈<\\[《【#]\\s*$_num\\s*[화장]?\\s*[〉>\\]》】]?\\s*\$'),
];

/// Detects chapter headings: short lines that match a heading pattern.
List<TocEntry> detectToc(List<String> paragraphs, {int maxLength = 40}) {
  final out = <TocEntry>[];
  for (var i = 0; i < paragraphs.length; i++) {
    final line = paragraphs[i].trim();
    if (line.isEmpty || line.length > maxLength) continue;
    if (_patterns.any((p) => p.hasMatch(line))) {
      out.add(TocEntry(line, i));
    }
  }
  return out;
}
