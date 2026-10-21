import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/reader_theme.dart';
import '../services/theme_io.dart';
import 'color_picker.dart';

/// Lists themes; select, create, edit, delete, import, and export them.
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final current = state.theme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('테마'),
        actions: [
          IconButton(
            tooltip: '불러오기',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => importThemesFlow(context),
          ),
          IconButton(
            tooltip: '사용자 테마 전체 내보내기',
            icon: const Icon(Icons.ios_share),
            onPressed: state.customThemes.isEmpty
                ? null
                : () => exportThemesFlow(context, state.customThemes),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final t in state.themes)
            _ThemeTile(
              theme: t,
              selected: t.id == current.id,
              onSelect: () => state.selectTheme(t.id),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('새 테마'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ThemeEditorPage(
            initial: current.copyWith(
              id: state.newThemeId(),
              name: '${current.name} 사본',
              builtIn: false,
            ),
            isNew: true,
          ),
        )),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.onSelect,
  });

  final ReaderTheme theme;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final appText = state.theme.text;
    return ListTile(
      onTap: onSelect,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.accent : Colors.grey,
            width: selected ? 3 : 1,
          ),
        ),
        child: Text('가',
            style: TextStyle(
                color: theme.text, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      title: Text(theme.name, style: TextStyle(color: appText)),
      subtitle: Text(
        '${theme.builtIn ? '기본' : '사용자'} · ${theme.dark ? '어두움' : '밝음'}',
        style: TextStyle(color: appText.withValues(alpha: 0.6)),
      ),
      trailing: PopupMenuButton<String>(
        iconColor: appText,
        onSelected: (action) async {
          switch (action) {
            case 'edit':
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ThemeEditorPage(initial: theme)));
            case 'copy':
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ThemeEditorPage(
                  initial: theme.copyWith(
                    id: state.newThemeId(),
                    name: '${theme.name} 사본',
                    builtIn: false,
                  ),
                  isNew: true,
                ),
              ));
            case 'export':
              if (context.mounted) await exportThemesFlow(context, [theme]);
            case 'delete':
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('테마 삭제'),
                  content: Text('"${theme.name}" 테마를 삭제합니다.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('삭제')),
                  ],
                ),
              );
              if (ok == true) await state.deleteTheme(theme.id);
          }
        },
        itemBuilder: (_) => [
          if (!theme.builtIn)
            const PopupMenuItem(value: 'edit', child: Text('편집')),
          const PopupMenuItem(value: 'copy', child: Text('복제하여 새 테마')),
          const PopupMenuItem(value: 'export', child: Text('내보내기')),
          if (!theme.builtIn)
            const PopupMenuItem(value: 'delete', child: Text('삭제')),
        ],
      ),
    );
  }
}

/// Exports [themes] to a JSON file chosen by the user.
Future<void> exportThemesFlow(
    BuildContext context, List<ReaderTheme> themes) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final includeTypography = await showDialog<bool>(
    context: context,
    builder: (context) {
      var include = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('테마 내보내기'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: include,
            onChanged: (v) => setState(() => include = v ?? false),
            title: const Text('현재 글꼴·크기·간격 설정 포함'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(context, include),
                child: const Text('저장')),
          ],
        ),
      );
    },
  );
  if (includeTypography == null) return;
  final json = encodeThemeBundle(ThemeBundle(
    themes,
    typography: includeTypography ? state.settings.typographyJson() : null,
  ));
  final baseName = themes.length == 1
      ? themes.first.name.replaceAll(RegExp(r'[\\/:*?"<>| ]+'), '_')
      : 'themes';
  try {
    final uri = await FilePicker.saveFile(
      fileName: 'rune-theme-$baseName.json',
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    );
    if (uri != null) {
      messenger.showSnackBar(
          SnackBar(content: Text('${themes.length}개 테마를 내보냈습니다')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('내보내기 실패: $e')));
  }
}

/// Imports themes from a JSON file chosen by the user.
Future<void> importThemesFlow(BuildContext context) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    final bundle = decodeThemeBundle(utf8.decode(bytes, allowMalformed: true));
    final stored = await state.importThemes(bundle.themes);
    messenger.showSnackBar(
        SnackBar(content: Text('${stored.length}개 테마를 불러왔습니다')));
    final typography = bundle.typography;
    if (typography != null && context.mounted) {
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('텍스트 설정 적용'),
          content: const Text('파일에 글꼴·크기·간격 설정이 포함되어 있습니다. 적용할까요?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('아니오')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('적용')),
          ],
        ),
      );
      if (apply == true) state.applyTypography(typography);
    }
    if (stored.length == 1) state.selectTheme(stored.first.id);
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('불러오기 실패: ${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
  }
}

/// Creates or edits a custom theme.
class ThemeEditorPage extends StatefulWidget {
  const ThemeEditorPage({super.key, required this.initial, this.isNew = false});

  final ReaderTheme initial;
  final bool isNew;

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  late ReaderTheme _theme = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(String title, Color current,
      ReaderTheme Function(Color) apply) async {
    final c = await showColorPicker(context, initial: current, title: title);
    if (c != null) setState(() => _theme = apply(c));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이름을 입력하세요')));
      return;
    }
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    await state.saveTheme(_theme.copyWith(name: name));
    state.selectTheme(_theme.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final appText = AppScope.of(context).theme.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '새 테마' : '테마 편집'),
        actions: [
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            style: TextStyle(color: appText),
            decoration: const InputDecoration(labelText: '테마 이름'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _theme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('제1장 미리보기',
                    style: TextStyle(
                        color: _theme.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '다람쥐 헌 쳇바퀴에 타고파. The quick brown fox jumps over the lazy dog. '
                  '0123456789',
                  style: TextStyle(color: _theme.text, fontSize: 16, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _colorTile('배경색', _theme.background,
              () => _pick('배경색', _theme.background,
                  (c) => _theme.copyWith(background: c))),
          _colorTile('글자색', _theme.text,
              () => _pick('글자색', _theme.text, (c) => _theme.copyWith(text: c))),
          _colorTile('강조색', _theme.accent,
              () => _pick('강조색', _theme.accent,
                  (c) => _theme.copyWith(accent: c))),
          SwitchListTile(
            title: Text('어두운 UI', style: TextStyle(color: appText)),
            subtitle: Text('메뉴·대화상자를 어두운 색으로 표시',
                style: TextStyle(color: appText.withValues(alpha: 0.6))),
            value: _theme.dark,
            onChanged: (v) => setState(() => _theme = _theme.copyWith(dark: v)),
          ),
        ],
      ),
    );
  }

  Widget _colorTile(String label, Color color, VoidCallback onTap) {
    final appText = AppScope.of(context).theme.text;
    return ListTile(
      title: Text(label, style: TextStyle(color: appText)),
      subtitle: Text(colorToHex(color),
          style: TextStyle(color: appText.withValues(alpha: 0.6))),
      trailing: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey),
        ),
      ),
      onTap: onTap,
    );
  }
}
