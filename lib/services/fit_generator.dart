import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';

import '../models/telemetry.dart';

/// Generates a FIT activity file from the 1-second telemetry array.
///
/// The session is tagged `sport: running` + `subSport: virtualActivity`,
/// which is what makes a hand-uploaded file land on Strava as a
/// **Virtual Run** — TCX cannot express "virtual" at all. The TCX
/// generator stays alongside as the proven fallback.
class FitGenerator {
  /// Seconds between the Unix epoch and the FIT epoch (1989-12-31T00:00:00Z).
  ///
  /// fit_tool's `date_time` fields take milliseconds since the Unix epoch and
  /// do this conversion themselves; only the Activity message's raw
  /// `local_timestamp` needs it done by hand.
  static const int fitEpochOffsetSeconds = 631065600;

  /// The Activity message's `local_timestamp` is a raw uint32: seconds since
  /// the FIT epoch shifted by the device's UTC offset, so importers can tell
  /// what time of day the run happened.
  static int localFitTimestamp(DateTime endUtc, Duration utcOffset) {
    return endUtc.millisecondsSinceEpoch ~/ 1000 -
        fitEpochOffsetSeconds +
        utcOffset.inSeconds;
  }

  /// FIT stores positions as sint32 semicircles (deg × 2^31 / 180) and
  /// fit_tool rounds to the nearest semicircle. A longitude within half a
  /// semicircle of +180° (~9 mm at the antimeridian) would round to
  /// 0x7FFFFFFF — the sint32 "invalid" sentinel, which decoders drop — so
  /// wrap it to −180°, the same meridian. Latitude tops out at ±90° and
  /// can never reach the sentinel.
  static double safeLongitude(double degrees) =>
      (degrees * 2147483648 / 180).round() >= 2147483647 ? -180.0 : degrees;

  static Uint8List generate({
    required DateTime startTime,
    required List<TelemetryPoint> telemetry,
    required double totalDistanceM,
    required int totalTimeSeconds,
    required double elevationGainM,
  }) {
    final startUtc = startTime.toUtc();
    final startMs = startUtc.millisecondsSinceEpoch;
    final endMs = startMs + totalTimeSeconds * 1000;

    // Lap/session averages, from the same readings the records carry:
    // zero heart rate means "no strap", zero cadence means "no sensor".
    final hrs = [
      for (final tp in telemetry)
        if (tp.heartRate != null && tp.heartRate! > 0) tp.heartRate!,
    ];
    final cadences = [
      for (final tp in telemetry)
        if (tp.cadence != null && tp.cadence! > 0) tp.cadence!,
    ];

    final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

    builder.add(FileIdMessage()
      ..type = FileType.activity
      ..manufacturer = Manufacturer.development.value
      ..product = 0
      ..timeCreated = startMs
      // 'SUB3' in ASCII — any stable value works.
      ..serialNumber = 0x53554233);

    builder.add(DeviceInfoMessage()
      ..timestamp = startMs
      ..manufacturer = Manufacturer.development.value
      ..productName = 'Sub3');

    builder.add(EventMessage()
      ..event = Event.timer
      ..eventType = EventType.start
      ..timestamp = startMs);

    for (final tp in telemetry) {
      final record = RecordMessage()
        ..timestamp = startMs + tp.elapsedSeconds * 1000
        ..distance = tp.cumulativeDistanceKm * 1000
        ..speed = tp.speedKmh / 3.6; // km/h → m/s
      // fit_tool takes degrees and scales to semicircles (2^31 / 180) itself.
      if (tp.latitude != null && tp.longitude != null) {
        record.positionLat = tp.latitude;
        record.positionLong = safeLongitude(tp.longitude!);
      }
      if (tp.altitude != null) {
        record.altitude = tp.altitude;
      }
      if (tp.heartRate != null && tp.heartRate! > 0) {
        record.heartRate = tp.heartRate!.round();
      }
      if (tp.cadence != null && tp.cadence! > 0) {
        // Same single-leg steps-per-minute the TCX exports as RunCadence.
        record.cadence = tp.cadence;
      }
      builder.add(record);
    }

    builder.add(EventMessage()
      ..event = Event.timer
      ..eventType = EventType.stopAll
      ..timestamp = endMs);

    final lap = LapMessage()
      ..messageIndex = 0
      ..timestamp = endMs
      ..startTime = startMs
      ..event = Event.lap
      ..eventType = EventType.stop
      ..totalElapsedTime = totalTimeSeconds.toDouble()
      ..totalTimerTime = totalTimeSeconds.toDouble()
      ..totalDistance = totalDistanceM;
    if (hrs.isNotEmpty) {
      lap.avgHeartRate = _mean(hrs).round();
      lap.maxHeartRate = hrs.reduce((a, b) => a > b ? a : b).round();
    }
    if (cadences.isNotEmpty) {
      lap.avgCadence = _mean(cadences).round();
    }
    builder.add(lap);

    final session = SessionMessage()
      ..messageIndex = 0
      ..timestamp = endMs
      ..startTime = startMs
      ..event = Event.session
      ..eventType = EventType.stop
      ..sport = Sport.running
      ..subSport = SubSport.virtualActivity
      ..totalElapsedTime = totalTimeSeconds.toDouble()
      ..totalTimerTime = totalTimeSeconds.toDouble()
      ..totalDistance = totalDistanceM
      ..totalAscent = elevationGainM.round()
      ..firstLapIndex = 0
      ..numLaps = 1;
    if (hrs.isNotEmpty) {
      session.avgHeartRate = _mean(hrs).round();
      session.maxHeartRate = hrs.reduce((a, b) => a > b ? a : b).round();
    }
    if (cadences.isNotEmpty) {
      session.avgCadence = _mean(cadences).round();
    }
    builder.add(session);

    builder.add(ActivityMessage()
      ..timestamp = endMs
      ..totalTimerTime = totalTimeSeconds.toDouble()
      ..numSessions = 1
      ..localTimestamp = localFitTimestamp(
          DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
          startTime.timeZoneOffset));

    return Uint8List.fromList(builder.build().toBytes());
  }

  static double _mean(List<num> values) =>
      values.fold<double>(0, (sum, v) => sum + v) / values.length;
}
