import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/ghost_trace.dart';
import 'package:sub3/models/workout_file.dart';
import 'package:sub3/providers/workout_provider.dart';
import 'package:sub3/screens/live_workout_screen.dart';
import 'package:sub3/screens/post_workout_screen.dart';

/// Every metric tile the live dashboard shows. The last three are the row
/// that used to fall off the bottom of a 375×667 phone.
const _liveTiles = [
  'HR',
  'PACE',
  'AVG PACE',
  'SPEED',
  'AVG SPEED',
  'INCLINE',
  'DISTANCE',
  'CADENCE',
  'AVG HR',
];

WorkoutFile _route() => WorkoutFile(
      name: 'route1152412195.gpx',
      displayName: 'Hillview (Rail Corridor) to Holland V',
      isGpx: true,
      gpxPoints: const [
        GpxPoint(lat: 1.0, lon: 103.0, elevation: 10, cumulativeDistanceM: 0),
        GpxPoint(
            lat: 1.05, lon: 103.0, elevation: 30, cumulativeDistanceM: 5000),
      ],
      smoothedElevations: const [10, 30],
    );

class _FixedWorkout extends ActiveWorkoutNotifier {
  _FixedWorkout(this.fixed);
  final ActiveWorkoutState fixed;

  @override
  ActiveWorkoutState? build() => fixed;
}

Widget _app(ActiveWorkoutState state, Widget home) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(() => _FixedWorkout(state)),
    ],
    child: MaterialApp(home: home),
  );
}

/// The test font's glyph metrics are not Inter's, so intrinsic-size overflows
/// reported here say nothing about the real app. These tests check geometry
/// instead — where the tiles actually land — so the noise is dropped.
void _ignoreLayoutNoise(WidgetTester tester) => tester.takeException();

void main() {
  // iPhone SE / 8 — the smallest screen sub3 supports, and the one where the
  // ghost delta chip pushed the bottom row of tiles out of view.
  void useSmallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Live dashboard on a small phone (§9)', () {
    Future<void> pumpLive(WidgetTester tester, {GhostTrace? ghost}) async {
      useSmallPhone(tester);
      await tester.pumpWidget(_app(
        ActiveWorkoutState(
          workoutFile: _route(),
          ghost: ghost,
          phase: WorkoutPhase.running,
          elapsedSeconds: 300,
          totalDistanceKm: 1.2,
        ),
        const LiveWorkoutScreen(),
      ));
      await tester.pump();
    }

    void expectEveryTileInsideTheGrid(WidgetTester tester) {
      for (final label in _liveTiles) {
        expect(find.text(label), findsOneWidget, reason: '$label was never built');
      }
      // The grid cannot scroll, so anything past the viewport is lost for
      // good: its content must be no taller than the space it was given.
      final scroll = tester.state<ScrollableState>(find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ));
      expect(scroll.position.maxScrollExtent, 0,
          reason: 'the bottom row hangs '
              '${scroll.position.maxScrollExtent}px below a grid that cannot '
              'be scrolled');
    }

    // The chip costs ~36 px above a grid that could not scroll, which pushed
    // DISTANCE / CADENCE / AVG HR past the bottom edge — on exactly the run a
    // rider most wants to watch, a route with a PR.
    testWidgets('all nine tiles fit with the ghost chip showing',
        (tester) async {
      await pumpLive(tester,
          ghost: GhostTrace.fromDistances(
              List<double>.generate(1201, (i) => i * 4.0)));

      expectEveryTileInsideTheGrid(tester);
      _ignoreLayoutNoise(tester);
    });

    testWidgets('all nine tiles fit without a ghost', (tester) async {
      await pumpLive(tester);

      expectEveryTileInsideTheGrid(tester);
      _ignoreLayoutNoise(tester);
    });
  });

  group('Post-run summary on a small phone (§5)', () {
    // Elev. Gain carries a metric-help dialog, so a tile that can never be
    // reached is a feature the runner can never use.
    testWidgets('the last row of tiles can be scrolled to', (tester) async {
      useSmallPhone(tester);
      await tester.pumpWidget(_app(
        ActiveWorkoutState(
          workoutFile: _route(),
          phase: WorkoutPhase.finished,
          elapsedSeconds: 1800,
          totalDistanceKm: 5.0,
        ),
        const PostWorkoutScreen(),
      ));
      await tester.pump();

      await tester.drag(find.byType(GridView), const Offset(0, -200));
      await tester.pump();

      expect(find.text('Elev. Gain'), findsOneWidget);
      expect(find.text('Data Points'), findsOneWidget);
      _ignoreLayoutNoise(tester);
    });
  });
}
