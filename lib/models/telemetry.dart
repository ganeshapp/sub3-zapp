/// One-second snapshot captured during an active workout.
class TelemetryPoint {
  final int elapsedSeconds;
  final double? heartRate;
  final int? cadence;
  final double speedKmh;
  final double inclinePct;
  final double cumulativeDistanceKm;
  final double? paceMinPerKm;
  final double? latitude;
  final double? longitude;
  final double? altitude;

  const TelemetryPoint({
    required this.elapsedSeconds,
    this.heartRate,
    this.cadence,
    required this.speedKmh,
    required this.inclinePct,
    required this.cumulativeDistanceKm,
    this.paceMinPerKm,
    this.latitude,
    this.longitude,
    this.altitude,
  });
}
