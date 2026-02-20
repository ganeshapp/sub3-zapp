import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/library_item.dart';
import 'package:sub3/models/telemetry.dart';
import 'package:sub3/models/workout_session.dart';
import 'package:sub3/services/tcx_generator.dart';
import 'package:sub3/services/ftms_service.dart';

void main() {
  group('LibraryItem', () {
    test('round-trips through toMap/fromMap', () {
      const item = LibraryItem(
        id: 1,
        name: 'tempo_5k.json',
        type: LibraryItemType.workout,
        filePath: '/data/workouts/tempo_5k.json',
        completionCount: 3,
      );
      final restored = LibraryItem.fromMap(item.toMap());
      expect(restored.name, item.name);
      expect(restored.type, item.type);
      expect(restored.filePath, item.filePath);
      expect(restored.completionCount, item.completionCount);
      expect(restored.isDownloaded, true);
    });

    test('isDownloaded is false when filePath is null', () {
      const item = LibraryItem(name: 'test.gpx', type: LibraryItemType.gpx);
      expect(item.isDownloaded, false);
    });
  });

  group('WorkoutSession', () {
    test('round-trips through toMap/fromMap', () {
      final session = WorkoutSession(
        date: DateTime(2026, 2, 21),
        fileName: 'marathon_hills.gpx',
        type: 'gpx',
        durationSeconds: 3600,
        distanceKm: 10.5,
        avgHr: 155,
        avgSpeed: 10.5,
        isUploadedToStrava: true,
      );
      final restored = WorkoutSession.fromMap(session.toMap());
      expect(restored.fileName, session.fileName);
      expect(restored.durationSeconds, session.durationSeconds);
      expect(restored.distanceKm, session.distanceKm);
      expect(restored.isUploadedToStrava, true);
    });
  });

  group('TcxGenerator', () {
    test('generates valid TCX with required elements', () {
      final telemetry = [
        const TelemetryPoint(
          elapsedSeconds: 1,
          heartRate: 145,
          cadence: 170,
          speedKmh: 12.0,
          inclinePct: 1.0,
          cumulativeDistanceKm: 0.0033,
        ),
        const TelemetryPoint(
          elapsedSeconds: 2,
          heartRate: 148,
          cadence: 172,
          speedKmh: 12.5,
          inclinePct: 1.5,
          cumulativeDistanceKm: 0.0068,
        ),
      ];

      final tcx = TcxGenerator.generate(
        startTime: DateTime.utc(2026, 2, 21, 12, 0, 0),
        telemetry: telemetry,
        totalDistanceM: 6.8,
        totalTimeSeconds: 2,
      );

      expect(tcx, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(tcx, contains('TrainingCenterDatabase'));
      expect(tcx, contains('Sub3 App with barometer'));
      expect(tcx, contains('Sport="Running"'));
      expect(tcx, contains('<TotalTimeSeconds>2.0</TotalTimeSeconds>'));
      expect(tcx, contains('<DistanceMeters>6.8</DistanceMeters>'));
      expect(tcx, contains('<Intensity>Active</Intensity>'));

      // HR inside proper tags
      expect(tcx, contains('<HeartRateBpm>'));
      expect(tcx, contains('<Value>145</Value>'));

      // Speed and Cadence inside Extensions/TPX namespace
      expect(tcx, contains('xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"'));
      expect(tcx, contains('<Speed>'));
      expect(tcx, contains('<RunCadence>170</RunCadence>'));

      // Speed in m/s (12.0 km/h = 3.33 m/s)
      expect(tcx, contains('<Speed>3.33</Speed>'));

      // ISO 8601 UTC timestamps
      expect(tcx, contains('2026-02-21T12:00:00.000Z'));
      expect(tcx, contains('2026-02-21T12:00:01.000Z'));
    });

    test('omits HR when null', () {
      final telemetry = [
        const TelemetryPoint(
          elapsedSeconds: 1,
          speedKmh: 10.0,
          inclinePct: 0,
          cumulativeDistanceKm: 0.0028,
        ),
      ];

      final tcx = TcxGenerator.generate(
        startTime: DateTime.utc(2026, 1, 1),
        telemetry: telemetry,
        totalDistanceM: 2.8,
        totalTimeSeconds: 1,
      );

      expect(tcx, isNot(contains('<HeartRateBpm>')));
      expect(tcx, isNot(contains('<RunCadence>')));
    });
  });

  group('FtmsService incline clamping', () {
    test('direct 1:1 mapping', () {
      expect(FtmsService.clampInclineToLevel(0), 0);
      expect(FtmsService.clampInclineToLevel(1.0), 1);
      expect(FtmsService.clampInclineToLevel(5.0), 5);
      expect(FtmsService.clampInclineToLevel(10.0), 10);
      expect(FtmsService.clampInclineToLevel(18.0), 18);
    });

    test('clamps above 18 to 18', () {
      expect(FtmsService.clampInclineToLevel(20.0), 18);
      expect(FtmsService.clampInclineToLevel(25.5), 18);
    });

    test('clamps below 0 to 0', () {
      expect(FtmsService.clampInclineToLevel(-1.0), 0);
      expect(FtmsService.clampInclineToLevel(-5.0), 0);
    });

    test('rounds fractional values', () {
      expect(FtmsService.clampInclineToLevel(4.4), 4);
      expect(FtmsService.clampInclineToLevel(4.5), 5);
      expect(FtmsService.clampInclineToLevel(4.6), 5);
      expect(FtmsService.clampInclineToLevel(0.3), 0);
    });
  });
}
