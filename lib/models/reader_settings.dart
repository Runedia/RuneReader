import 'dart:ui' show TextAlign;

enum ReadingMode { page, scroll }

enum PageAnimation { slide, none }

enum ReaderTextAlign {
  left(TextAlign.left, '왼쪽'),
  justify(TextAlign.justify, '양쪽'),
  center(TextAlign.center, '가운데');

  const ReaderTextAlign(this.value, this.label);
  final TextAlign value;
  final String label;
}

enum ImageFit { contain, fitWidth, fitHeight }

/// Typography, layout, and behavior settings for the reader.
///
/// All lengths are logical pixels except [indent] (em) and [lineHeight]
/// (multiple of font size).
class ReaderSettings {
  const ReaderSettings({
    this.fontId = 'system',
    this.fontSize = 18,
    this.fontWeight = 400,
    this.scaleX = 1.0,
    this.letterSpacing = 0,
    this.wordSpacing = 0,
    this.lineHeight = 1.6,
    this.paragraphSpacing = 8,
    this.indent = 0,
    this.marginHorizontal = 20,
    this.marginVertical = 24,
    this.textAlign = ReaderTextAlign.justify,
    this.readingMode = ReadingMode.page,
    this.pageAnimation = PageAnimation.slide,
    this.themeId = 'light',
    this.keepScreenOn = true,
    this.fullscreen = true,
    this.showFooter = true,
    this.volumeKeyPaging = false,
    this.collapseBlankLines = true,
    this.trimParagraphs = false,
    this.imageFit = ImageFit.contain,
    this.imageRightToLeft = false,
  });

  static const minFontSize = 8.0;
  static const maxFontSize = 64.0;
  static const minScaleX = 0.5;
  static const maxScaleX = 2.0;
  static const minLetterSpacing = -5.0;
  static const maxLetterSpacing = 20.0;
  static const minLineHeight = 0.8;
  static const maxLineHeight = 4.0;

  final String fontId;
  final double fontSize;
  final int fontWeight;

  /// Horizontal glyph scale (장평). 1.0 is the font's natural width.
  final double scaleX;

  /// Extra space between characters (자간).
  final double letterSpacing;
  final double wordSpacing;
  final double lineHeight;
  final double paragraphSpacing;

  /// First-line indent in em.
  final double indent;
  final double marginHorizontal;
  final double marginVertical;
  final ReaderTextAlign textAlign;
  final ReadingMode readingMode;
  final PageAnimation pageAnimation;
  final String themeId;
  final bool keepScreenOn;
  final bool fullscreen;
  final bool showFooter;
  final bool volumeKeyPaging;

  /// Merge runs of blank lines into a single blank line.
  final bool collapseBlankLines;

  /// Remove leading/trailing whitespace of each paragraph.
  final bool trimParagraphs;
  final ImageFit imageFit;
  final bool imageRightToLeft;

  ReaderSettings copyWith({
    String? fontId,
    double? fontSize,
    int? fontWeight,
    double? scaleX,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    double? paragraphSpacing,
    double? indent,
    double? marginHorizontal,
    double? marginVertical,
    ReaderTextAlign? textAlign,
    ReadingMode? readingMode,
    PageAnimation? pageAnimation,
    String? themeId,
    bool? keepScreenOn,
    bool? fullscreen,
    bool? showFooter,
    bool? volumeKeyPaging,
    bool? collapseBlankLines,
    bool? trimParagraphs,
    ImageFit? imageFit,
    bool? imageRightToLeft,
  }) {
    return ReaderSettings(
      fontId: fontId ?? this.fontId,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      scaleX: scaleX ?? this.scaleX,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      indent: indent ?? this.indent,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      marginVertical: marginVertical ?? this.marginVertical,
      textAlign: textAlign ?? this.textAlign,
      readingMode: readingMode ?? this.readingMode,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      themeId: themeId ?? this.themeId,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      fullscreen: fullscreen ?? this.fullscreen,
      showFooter: showFooter ?? this.showFooter,
      volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
      collapseBlankLines: collapseBlankLines ?? this.collapseBlankLines,
      trimParagraphs: trimParagraphs ?? this.trimParagraphs,
      imageFit: imageFit ?? this.imageFit,
      imageRightToLeft: imageRightToLeft ?? this.imageRightToLeft,
    );
  }

  /// Settings that change text layout. Used for theme export.
  Map<String, Object?> typographyJson() => {
        'fontId': fontId,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        'scaleX': scaleX,
        'letterSpacing': letterSpacing,
        'wordSpacing': wordSpacing,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'indent': indent,
        'marginHorizontal': marginHorizontal,
        'marginVertical': marginVertical,
        'textAlign': textAlign.name,
      };

  Map<String, Object?> toJson() => {
        ...typographyJson(),
        'readingMode': readingMode.name,
        'pageAnimation': pageAnimation.name,
        'themeId': themeId,
        'keepScreenOn': keepScreenOn,
        'fullscreen': fullscreen,
        'showFooter': showFooter,
        'volumeKeyPaging': volumeKeyPaging,
        'collapseBlankLines': collapseBlankLines,
        'trimParagraphs': trimParagraphs,
        'imageFit': imageFit.name,
        'imageRightToLeft': imageRightToLeft,
      };

  /// Reads known keys from [json] over this instance; unknown or invalid
  /// values keep the current value.
  ReaderSettings mergeJson(Map<String, Object?> json) {
    double? d(String k, double min, double max) {
      final v = json[k];
      return v is num ? v.toDouble().clamp(min, max) : null;
    }

    bool? b(String k) => json[k] is bool ? json[k] as bool : null;

    T? e<T extends Enum>(String k, List<T> values) {
      final v = json[k];
      if (v is! String) return null;
      for (final x in values) {
        if (x.name == v) return x;
      }
      return null;
    }

    final weight = json['fontWeight'];
    return copyWith(
      fontId: json['fontId'] is String ? json['fontId'] as String : null,
      fontSize: d('fontSize', minFontSize, maxFontSize),
      fontWeight: weight is num ? (weight.round() ~/ 100 * 100).clamp(100, 900) : null,
      scaleX: d('scaleX', minScaleX, maxScaleX),
      letterSpacing: d('letterSpacing', minLetterSpacing, maxLetterSpacing),
      wordSpacing: d('wordSpacing', -10, 40),
      lineHeight: d('lineHeight', minLineHeight, maxLineHeight),
      paragraphSpacing: d('paragraphSpacing', 0, 100),
      indent: d('indent', 0, 8),
      marginHorizontal: d('marginHorizontal', 0, 120),
      marginVertical: d('marginVertical', 0, 160),
      textAlign: e('textAlign', ReaderTextAlign.values),
      readingMode: e('readingMode', ReadingMode.values),
      pageAnimation: e('pageAnimation', PageAnimation.values),
      themeId: json['themeId'] is String ? json['themeId'] as String : null,
      keepScreenOn: b('keepScreenOn'),
      fullscreen: b('fullscreen'),
      showFooter: b('showFooter'),
      volumeKeyPaging: b('volumeKeyPaging'),
      collapseBlankLines: b('collapseBlankLines'),
      trimParagraphs: b('trimParagraphs'),
      imageFit: e('imageFit', ImageFit.values),
      imageRightToLeft: b('imageRightToLeft'),
    );
  }

  factory ReaderSettings.fromJson(Map<String, Object?> json) =>
      const ReaderSettings().mergeJson(json);

  /// Key identifying everything that affects text pagination.
  String get layoutKey => [
        fontId,
        fontSize,
        fontWeight,
        scaleX,
        letterSpacing,
        wordSpacing,
        lineHeight,
        paragraphSpacing,
        indent,
        marginHorizontal,
        marginVertical,
        textAlign.name,
        showFooter,
        collapseBlankLines,
        trimParagraphs,
      ].join('|');
}
