enum LibraryItemType { workout, gpx }

class LibraryItem {
  final int? id;
  final String name;
  final LibraryItemType type;
  final String? filePath;
  final int completionCount;
  final int? bestTimeSeconds;
  final String? sha;
  final String? metadataJson;
  final String? previewPoints;

  /// JSON list of cumulative metres, one sample per second, from the run that
  /// set the current best time. Used to race a ghost on routes.
  final String? prTrace;

  const LibraryItem({
    this.id,
    required this.name,
    required this.type,
    this.filePath,
    this.completionCount = 0,
    this.bestTimeSeconds,
    this.sha,
    this.metadataJson,
    this.previewPoints,
    this.prTrace,
  });

  bool get isDownloaded => filePath != null;
  bool get hasCachedPreview => metadataJson != null && previewPoints != null;

  LibraryItem copyWith({
    int? id,
    String? name,
    LibraryItemType? type,
    String? filePath,
    int? completionCount,
    int? bestTimeSeconds,
    String? sha,
    String? metadataJson,
    String? previewPoints,
    String? prTrace,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      completionCount: completionCount ?? this.completionCount,
      bestTimeSeconds: bestTimeSeconds ?? this.bestTimeSeconds,
      sha: sha ?? this.sha,
      metadataJson: metadataJson ?? this.metadataJson,
      previewPoints: previewPoints ?? this.previewPoints,
      prTrace: prTrace ?? this.prTrace,
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
      'sha': sha,
      'metadata_json': metadataJson,
      'preview_points': previewPoints,
      'pr_trace': prTrace,
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
      sha: map['sha'] as String?,
      metadataJson: map['metadata_json'] as String?,
      previewPoints: map['preview_points'] as String?,
      prTrace: map['pr_trace'] as String?,
    );
  }
}
