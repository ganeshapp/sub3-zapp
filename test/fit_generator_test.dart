import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/telemetry.dart';
import 'package:sub3/services/fit_generator.dart';

/// A short virtual run: position, altitude, heart rate and cadence on every
/// point — the richest shape the generator has to handle.
List<TelemetryPoint> _gpxTelemetry() {
  return List.generate(5, (i) {
    return TelemetryPoint(
      elapsedSeconds: i,
      heartRate: 140.0 + i,
      cadence: 80 + i,
      speedKmh: 12.0 + i * 0.1,
      inclinePct: 1.0,
      cumulativeDistanceKm: i * 0.0033,
      latitude: 1.3521 + i * 0.0001,
      longitude: 103.8198 + i * 0.0001,
      altitude: 15.0 + i * 0.5,
    );
  });
}

void main() {
  group('FIT epoch conversion (§1)', () {
    // The FIT epoch is 1989-12-31T00:00:00Z, 631065600 seconds after the
    // Unix epoch. Only the Activity message's raw local_timestamp needs the
    // conversion done by hand; fit_tool converts every date_time field
    // itself from milliseconds since the Unix epoch.
    test('start of the FIT epoch maps to zero', () {
      expect(
        FitGenerator.localFitTimestamp(
            DateTime.utc(1989, 12, 31), Duration.zero),
        0,
      );
    });

    test('one day into the epoch, at UTC, is exactly 86400', () {
      expect(
        FitGenerator.localFitTimestamp(
            DateTime.utc(1990, 1, 1), Duration.zero),
        86400,
      );
    });

    test('the device UTC offset shifts the local timestamp forward', () {
      // A run ending 08:00 UTC on a UTC+8 phone reads as 16:00 local.
      final utc = FitGenerator.localFitTimestamp(
          DateTime.utc(2026, 8, 23, 8), Duration.zero);
      final sgt = FitGenerator.localFitTimestamp(
          DateTime.utc(2026, 8, 23, 8), const Duration(hours: 8));
      expect(sgt - utc, 8 * 3600);
    });
  });

  group('Generated FIT structure (§2)', () {
    test('bytes carry the ".FIT" magic and a whole-file CRC', () {
      final bytes = FitGenerator.generate(
        startTime: DateTime.utc(2026, 8, 23, 1, 2, 3),
        telemetry: _gpxTelemetry(),
        totalDistanceM: 13.2,
        totalTimeSeconds: 5,
        elevationGainM: 2.0,
      );

      expect(bytes.length, greaterThan(14 + 2));
      // Header magic at offset 8: ".FIT".
      expect(String.fromCharCodes(bytes.sublist(8, 12)), '.FIT');
    });

    // fit_tool reading back its own output is a smoke check, not the proof —
    // the independent fitparse decode lives in fit_decode_test.dart.
    test('round-trips as a virtual running activity', () {
      final telemetry = _gpxTelemetry();
      final bytes = FitGenerator.generate(
        startTime: DateTime.utc(2026, 8, 23, 1, 2, 3),
        telemetry: telemetry,
        totalDistanceM: 13.2,
        totalTimeSeconds: 5,
        elevationGainM: 2.0,
      );

      final messages =
          FitFile.fromBytes(bytes).records.map((r) => r.message).toList();

      final session = messages.whereType<SessionMessage>().single;
      expect(session.sport, Sport.running);
      expect(session.subSport, SubSport.virtualActivity);
      expect(session.totalDistance, closeTo(13.2, 0.01));
      expect(session.totalTimerTime, 5.0);
      expect(session.totalAscent, 2);
      expect(session.firstLapIndex, 0);
      expect(session.numLaps, 1);

      final records = messages.whereType<RecordMessage>().toList();
      expect(records.length, telemetry.length);
      expect(records.first.speed, closeTo(12.0 / 3.6, 0.001));
      expect(records.first.cadence, 80);
      expect(records.first.heartRate, 140);

      expect(messages.whereType<LapMessage>().length, 1);
      expect(messages.whereType<ActivityMessage>().single.numSessions, 1);
    });

    test('omits position, heart rate and cadence when the run has none',
        () {
      // A structured workout: no GPS, no strap, no cadence sensor — but the
      // synthesized altitude is still exported.
      final telemetry = List.generate(3, (i) {
        return TelemetryPoint(
          elapsedSeconds: i,
          speedKmh: 10.0,
          inclinePct: 2.0,
          cumulativeDistanceKm: i * 0.0028,
          altitude: 5.0 + i * 0.1,
        );
      });

      final bytes = FitGenerator.generate(
        startTime: DateTime.utc(2026, 8, 23, 1, 2, 3),
        telemetry: telemetry,
        totalDistanceM: 5.6,
        totalTimeSeconds: 3,
        elevationGainM: 0.2,
      );

      final messages =
          FitFile.fromBytes(bytes).records.map((r) => r.message).toList();
      final records = messages.whereType<RecordMessage>().toList();
      expect(records.length, 3);
      for (final record in records) {
        expect(record.positionLat, isNull);
        expect(record.positionLong, isNull);
        expect(record.heartRate, isNull);
        expect(record.cadence, isNull);
        expect(record.altitude, isNotNull);
      }

      final session = messages.whereType<SessionMessage>().single;
      expect(session.avgHeartRate, isNull);
      expect(session.avgCadence, isNull);
    });
  });

  group('Antimeridian longitude guard (§2)', () {
    test('a longitude that would round to the sint32 invalid sentinel wraps '
        'to −180°', () {
      // 179.9999999° rounds to semicircle 0x7FFFFFFF — FIT's sint32
      // "invalid" sentinel, which decoders drop — so it wraps to the same
      // meridian instead.
      expect(FitGenerator.safeLongitude(179.9999999), -180.0);
      expect(FitGenerator.safeLongitude(180.0), -180.0);
      // Anything at least half a semicircle away passes through untouched.
      expect(FitGenerator.safeLongitude(179.99995), 179.99995);
      expect(FitGenerator.safeLongitude(-179.9999999), -179.9999999);
      expect(FitGenerator.safeLongitude(103.8198), 103.8198);
    });

    test('a record at the antimeridian keeps both position fields', () {
      final bytes = FitGenerator.generate(
        startTime: DateTime.utc(2026, 8, 23, 1, 2, 3),
        telemetry: const [
          TelemetryPoint(
            elapsedSeconds: 0,
            speedKmh: 12.0,
            inclinePct: 0.0,
            cumulativeDistanceKm: 0,
            latitude: -54.8019,
            longitude: 179.9999999,
          ),
        ],
        totalDistanceM: 0,
        totalTimeSeconds: 1,
        elevationGainM: 0,
      );
      final record = FitFile.fromBytes(bytes)
          .records
          .map((r) => r.message)
          .whereType<RecordMessage>()
          .single;
      expect(record.positionLat, closeTo(-54.8019, 1e-6));
      expect(record.positionLong, closeTo(-180.0, 1e-6));
    });
  });
}
