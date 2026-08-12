import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/workout_file.dart';
import 'package:sub3/providers/workout_provider.dart';
import 'package:sub3/screens/post_workout_screen.dart';

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

void main() {
  // The post-run screen is wrapped in PopScope(canPop: false) and its AppBar
  // has no back button, so Discard — which deletes the run — is the only other
  // way off it. A save that fails silently strands the runner there.
  //
  // sqflite has no implementation in a widget test, so `insertSession` throws
  // exactly the way it would on a locked or full device.
  group('Save & Exit when the insert fails (§1)', () {
    Future<void> pumpSummary(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeWorkoutProvider.overrideWith(() => _FixedWorkout(
                ActiveWorkoutState(
                  workoutFile: _route(),
                  phase: WorkoutPhase.finished,
                  elapsedSeconds: 1800,
                  totalDistanceKm: 5.0,
                ),
              )),
        ],
        child: const MaterialApp(home: PostWorkoutScreen()),
      ));
      await tester.pump();
    }

    testWidgets('says so instead of doing nothing', (tester) async {
      await pumpSummary(tester);

      await tester.tap(find.text('Save & Exit'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Save failed'), findsOneWidget);
    });

    testWidgets('a second tap reports again rather than dead-ending',
        (tester) async {
      await pumpSummary(tester);

      await tester.tap(find.text('Save & Exit'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Save failed'), findsOneWidget);

      // Dismiss the first snack bar, then retry: the failed save must not be
      // memoized, or every later tap replays the same cached error.
      ScaffoldMessenger.of(tester.element(find.text('Save & Exit')))
          .removeCurrentSnackBar();
      await tester.pump();

      await tester.tap(find.text('Save & Exit'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Save failed'), findsOneWidget);
    });
  });
}
