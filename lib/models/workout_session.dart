class WorkoutSession {
  final int? id;
  final DateTime date;
  final String fileName;

  /// Human-readable name of the workout or route (the same name the Library
  /// shows). Null for rows saved before the column existed; the database
  /// service back-fills those at read time.
  final String? displayName;

  final String type; // 'workout' or 'gpx'
  final int durationSeconds;
  final double distanceKm;
  final double? avgHr;
  final double? avgPace;
  final double? avgSpeed;
  final double? elevationGain;

  const WorkoutSession({
    this.id,
    required this.date,
    required this.fileName,
    this.displayName,
    required this.type,
    required this.durationSeconds,
    required this.distanceKm,
    this.avgHr,
    this.avgPace,
    this.avgSpeed,
    this.elevationGain,
  });

  /// Name to show in history rows and export file names. Falls back to a
  /// prettified file name when nothing better is known.
  String get title {
    final name = displayName;
    if (name != null && name.isNotEmpty) return name;
    return prettifyFileName(fileName);
  }

  /// Strip the extension and turn underscores into spaces.
  static String prettifyFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'\.(json|gpx)$'), '')
        .replaceAll('_', ' ')
        .trim();
  }

  WorkoutSession copyWith({String? displayName}) {
    return WorkoutSession(
      id: id,
      date: date,
      fileName: fileName,
      displayName: displayName ?? this.displayName,
      type: type,
      durationSeconds: durationSeconds,
      distanceKm: distanceKm,
      avgHr: avgHr,
      avgPace: avgPace,
      avgSpeed: avgSpeed,
      elevationGain: elevationGain,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String(),
      'file_name': fileName,
      'display_name': displayName,
      'type': type,
      'duration_seconds': durationSeconds,
      'distance_km': distanceKm,
      'avg_hr': avgHr,
      'avg_pace': avgPace,
      'avg_speed': avgSpeed,
      'elevation_gain': elevationGain,
    };
  }

  factory WorkoutSession.fromMap(Map<String, dynamic> map) {
    return WorkoutSession(
      id: map['id'] as int?,
      date: DateTime.parse(map['date'] as String),
      fileName: map['file_name'] as String,
      displayName: map['display_name'] as String?,
      type: map['type'] as String,
      durationSeconds: map['duration_seconds'] as int,
      distanceKm: (map['distance_km'] as num).toDouble(),
      avgHr: (map['avg_hr'] as num?)?.toDouble(),
      avgPace: (map['avg_pace'] as num?)?.toDouble(),
      avgSpeed: (map['avg_speed'] as num?)?.toDouble(),
      elevationGain: (map['elevation_gain'] as num?)?.toDouble(),
    );
  }
}
