enum LibraryItemType { workout, gpx }

class LibraryItem {
  final int? id;
  final String name;
  final LibraryItemType type;
  final String? filePath;
  final int completionCount;
  final int? bestTimeSeconds;

  const LibraryItem({
    this.id,
    required this.name,
    required this.type,
    this.filePath,
    this.completionCount = 0,
    this.bestTimeSeconds,
  });

  bool get isDownloaded => filePath != null;

  LibraryItem copyWith({
    int? id,
    String? name,
    LibraryItemType? type,
    String? filePath,
    int? completionCount,
    int? bestTimeSeconds,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      completionCount: completionCount ?? this.completionCount,
      bestTimeSeconds: bestTimeSeconds ?? this.bestTimeSeconds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type.name,
      'file_path': filePath,
      'completion_count': completionCount,
      'best_time_seconds': bestTimeSeconds,
    };
  }

  factory LibraryItem.fromMap(Map<String, dynamic> map) {
    return LibraryItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: LibraryItemType.values.byName(map['type'] as String),
      filePath: map['file_path'] as String?,
      completionCount: (map['completion_count'] as int?) ?? 0,
      bestTimeSeconds: map['best_time_seconds'] as int?,
    );
  }
}
