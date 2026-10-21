import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'models/reader_theme.dart';
import 'services/font_service.dart';
import 'services/library_service.dart';
import 'services/storage.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final state = AppState(
    store: SharedPrefsStore(),
    library: LibraryService(Directory(p.join(docs.path, 'library'))),
    fonts: FontService(Directory(p.join(docs.path, 'fonts'))),
  );
  await state.load();
  runApp(RuneReaderApp(state: state));
}

class RuneReaderApp extends StatelessWidget {
  const RuneReaderApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'RuneReader',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(state.theme),
          home: const HomePage(),
        ),
      ),
    );
  }
}

/// Derives the Material theme for app chrome from a reader theme.
ThemeData buildMaterialTheme(ReaderTheme theme) {
  final scheme = ColorScheme.fromSeed(
    seedColor: theme.accent,
    brightness: theme.dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: theme.background,
    appBarTheme: AppBarTheme(
      backgroundColor: theme.background,
      foregroundColor: theme.text,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
