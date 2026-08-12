import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/library_item.dart';
import 'package:sub3/models/telemetry.dart';
import 'package:sub3/models/workout_file.dart';
import 'package:sub3/models/workout_session.dart';
import 'package:sub3/providers/workout_provider.dart';
import 'package:sub3/services/tcx_file_manager.dart';
import 'package:sub3/services/tcx_generator.dart';
import 'package:sub3/services/ftms_service.dart';

/// A GPX route of [distanceM] metres along a straight line.
WorkoutFile routeFile(double distanceM) {
  return WorkoutFile(
    name: 'route1152412195.gpx',
    displayName: 'Hillview (Rail Corridor) to Holland V',
    isGpx: true,
    gpxPoints: [
      const GpxPoint(lat: 1.0, lon: 103.0, elevation: 10, cumulativeDistanceM: 0),
      GpxPoint(
          lat: 1.01, lon: 103.0, elevation: 20, cumulativeDistanceM: distanceM),
    ],
    smoothedElevations: const [10, 20],
  );
}

/// A structured workout of [durationSeconds] seconds.
WorkoutFile workoutFile(int durationSeconds) {
  return WorkoutFile(
    name: 'tempo_5k.json',
    displayName: 'Tempo 5K',
    isGpx: false,
    intervals: [
      WorkoutInterval(
        durationSeconds: durationSeconds,
        speedKmh: 12,
        inclinePct: 1,
      ),
    ],
  );
}

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
        displayName: 'Marathon Hills',
        type: 'gpx',
        durationSeconds: 3600,
        distanceKm: 10.5,
        avgHr: 155,
        avgSpeed: 10.5,
      );
      final restored = WorkoutSession.fromMap(session.toMap());
      expect(restored.fileName, session.fileName);
      expect(restored.displayName, 'Marathon Hills');
      expect(restored.durationSeconds, session.durationSeconds);
      expect(restored.distanceKm, session.distanceKm);
    });

    test('title uses the stored display name', () {
      final session = WorkoutSession(
        date: DateTime(2026, 2, 21),
        fileName: 'route1152412195.gpx',
        displayName: 'Hillview (Rail Corridor) to Holland V',
        type: 'gpx',
        durationSeconds: 3600,
        distanceKm: 10.5,
      );
      expect(session.title, 'Hillview (Rail Corridor) to Holland V');
    });

    test('title falls back to a prettified file name', () {
      final session = WorkoutSession(
        date: DateTime(2026, 2, 21),
        fileName: 'tempo_5k_progression.json',
        type: 'workout',
        durationSeconds: 1800,
        distanceKm: 5,
      );
      expect(session.title, 'tempo 5k progression');
    });

    test('prettifyFileName strips the extension and underscores', () {
      expect(WorkoutSession.prettifyFileName('easy_run.gpx'), 'easy run');
      expect(WorkoutSession.prettifyFileName('hill_repeats.json'),
          'hill repeats');
      expect(WorkoutSession.prettifyFileName('route1152412195.gpx'),
          'route1152412195');
    });
  });

  group('Completion rule', () {
    test('route counts only at 99% of the distance', () {
      final state = ActiveWorkoutState(workoutFile: routeFile(10000));
      expect(state.copyWith(totalDistanceKm: 0.5).routeCompleted, false);
      expect(state.copyWith(totalDistanceKm: 9.8).routeCompleted, false);
      expect(state.copyWith(totalDistanceKm: 9.9).routeCompleted, true);
      expect(state.copyWith(totalDistanceKm: 10.4).routeCompleted, true);
    });

    test('structured workout counts only at 99% of the duration', () {
      final state = ActiveWorkoutState(workoutFile: workoutFile(1800));
      expect(state.copyWith(elapsedSeconds: 300).workoutCompleted, false);
      expect(state.copyWith(elapsedSeconds: 1781).workoutCompleted, false);
      expect(state.copyWith(elapsedSeconds: 1782).workoutCompleted, true);
      expect(state.copyWith(elapsedSeconds: 1800).workoutCompleted, true);
    });

    test('the two rules never apply to the other file type', () {
      final route = ActiveWorkoutState(workoutFile: routeFile(10000))
          .copyWith(totalDistanceKm: 10, elapsedSeconds: 10);
      expect(route.workoutCompleted, false);
      expect(route.earnedCompletion, true);

      final workout = ActiveWorkoutState(workoutFile: workoutFile(1800))
          .copyWith(elapsedSeconds: 1800, totalDistanceKm: 0.1);
      expect(workout.routeCompleted, false);
      expect(workout.earnedCompletion, true);
    });

    test('a quit-early run earns nothing', () {
      final route = ActiveWorkoutState(workoutFile: routeFile(7800))
          .copyWith(totalDistanceKm: 0.5);
      expect(route.earnedCompletion, false);

      final workout = ActiveWorkoutState(workoutFile: workoutFile(1800))
          .copyWith(elapsedSeconds: 600);
      expect(workout.earnedCompletion, false);
    });

    test('a route with no distance never completes', () {
      final state = ActiveWorkoutState(workoutFile: routeFile(0))
          .copyWith(totalDistanceKm: 5);
      expect(state.routeCompleted, false);
      expect(state.earnedCompletion, false);
    });
  });

  group('TCX export names', () {
    test('keeps readable characters and drops the rest', () {
      expect(
        TcxFileManager.safeFileName(
            'Sub3_Hillview (Rail Corridor) to Holland V_2026-02-21'),
        'Sub3_Hillview _Rail Corridor_ to Holland V_2026-02-21',
      );
      expect(TcxFileManager.safeFileName('Sub3_Tempo 5K_2026-02-21'),
          'Sub3_Tempo 5K_2026-02-21');
    });

    test('never produces an empty name', () {
      expect(TcxFileManager.safeFileName(''), 'Sub3_run');
      expect(TcxFileManager.safeFileName('///'), 'Sub3_run');
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
