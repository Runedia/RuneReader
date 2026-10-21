import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rune_reader/app_state.dart';
import 'package:rune_reader/main.dart';
import 'package:rune_reader/services/font_service.dart';
import 'package:rune_reader/services/library_service.dart';
import 'package:rune_reader/services/storage.dart';

void main() {
  testWidgets('empty library shows the open hint and theme switching works',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('rr_widget_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = AppState(
      store: MemoryStore(),
      library: LibraryService(Directory(p.join(tmp.path, 'library'))),
      fonts: FontService(Directory(p.join(tmp.path, 'fonts')),
          systemFontDirs: const []),
    );
    await tester.runAsync(state.load);

    await tester.pumpWidget(RuneReaderApp(state: state));
    expect(find.textContaining('서재가 비어 있습니다'), findsOneWidget);
    expect(find.text('가져오기'), findsOneWidget);
    expect(find.text('폴더'), findsOneWidget); // bottom navigation

    state.selectTheme('dark');
    await tester.pump();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, isNull); // uses theme background
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xFF121212));
    // Let the debounced settings write finish.
    await tester.pump(const Duration(seconds: 1));
  });
}
