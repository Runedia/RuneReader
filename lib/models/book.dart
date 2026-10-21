enum BookKind { text, images, archive }

/// A reading position in a text document: a paragraph and a character offset
/// inside it.
class ReadingPosition {
  const ReadingPosition(this.paragraph, [this.offset = 0]);

  final int paragraph;
  final int offset;

  Map<String, Object?> toJson() => {'p': paragraph, 'o': offset};

  static ReadingPosition fromJson(Object? json) {
    if (json is Map) {
      final p = json['p'];
      final o = json['o'];
      return ReadingPosition(p is int ? p : 0, o is int ? o : 0);
    }
    return const ReadingPosition(0);
  }

  int compareTo(ReadingPosition other) => paragraph != other.paragraph
      ? paragraph.compareTo(other.paragraph)
      : offset.compareTo(other.offset);

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.paragraph == paragraph &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(paragraph, offset);

  @override
  String toString() => 'ReadingPosition($paragraph, $offset)';
}

class Bookmark {
  const Bookmark({
    required this.position,
    required this.label,
    required this.createdAt,
  });

  /// Text position for text books; `paragraph` holds the page index for
  /// image books.
  final ReadingPosition position;
  final String label;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'position': position.toJson(),
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, Object?> json) => Bookmark(
        position: ReadingPosition.fromJson(json['position']),
        label: json['label'] is String ? json['label'] as String : '',
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}

/// A file imported into the app library.
class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.path,
    required this.addedAt,
    this.lastOpenedAt,
    this.progress = 0,
    this.position = const ReadingPosition(0),
    this.encoding,
    this.bookmarks = const [],
  });

  final String id;
  final String title;
  final BookKind kind;

  /// File path (text, archive) or directory path (image set) inside the
  /// app library directory.
  final String path;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  /// Reading progress from 0 to 1.
  final double progress;
  final ReadingPosition position;

  /// Encoding override name (see `TextEncodingKind`); null means auto.
  final String? encoding;
  final List<Bookmark> bookmarks;

  LibraryEntry copyWith({
    String? title,
    DateTime? lastOpenedAt,
    double? progress,
    ReadingPosition? position,
    String? encoding,
    bool clearEncoding = false,
    List<Bookmark>? bookmarks,
  }) {
    return LibraryEntry(
      id: id,
      title: title ?? this.title,
      kind: kind,
      path: path,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      progress: progress ?? this.progress,
      position: position ?? this.position,
      encoding: clearEncoding ? null : (encoding ?? this.encoding),
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'path': path,
        'addedAt': addedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'progress': progress,
        'position': position.toJson(),
        'encoding': encoding,
        'bookmarks': [for (final b in bookmarks) b.toJson()],
      };

  factory LibraryEntry.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = BookKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => BookKind.text,
    );
    final progress = json['progress'];
    final marks = json['bookmarks'];
    return LibraryEntry(
      id: '${json['id']}',
      title: '${json['title']}',
      kind: kind,
      path: '${json['path']}',
      addedAt: DateTime.tryParse('${json['addedAt']}') ?? DateTime.now(),
      lastOpenedAt: json['lastOpenedAt'] is String
          ? DateTime.tryParse(json['lastOpenedAt'] as String)
          : null,
      progress: progress is num ? progress.toDouble().clamp(0, 1) : 0,
      position: ReadingPosition.fromJson(json['position']),
      encoding: json['encoding'] is String ? json['encoding'] as String : null,
      bookmarks: marks is List
          ? [
              for (final m in marks)
                if (m is Map) Bookmark.fromJson(m.cast<String, Object?>()),
            ]
          : const [],
    );
  }
}
