import 'dart:math';

/// A single interval block in a structured JSON workout.
class WorkoutInterval {
  final int durationSeconds;
  final double speedKmh;
  final double inclinePct;

  const WorkoutInterval({
    required this.durationSeconds,
    required this.speedKmh,
    required this.inclinePct,
  });
}

/// A single point along a GPX route.
class GpxPoint {
  final double lat;
  final double lon;
  final double elevation;
  final double cumulativeDistanceM;

  const GpxPoint({
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.cumulativeDistanceM,
  });
}

/// Parsed workout file — either JSON intervals or GPX route.
class WorkoutFile {
  final String name;
  final bool isGpx;

  /// Non-null for JSON workouts.
  final List<WorkoutInterval>? intervals;

  /// Non-null for GPX routes.
  final List<GpxPoint>? gpxPoints;

  /// Smoothed elevation values aligned to [gpxPoints].
  final List<double>? smoothedElevations;

  const WorkoutFile({
    required this.name,
    required this.isGpx,
    this.intervals,
    this.gpxPoints,
    this.smoothedElevations,
  });

  /// Total planned duration for JSON workouts.
  int get totalDurationSeconds =>
      intervals?.fold<int>(0, (sum, i) => sum + i.durationSeconds) ?? 0;

  /// Total route distance for GPX.
  double get totalDistanceM =>
      gpxPoints?.last.cumulativeDistanceM ?? 0;

  /// Haversine distance between two GPS coordinates in meters.
  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
