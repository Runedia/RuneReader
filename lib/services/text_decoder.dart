import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949/cp949table.dart';

enum TextEncodingKind {
  auto('자동 감지'),
  utf8('UTF-8'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  cp949('CP949 (EUC-KR)'),
  latin1('ISO-8859-1');

  const TextEncodingKind(this.label);
  final String label;

  static TextEncodingKind byName(String? name) => values.firstWhere(
        (e) => e.name == name,
        orElse: () => TextEncodingKind.auto,
      );
}

class DecodedText {
  const DecodedText(this.text, this.encoding);

  /// Decoded text with line endings normalized to `\n` and no BOM.
  final String text;

  /// Encoding actually used (never [TextEncodingKind.auto]).
  final TextEncodingKind encoding;
}

/// Decodes [bytes]. With [TextEncodingKind.auto] the encoding is detected
/// from the BOM, then strict UTF-8 validation, then a UTF-16 heuristic, and
/// finally CP949, which is the common legacy encoding of Korean text files.
DecodedText decodeText(
  Uint8List bytes, {
  TextEncodingKind encoding = TextEncodingKind.auto,
}) {
  final kind =
      encoding == TextEncodingKind.auto ? detectEncoding(bytes) : encoding;
  final String raw;
  switch (kind) {
    case TextEncodingKind.utf8:
    case TextEncodingKind.auto:
      raw = utf8.decode(_skipBom(bytes, const [0xEF, 0xBB, 0xBF]),
          allowMalformed: true);
    case TextEncodingKind.utf16le:
      raw = _decodeUtf16(_skipBom(bytes, const [0xFF, 0xFE]), Endian.little);
    case TextEncodingKind.utf16be:
      raw = _decodeUtf16(_skipBom(bytes, const [0xFE, 0xFF]), Endian.big);
    case TextEncodingKind.cp949:
      raw = decodeCp949(bytes);
    case TextEncodingKind.latin1:
      raw = latin1.decode(bytes);
  }
  return DecodedText(normalizeNewlines(raw), kind);
}

TextEncodingKind detectEncoding(Uint8List bytes) {
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    return TextEncodingKind.utf8;
  }
  if (_startsWith(bytes, const [0xFF, 0xFE])) return TextEncodingKind.utf16le;
  if (_startsWith(bytes, const [0xFE, 0xFF])) return TextEncodingKind.utf16be;

  // UTF-16 without BOM: ASCII-heavy text has a zero in every other byte.
  // Checked before UTF-8 because NUL bytes are valid UTF-8.
  final sample = bytes.length < 4096 ? bytes.length : 4096;
  if (sample >= 4) {
    var evenZero = 0, oddZero = 0;
    for (var i = 0; i + 1 < sample; i += 2) {
      if (bytes[i] == 0) evenZero++;
      if (bytes[i + 1] == 0) oddZero++;
    }
    final pairs = sample ~/ 2;
    if (oddZero > pairs * 0.3 && evenZero < pairs * 0.05) {
      return TextEncodingKind.utf16le;
    }
    if (evenZero > pairs * 0.3 && oddZero < pairs * 0.05) {
      return TextEncodingKind.utf16be;
    }
  }
  if (_isValidUtf8(bytes)) return TextEncodingKind.utf8;
  return TextEncodingKind.cp949;
}

/// Lenient CP949 decoder: invalid sequences become U+FFFD instead of
/// throwing.
String decodeCp949(Uint8List bytes) {
  final out = StringBuffer();
  final units = <int>[];
  void flush() {
    if (units.isNotEmpty) {
      out.write(String.fromCharCodes(units));
      units.clear();
    }
  }

  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      units.add(b);
      i++;
    } else if (i + 1 < bytes.length) {
      final code = (b << 8) | bytes[i + 1];
      final unicode = cp949ToUnicodeCodeMap[code];
      if (unicode != null) {
        units.add(unicode);
        i += 2;
      } else {
        units.add(0xFFFD);
        i++;
      }
    } else {
      units.add(0xFFFD);
      i++;
    }
    if (units.length >= 8192) flush();
  }
  flush();
  return out.toString();
}

String normalizeNewlines(String text) {
  var s = text;
  if (s.startsWith('﻿')) s = s.substring(1);
  return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

Uint8List _skipBom(Uint8List bytes, List<int> bom) => _startsWith(bytes, bom)
    ? Uint8List.sublistView(bytes, bom.length)
    : bytes;

String _decodeUtf16(Uint8List bytes, Endian endian) {
  final data = ByteData.sublistView(bytes);
  final count = bytes.length ~/ 2;
  final units = List<int>.generate(
    count,
    (i) => data.getUint16(i * 2, endian),
    growable: false,
  );
  return String.fromCharCodes(units);
}

bool _isValidUtf8(Uint8List bytes) {
  try {
    const Utf8Decoder(allowMalformed: false).convert(bytes);
    return true;
  } on FormatException {
    return false;
  }
}
