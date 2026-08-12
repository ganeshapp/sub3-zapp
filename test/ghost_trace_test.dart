import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/ghost_trace.dart';
import 'package:sub3/models/workout_file.dart';
import 'package:sub3/providers/workout_provider.dart';

/// A straight GPX route [distanceM] metres long.
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

/// A structured workout [durationSeconds] long.
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

/// A run at a constant [metresPerSecond] for [seconds] seconds.
List<double> steadyRun(double metresPerSecond, int seconds) {
  return List<double>.generate(seconds + 1, (i) => i * metresPerSecond);
}

void main() {
  group('GhostTrace.fromDistances', () {
    test('keeps one sample per second for a short run', () {
      final trace = GhostTrace.fromDistances(steadyRun(3, 10))!;
      expect(trace.stepSeconds, 1);
      expect(trace.totalSeconds, 10);
      expect(trace.metres.length, 11);
      expect(trace.totalMetres, 30);
    });

    test('downsamples a long run to at most 1800 points, finish included', () {
      // Two hours at 3 m/s — 7201 per-second samples.
      final trace = GhostTrace.fromDistances(steadyRun(3, 7200))!;
      expect(trace.metres.length, lessThanOrEqualTo(GhostTrace.maxSamples));
      expect(trace.stepSeconds, greaterThan(1));
      expect(trace.totalSeconds, 7200);
      // The real finish survives the thinning.
      expect(trace.totalMetres, closeTo(21600, 0.1));
    });

    test('a run of exactly 1800 seconds still fits without thinning', () {
      final trace = GhostTrace.fromDistances(steadyRun(3, 1799))!;
      expect(trace.stepSeconds, 1);
      expect(trace.metres.length, GhostTrace.maxSamples);
    });

    test('a run too short to race gives no trace', () {
      expect(GhostTrace.fromDistances([]), isNull);
      expect(GhostTrace.fromDistances([0]), isNull);
    });
  });

  group('GhostTrace encode/decode', () {
    test('round-trips through JSON', () {
      final trace = GhostTrace.fromDistances(steadyRun(2.5, 20))!;
      final restored = GhostTrace.decode(trace.toJson())!;
      expect(restored.stepSeconds, trace.stepSeconds);
      expect(restored.totalSeconds, trace.totalSeconds);
      expect(restored.metres, trace.metres);
    });

    test('reads a bare array as one sample per second', () {
      final trace = GhostTrace.decode('[0,3,6,9]')!;
      expect(trace.stepSeconds, 1);
      expect(trace.totalSeconds, 3);
      expect(trace.distanceAt(2), 6);
    });

    test('never throws on a missing or broken trace', () {
      expect(GhostTrace.decode(null), isNull);
      expect(GhostTrace.decode(''), isNull);
      expect(GhostTrace.decode('not json'), isNull);
      expect(GhostTrace.decode('{"step":1}'), isNull);
      expect(GhostTrace.decode('{"step":1,"m":[0]}'), isNull);
      expect(GhostTrace.decode('{"step":0,"m":[0,1]}'), isNull);
      expect(GhostTrace.decode('{"step":1,"m":[0,"x"]}'), isNull);
      expect(GhostTrace.decode('[1]'), isNull);
    });
  });

  group('GhostTrace.distanceAt', () {
    final trace = GhostTrace.fromDistances(steadyRun(3, 10))!;

    test('interpolates between samples', () {
      expect(trace.distanceAt(0), 0);
      expect(trace.distanceAt(5), closeTo(15, 0.001));
      expect(trace.distanceAt(5.5), closeTo(16.5, 0.001));
    });

    test('freezes at the finish once the trace ends', () {
      expect(trace.distanceAt(10), 30);
      expect(trace.distanceAt(11), 30);
      expect(trace.distanceAt(99999), 30);
    });

    test('never goes backwards before the start', () {
      expect(trace.distanceAt(-5), 0);
    });

    test('works on a downsampled trace', () {
      final long = GhostTrace.fromDistances(steadyRun(3, 7200))!;
      expect(long.distanceAt(3600), closeTo(10800, 10));
      expect(long.distanceAt(7200), closeTo(21600, 0.1));
    });
  });

  group('GhostTrace.timeAtDistance', () {
    final trace = GhostTrace.fromDistances(steadyRun(3, 10))!;

    test('finds when the ghost passed a distance', () {
      expect(trace.timeAtDistance(0), 0);
      expect(trace.timeAtDistance(15), closeTo(5, 0.001));
      expect(trace.timeAtDistance(16.5), closeTo(5.5, 0.001));
      expect(trace.timeAtDistance(30), closeTo(10, 0.001));
    });

    test('is null past the furthest point the ghost reached', () {
      expect(trace.timeAtDistance(30.5), isNull);
      expect(trace.timeAtDistance(9999), isNull);
    });

    test('handles a stalled ghost without dividing by zero', () {
      // Ghost stands still for two seconds in the middle.
      final stalled =
          GhostTrace.fromDistances([0, 3, 6, 6, 6, 9])!;
      expect(stalled.timeAtDistance(6), 2);
      expect(stalled.distanceAt(3), 6);
    });
  });

  group('Ghost delta', () {
    // PR: 3 m/s for 100 s = 300 m.
    final trace = GhostTrace.fromDistances(steadyRun(3, 100))!;

    test('is positive when you are ahead of the PR', () {
      // 150 m covered in 40 s; the ghost took 50 s to get here.
      final delta = trace.deltaAt(elapsedSeconds: 40, distanceM: 150);
      expect(delta, closeTo(10, 0.001));
    });

    test('is negative when you are behind the PR', () {
      // 150 m covered in 60 s; the ghost was here at 50 s.
      final delta = trace.deltaAt(elapsedSeconds: 60, distanceM: 150);
      expect(delta, closeTo(-10, 0.001));
    });

    test('is null once you are past the ghost\'s furthest point', () {
      expect(trace.deltaAt(elapsedSeconds: 120, distanceM: 310), isNull);
    });

    test('knows when the ghost has finished', () {
      expect(trace.hasFinishedBy(99), false);
      expect(trace.hasFinishedBy(100), true);
      expect(trace.hasFinishedBy(101), true);
    });
  });

  group('Ghost on the live workout state', () {
    final trace = GhostTrace.fromDistances(steadyRun(3, 100))!;

    ActiveWorkoutState raceState({
      required int elapsed,
      required double distanceKm,
      GhostTrace? ghost,
    }) {
      return ActiveWorkoutState(
        workoutFile: routeFile(300),
        ghost: ghost,
      ).copyWith(elapsedSeconds: elapsed, totalDistanceKm: distanceKm);
    }

    test('no ghost means no dot and no chip', () {
      final s = raceState(elapsed: 40, distanceKm: 0.15);
      expect(s.ghostProgress, isNull);
      expect(s.ghostDeltaSeconds, isNull);
      expect(s.ghostFinished, false);
    });

    test('ghost progress is a fraction of the route', () {
      final s = raceState(elapsed: 50, distanceKm: 0.1, ghost: trace);
      expect(s.ghostProgress, closeTo(0.5, 0.001));
    });

    test('ghost progress freezes at the finish line', () {
      final s = raceState(elapsed: 500, distanceKm: 0.2, ghost: trace);
      expect(s.ghostProgress, 1.0);
      expect(s.ghostFinished, true);
    });

    test('delta is whole seconds, ahead positive and behind negative', () {
      expect(
        raceState(elapsed: 40, distanceKm: 0.15, ghost: trace)
            .ghostDeltaSeconds,
        10,
      );
      expect(
        raceState(elapsed: 60, distanceKm: 0.15, ghost: trace)
            .ghostDeltaSeconds,
        -10,
      );
    });

    test('a ghost is never armed for a structured workout', () {
      final s = ActiveWorkoutState(workoutFile: workoutFile(1800), ghost: trace)
          .copyWith(elapsedSeconds: 50);
      // The route fraction needs a route distance, which a workout has none of.
      expect(s.ghostProgress, isNull);
    });

    test('copyWith keeps the ghost armed', () {
      final s = raceState(elapsed: 10, distanceKm: 0.05, ghost: trace)
          .copyWith(elapsedSeconds: 20);
      expect(s.ghost, isNotNull);
      expect(s.ghostProgress, closeTo(0.2, 0.001));
    });
  });
}
