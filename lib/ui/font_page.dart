import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/font_service.dart';

const _sample = '가나다라 ABC abc 123 — 다람쥐 헌 쳇바퀴에 타고파.';

/// Lists built-in, user, and system fonts. Tapping a font selects it for
/// the reader.
class FontPage extends StatefulWidget {
  const FontPage({super.key});

  @override
  State<FontPage> createState() => _FontPageState();
}

class _FontPageState extends State<FontPage> {
  List<FontEntry> _user = const [];
  List<FontEntry> _system = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final fonts = AppScope.read(context).fonts;
    final user = await fonts.userFonts();
    final system = await fonts.systemFonts();
    if (!mounted) return;
    setState(() {
      _user = user;
      _system = system;
      _loading = false;
    });
  }

  Future<void> _import() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf', 'ttc', 'otc'],
      );
      FontEntry? last;
      for (final f in files) {
        last = await state.fonts.importFont(f.name, await f.readAsBytes());
      }
      await _reload();
      if (last != null) {
        _select(last);
        messenger.showSnackBar(
            SnackBar(content: Text('${files.length}개 글꼴을 추가했습니다')));
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('글꼴 추가 실패: $e')));
    }
  }

  void _select(FontEntry entry) {
    final state = AppScope.read(context);
    state.updateSettings(state.settings.copyWith(fontId: entry.id));
  }

  Future<void> _delete(FontEntry entry) async {
    final state = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('글꼴 삭제'),
        content: Text('"${entry.label}" 글꼴 파일을 앱에서 삭제합니다.'),
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
    if (ok != true) return;
    if (state.settings.fontId == entry.id) {
      state.updateSettings(state.settings.copyWith(fontId: 'system'));
    }
    await state.fonts.deleteUserFont(entry);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = state.theme.text;
    final selected = state.settings.fontId;
    final q = _query.toLowerCase();
    final system = q.isEmpty
        ? _system
        : _system.where((f) => f.label.toLowerCase().contains(q)).toList();

    Widget header(String title, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: state.theme.accent,
                        fontWeight: FontWeight.bold)),
              ),
              ?trailing,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('글꼴')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header('기본')),
                SliverList.list(children: [
                  for (final f in FontService.builtIns)
                    _FontTile(
                      entry: f,
                      selected: f.id == selected,
                      onTap: () => _select(f),
                      showPreview: true,
                    ),
                ]),
                SliverToBoxAdapter(
                  child: header(
                    '사용자 글꼴 (TTF / OTF / TTC)',
                    trailing: TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.add),
                      label: const Text('추가'),
                    ),
                  ),
                ),
                if (_user.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('추가한 글꼴이 없습니다.',
                          style: TextStyle(color: text.withValues(alpha: 0.6))),
                    ),
                  ),
                SliverList.list(children: [
                  for (final f in _user)
                    _FontTile(
                      entry: f,
                      selected: f.id == selected,
                      onTap: () => _select(f),
                      onDelete: () => _delete(f),
                      showPreview: true,
                    ),
                ]),
                SliverToBoxAdapter(
                    child: header('시스템 글꼴 파일 (${_system.length})')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: TextStyle(color: text),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '이름 검색 (예: NotoSansCJK, Roboto)',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: system.length,
                  itemBuilder: (context, i) => _FontTile(
                    entry: system[i],
                    selected: system[i].id == selected,
                    onTap: () => _select(system[i]),
                    showPreview: system[i].id == selected,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.showPreview,
    this.onDelete,
  });

  final FontEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = state.theme.text;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? state.theme.accent : text.withValues(alpha: 0.4),
      ),
      title: Text(entry.label, style: TextStyle(color: text)),
      subtitle: showPreview
          ? FutureBuilder<String?>(
              future: state.fonts.resolveFamily(entry.id),
              builder: (context, snap) => Text(
                snap.connectionState == ConnectionState.done
                    ? _sample
                    : '불러오는 중…',
                style: TextStyle(
                  color: text.withValues(alpha: 0.75),
                  fontFamily: snap.data,
                  fontSize: 16,
                ),
              ),
            )
          : null,
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: '삭제',
              icon: Icon(Icons.delete_outline, color: text),
              onPressed: onDelete,
            ),
    );
  }
}
