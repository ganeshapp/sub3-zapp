class WorkoutSession {
  final int? id;
  final DateTime date;
  final String fileName;
  final String type; // 'workout' or 'gpx'
  final int durationSeconds;
  final double distanceKm;
  final double? avgHr;
  final double? avgPace;
  final double? avgSpeed;
  final double? elevationGain;
  final bool isUploadedToStrava;

  const WorkoutSession({
    this.id,
    required this.date,
    required this.fileName,
    required this.type,
    required this.durationSeconds,
    required this.distanceKm,
    this.avgHr,
    this.avgPace,
    this.avgSpeed,
    this.elevationGain,
    this.isUploadedToStrava = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String(),
      'file_name': fileName,
      'type': type,
      'duration_seconds': durationSeconds,
      'distance_km': distanceKm,
      'avg_hr': avgHr,
      'avg_pace': avgPace,
      'avg_speed': avgSpeed,
      'elevation_gain': elevationGain,
      'is_uploaded_to_strava': isUploadedToStrava ? 1 : 0,
    };
  }

  factory WorkoutSession.fromMap(Map<String, dynamic> map) {
    return WorkoutSession(
      id: map['id'] as int?,
      date: DateTime.parse(map['date'] as String),
      fileName: map['file_name'] as String,
      type: map['type'] as String,
      durationSeconds: map['duration_seconds'] as int,
      distanceKm: (map['distance_km'] as num).toDouble(),
      avgHr: (map['avg_hr'] as num?)?.toDouble(),
      avgPace: (map['avg_pace'] as num?)?.toDouble(),
      avgSpeed: (map['avg_speed'] as num?)?.toDouble(),
      elevationGain: (map['elevation_gain'] as num?)?.toDouble(),
      isUploadedToStrava: (map['is_uploaded_to_strava'] as int?) == 1,
    );
  }
}
