import 'package:flutter/painting.dart';

/// A color scheme applied to the reader and the rest of the app.
class ReaderTheme {
  const ReaderTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
    required this.accent,
    required this.dark,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final Color background;
  final Color text;
  final Color accent;

  /// Whether app chrome (dialogs, sheets, bars) uses dark brightness.
  final bool dark;

  /// Built-in themes cannot be edited or deleted.
  final bool builtIn;

  ReaderTheme copyWith({
    String? id,
    String? name,
    Color? background,
    Color? text,
    Color? accent,
    bool? dark,
    bool? builtIn,
  }) {
    return ReaderTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      background: background ?? this.background,
      text: text ?? this.text,
      accent: accent ?? this.accent,
      dark: dark ?? this.dark,
      builtIn: builtIn ?? this.builtIn,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'background': colorToHex(background),
        'text': colorToHex(text),
        'accent': colorToHex(accent),
        'dark': dark,
      };

  /// Parses a theme. Imported themes are never built-in.
  factory ReaderTheme.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('theme.id가 없습니다');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('theme.name이 없습니다');
    }
    return ReaderTheme(
      id: id,
      name: name.trim(),
      background: _readColor(json, 'background'),
      text: _readColor(json, 'text'),
      accent: json.containsKey('accent')
          ? _readColor(json, 'accent')
          : _readColor(json, 'text'),
      dark: json['dark'] == true,
    );
  }

  static Color _readColor(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('theme.$key 색상이 없습니다');
    }
    return colorFromHex(value);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderTheme &&
      other.id == id &&
      other.name == name &&
      other.background == background &&
      other.text == text &&
      other.accent == accent &&
      other.dark == dark &&
      other.builtIn == builtIn;

  @override
  int get hashCode =>
      Object.hash(id, name, background, text, accent, dark, builtIn);
}

/// Formats a color as `#AARRGGBB`.
String colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Parses `#RGB`, `#RRGGBB`, or `#AARRGGBB` (the `#` is optional).
Color colorFromHex(String input) {
  var hex = input.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) {
    throw FormatException('잘못된 색상 값: $input');
  }
  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    throw FormatException('잘못된 색상 값: $input');
  }
  return Color(value);
}

const builtInThemes = <ReaderTheme>[
  ReaderTheme(
    id: 'light',
    name: '라이트',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF222222),
    accent: Color(0xFF3F51B5),
    dark: false,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'dark',
    name: '다크',
    background: Color(0xFF121212),
    text: Color(0xFFCFCFCF),
    accent: Color(0xFF8C9EFF),
    dark: true,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'sepia',
    name: '세피아',
    background: Color(0xFFF4ECD8),
    text: Color(0xFF5B4636),
    accent: Color(0xFF8D6E63),
    dark: false,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'paper',
    name: '종이',
    background: Color(0xFFE9E6DF),
    text: Color(0xFF303030),
    accent: Color(0xFF607D8B),
    dark: false,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'green',
    name: '눈 보호',
    background: Color(0xFFCCE8CF),
    text: Color(0xFF233323),
    accent: Color(0xFF388E3C),
    dark: false,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'night_blue',
    name: '나이트 블루',
    background: Color(0xFF1B2333),
    text: Color(0xFFA9B7C6),
    accent: Color(0xFF64B5F6),
    dark: true,
    builtIn: true,
  ),
  ReaderTheme(
    id: 'amoled',
    name: '블랙 (AMOLED)',
    background: Color(0xFF000000),
    text: Color(0xFFA0A0A0),
    accent: Color(0xFFFFB74D),
    dark: true,
    builtIn: true,
  ),
];
