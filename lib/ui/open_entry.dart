import 'package:flutter/material.dart';

import '../models/book.dart';
import 'image_viewer_page.dart';
import 'text_reader_page.dart';

/// Opens a library entry in the matching viewer.
Future<void> openEntry(BuildContext context, LibraryEntry entry) {
  final page = entry.kind == BookKind.text
      ? TextReaderPage(entryId: entry.id)
      : ImageViewerPage(entryId: entry.id);
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => page));
}
