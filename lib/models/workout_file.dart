import 'dart:math';

/// A single interval block in a structured JSON workout.
class WorkoutInterval {
  final int durationSeconds;
  final double speedKmh;
  final double endSpeedKmh;
  final double inclinePct;
  final double endInclinePct;
  final String type;

  const WorkoutInterval({
    required this.durationSeconds,
    required this.speedKmh,
    double? endSpeedKmh,
    required this.inclinePct,
    double? endInclinePct,
    this.type = 'active',
  })  : endSpeedKmh = endSpeedKmh ?? speedKmh,
        endInclinePct = endInclinePct ?? inclinePct;

  /// Linearly interpolate speed at a given fraction (0.0 = start, 1.0 = end).
  double speedAt(double t) =>
      speedKmh + (endSpeedKmh - speedKmh) * t.clamp(0.0, 1.0);

  /// Linearly interpolate incline at a given fraction.
  double inclineAt(double t) =>
      inclinePct + (endInclinePct - inclinePct) * t.clamp(0.0, 1.0);
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
  final String displayName;
  final bool isGpx;

  /// Non-null for JSON workouts.
  final List<WorkoutInterval>? intervals;

  /// Non-null for GPX routes.
  final List<GpxPoint>? gpxPoints;

  /// Smoothed elevation values aligned to [gpxPoints].
  final List<double>? smoothedElevations;

  const WorkoutFile({
    required this.name,
    required this.displayName,
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

  /// Interpolate elevation (meters) along the GPX route for a given distance.
  double? interpolateElevation(double distanceM) {
    if (gpxPoints == null || gpxPoints!.length < 2) return null;
    final pts = gpxPoints!;

    if (distanceM <= 0) return pts.first.elevation;
    if (distanceM >= pts.last.cumulativeDistanceM) {
      return pts.last.elevation;
    }

    for (var i = 0; i < pts.length - 1; i++) {
      if (pts[i + 1].cumulativeDistanceM >= distanceM) {
        final segLen =
            pts[i + 1].cumulativeDistanceM - pts[i].cumulativeDistanceM;
        if (segLen <= 0) return pts[i].elevation;
        final t = (distanceM - pts[i].cumulativeDistanceM) / segLen;
        return pts[i].elevation +
            (pts[i + 1].elevation - pts[i].elevation) * t;
      }
    }
    return pts.last.elevation;
  }

  /// Interpolate virtual lat/lon position along the GPX route for a given distance.
  (double lat, double lon)? interpolatePosition(double distanceM) {
    if (gpxPoints == null || gpxPoints!.length < 2) return null;
    final pts = gpxPoints!;

    if (distanceM <= 0) return (pts.first.lat, pts.first.lon);
    if (distanceM >= pts.last.cumulativeDistanceM) {
      return (pts.last.lat, pts.last.lon);
    }

    for (var i = 0; i < pts.length - 1; i++) {
      if (pts[i + 1].cumulativeDistanceM >= distanceM) {
        final segLen =
            pts[i + 1].cumulativeDistanceM - pts[i].cumulativeDistanceM;
        if (segLen <= 0) return (pts[i].lat, pts[i].lon);
        final t = (distanceM - pts[i].cumulativeDistanceM) / segLen;
        return (
          pts[i].lat + (pts[i + 1].lat - pts[i].lat) * t,
          pts[i].lon + (pts[i + 1].lon - pts[i].lon) * t,
        );
      }
    }
    return (pts.last.lat, pts.last.lon);
  }
}
