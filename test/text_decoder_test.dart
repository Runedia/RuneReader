import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_reader/services/text_decoder.dart';

Uint8List b(List<int> x) => Uint8List.fromList(x);

void main() {
  test('UTF-8 without BOM', () {
    final r = decodeText(b(utf8.encode('안녕 hello')));
    expect(r.encoding, TextEncodingKind.utf8);
    expect(r.text, '안녕 hello');
  });

  test('UTF-8 BOM is stripped', () {
    final r = decodeText(b([0xEF, 0xBB, 0xBF, ...utf8.encode('가나')]));
    expect(r.encoding, TextEncodingKind.utf8);
    expect(r.text, '가나');
  });

  test('UTF-16 LE / BE with BOM', () {
    final le = decodeText(b([0xFF, 0xFE, 0x00, 0xAC, 0x41, 0x00]));
    expect(le.encoding, TextEncodingKind.utf16le);
    expect(le.text, '가A');
    final be = decodeText(b([0xFE, 0xFF, 0xAC, 0x00, 0x00, 0x41]));
    expect(be.encoding, TextEncodingKind.utf16be);
    expect(be.text, '가A');
  });

  test('UTF-16 LE without BOM is detected heuristically', () {
    final units = 'Hello world, plain ascii text'.codeUnits;
    final bytes = <int>[for (final u in units) ...[u & 0xFF, u >> 8]];
    final r = decodeText(b(bytes));
    expect(r.encoding, TextEncodingKind.utf16le);
    expect(r.text, 'Hello world, plain ascii text');
  });

  test('CP949 including extended (UHC) syllables', () {
    const text = '안녕하세요 똠방각하 뷁 ABC';
    final bytes = cp949.encode(text);
    final r = decodeText(bytes);
    expect(r.encoding, TextEncodingKind.cp949);
    expect(r.text, text);
  });

  test('invalid CP949 bytes become U+FFFD instead of throwing', () {
    final r = decodeText(b([0x41, 0xFF, 0x42, 0xB0]),
        encoding: TextEncodingKind.cp949);
    expect(r.text, 'A�B�');
  });

  test('forced encoding overrides detection', () {
    final r = decodeText(b(utf8.encode('é')), encoding: TextEncodingKind.latin1);
    expect(r.encoding, TextEncodingKind.latin1);
    expect(r.text, 'Ã©');
  });

  test('line endings are normalized', () {
    final r = decodeText(b(utf8.encode('a\r\nb\rc\nd')));
    expect(r.text, 'a\nb\nc\nd');
  });
}
