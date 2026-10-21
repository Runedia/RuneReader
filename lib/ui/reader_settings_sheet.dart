import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/reader_settings.dart';
import '../services/text_decoder.dart';
import 'font_page.dart';
import 'theme_page.dart';

/// Opens the reader settings sheet. [encoding] and [onEncoding] are shown
/// for text books only.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  bool imageMode = false,
  TextEncodingKind? encoding,
  ValueChanged<TextEncodingKind>? onEncoding,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReaderSettingsSheet(
      imageMode: imageMode,
      encoding: encoding,
      onEncoding: onEncoding,
    ),
  );
}

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    this.imageMode = false,
    this.encoding,
    this.onEncoding,
  });

  final bool imageMode;
  final TextEncodingKind? encoding;
  final ValueChanged<TextEncodingKind>? onEncoding;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;
    if (imageMode) {
      return SizedBox(height: height * 0.7, child: const _ImageTab());
    }
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(tabs: [
              Tab(text: '글꼴'),
              Tab(text: '레이아웃'),
              Tab(text: '테마'),
              Tab(text: '기타'),
            ]),
            Expanded(
              child: TabBarView(children: [
                const _FontTab(),
                const _LayoutTab(),
                const _ThemeTab(),
                _MiscTab(encoding: encoding, onEncoding: onEncoding),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final step = (max - min) / divisions;
    double snap(double v) =>
        (min + ((v - min) / step).round() * step).clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            onPressed: value > min ? () => onChanged(snap(value - step)) : null,
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: format(value),
              onChanged: (v) => onChanged(snap(v)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: value < max ? () => onChanged(snap(value + step)) : null,
          ),
          SizedBox(
            width: 52,
            child: Text(format(value), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _FontTab extends StatelessWidget {
  const _FontTab();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    void set(ReaderSettings v) => state.updateSettings(v);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('글꼴'),
          subtitle: Text(state.fonts.labelFor(s.fontId)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FontPage())),
        ),
        _ValueSlider(
          label: '크기',
          value: s.fontSize,
          min: ReaderSettings.minFontSize,
          max: ReaderSettings.maxFontSize,
          divisions: 112,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => set(s.copyWith(fontSize: v)),
        ),
        _ValueSlider(
          label: '장평',
          value: s.scaleX,
          min: ReaderSettings.minScaleX,
          max: ReaderSettings.maxScaleX,
          divisions: 150,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => set(s.copyWith(scaleX: v)),
        ),
        _ValueSlider(
          label: '자간',
          value: s.letterSpacing,
          min: ReaderSettings.minLetterSpacing,
          max: ReaderSettings.maxLetterSpacing,
          divisions: 250,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => set(s.copyWith(letterSpacing: v)),
        ),
        _ValueSlider(
          label: '단어 간격',
          value: s.wordSpacing,
          min: -10,
          max: 40,
          divisions: 100,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => set(s.copyWith(wordSpacing: v)),
        ),
        _ValueSlider(
          label: '굵기',
          value: s.fontWeight.toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          format: (v) => v.round().toString(),
          onChanged: (v) => set(s.copyWith(fontWeight: v.round())),
        ),
      ],
    );
  }
}

class _LayoutTab extends StatelessWidget {
  const _LayoutTab();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    void set(ReaderSettings v) => state.updateSettings(v);
    return ListView(
      children: [
        _ValueSlider(
          label: '줄 높이',
          value: s.lineHeight,
          min: ReaderSettings.minLineHeight,
          max: ReaderSettings.maxLineHeight,
          divisions: 64,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => set(s.copyWith(lineHeight: v)),
        ),
        _ValueSlider(
          label: '문단 간격',
          value: s.paragraphSpacing,
          min: 0,
          max: 60,
          divisions: 60,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => set(s.copyWith(paragraphSpacing: v)),
        ),
        _ValueSlider(
          label: '들여쓰기',
          value: s.indent,
          min: 0,
          max: 4,
          divisions: 16,
          format: (v) => '${v.toStringAsFixed(2)}em',
          onChanged: (v) => set(s.copyWith(indent: v)),
        ),
        _ValueSlider(
          label: '좌우 여백',
          value: s.marginHorizontal,
          min: 0,
          max: 80,
          divisions: 80,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => set(s.copyWith(marginHorizontal: v)),
        ),
        _ValueSlider(
          label: '상하 여백',
          value: s.marginVertical,
          min: 0,
          max: 120,
          divisions: 120,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => set(s.copyWith(marginVertical: v)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(width: 64, child: Text('정렬')),
              Expanded(
                child: SegmentedButton<ReaderTextAlign>(
                  segments: [
                    for (final a in ReaderTextAlign.values)
                      ButtonSegment(value: a, label: Text(a.label)),
                  ],
                  selected: {s.textAlign},
                  onSelectionChanged: (v) =>
                      set(s.copyWith(textAlign: v.first)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeTab extends StatelessWidget {
  const _ThemeTab();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in state.themes)
              InkWell(
                onTap: () => state.selectTheme(t.id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 92,
                  height: 64,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: t.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: t.id == state.theme.id ? t.accent : Colors.grey,
                      width: t.id == state.theme.id ? 3 : 1,
                    ),
                  ),
                  child: Text(t.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.text)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.palette_outlined),
          label: const Text('테마 관리 (만들기 · 내보내기 · 불러오기)'),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ThemePage())),
        ),
      ],
    );
  }
}

class _MiscTab extends StatelessWidget {
  const _MiscTab({this.encoding, this.onEncoding});

  final TextEncodingKind? encoding;
  final ValueChanged<TextEncodingKind>? onEncoding;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    void set(ReaderSettings v) => state.updateSettings(v);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<ReadingMode>(
            segments: const [
              ButtonSegment(
                  value: ReadingMode.page,
                  icon: Icon(Icons.auto_stories_outlined),
                  label: Text('페이지 넘김')),
              ButtonSegment(
                  value: ReadingMode.scroll,
                  icon: Icon(Icons.swap_vert),
                  label: Text('스크롤')),
            ],
            selected: {s.readingMode},
            onSelectionChanged: (v) => set(s.copyWith(readingMode: v.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('페이지 넘김 애니메이션'),
          value: s.pageAnimation == PageAnimation.slide,
          onChanged: (v) => set(s.copyWith(
              pageAnimation: v ? PageAnimation.slide : PageAnimation.none)),
        ),
        SwitchListTile(
          title: const Text('볼륨 키로 페이지 넘김'),
          value: s.volumeKeyPaging,
          onChanged: (v) => set(s.copyWith(volumeKeyPaging: v)),
        ),
        SwitchListTile(
          title: const Text('화면 켜짐 유지'),
          value: s.keepScreenOn,
          onChanged: (v) => set(s.copyWith(keepScreenOn: v)),
        ),
        SwitchListTile(
          title: const Text('전체 화면'),
          value: s.fullscreen,
          onChanged: (v) => set(s.copyWith(fullscreen: v)),
        ),
        SwitchListTile(
          title: const Text('하단 정보 표시 (쪽수 · 진행률 · 시각)'),
          value: s.showFooter,
          onChanged: (v) => set(s.copyWith(showFooter: v)),
        ),
        SwitchListTile(
          title: const Text('연속된 빈 줄 하나로 합치기'),
          value: s.collapseBlankLines,
          onChanged: (v) => set(s.copyWith(collapseBlankLines: v)),
        ),
        SwitchListTile(
          title: const Text('문단 앞뒤 공백 제거'),
          value: s.trimParagraphs,
          onChanged: (v) => set(s.copyWith(trimParagraphs: v)),
        ),
        if (encoding != null && onEncoding != null)
          ListTile(
            title: const Text('문자 인코딩'),
            trailing: DropdownButton<TextEncodingKind>(
              value: encoding,
              onChanged: (v) {
                if (v != null) {
                  onEncoding!(v);
                  Navigator.of(context).pop();
                }
              },
              items: [
                for (final e in TextEncodingKind.values)
                  DropdownMenuItem(value: e, child: Text(e.label)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ImageTab extends StatelessWidget {
  const _ImageTab();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    void set(ReaderSettings v) => state.updateSettings(v);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<ImageFit>(
            segments: const [
              ButtonSegment(value: ImageFit.contain, label: Text('화면 맞춤')),
              ButtonSegment(value: ImageFit.fitWidth, label: Text('너비 맞춤')),
              ButtonSegment(value: ImageFit.fitHeight, label: Text('높이 맞춤')),
            ],
            selected: {s.imageFit},
            onSelectionChanged: (v) => set(s.copyWith(imageFit: v.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('오른쪽에서 왼쪽으로 넘기기 (만화)'),
          value: s.imageRightToLeft,
          onChanged: (v) => set(s.copyWith(imageRightToLeft: v)),
        ),
        SwitchListTile(
          title: const Text('페이지 넘김 애니메이션'),
          value: s.pageAnimation == PageAnimation.slide,
          onChanged: (v) => set(s.copyWith(
              pageAnimation: v ? PageAnimation.slide : PageAnimation.none)),
        ),
        SwitchListTile(
          title: const Text('볼륨 키로 페이지 넘김'),
          value: s.volumeKeyPaging,
          onChanged: (v) => set(s.copyWith(volumeKeyPaging: v)),
        ),
        SwitchListTile(
          title: const Text('화면 켜짐 유지'),
          value: s.keepScreenOn,
          onChanged: (v) => set(s.copyWith(keepScreenOn: v)),
        ),
      ],
    );
  }
}
