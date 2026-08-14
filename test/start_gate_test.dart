import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/models/library_item.dart';
import 'package:sub3/models/workout_file.dart';
import 'package:sub3/providers/ble_provider.dart';
import 'package:sub3/providers/library_provider.dart';
import 'package:sub3/providers/workout_provider.dart';
import 'package:sub3/screens/device_pairing_screen.dart';
import 'package:sub3/screens/library_screen.dart';
import 'package:sub3/services/ble_service.dart';

/// wakelock_plus talks to the host over this pigeon channel. Mocking it is
/// the only way to see whether a refused start still woke the screen.
const _wakelockToggleChannel =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

final _treadmill = BluetoothDevice.fromId('06:E5:28:3B:FD:E0');
final _strap = BluetoothDevice.fromId('06:E5:28:3B:FD:E1');

WorkoutFile _workout() => WorkoutFile(
      name: 'tempo_5k.json',
      displayName: 'Tempo 5K',
      isGpx: false,
      intervals: [
        WorkoutInterval(durationSeconds: 1800, speedKmh: 12, inclinePct: 1),
      ],
    );

class _FixedDevices extends ConnectedDevicesNotifier {
  _FixedDevices(this.fixed);
  final ConnectedDevicesState fixed;

  @override
  ConnectedDevicesState build() => fixed;

  /// Plug the treadmill in mid-test, the way a real connect does.
  void publish(ConnectedDevicesState next) => state = next;
}

class _FixedWorkouts extends WorkoutsNotifier {
  _FixedWorkouts(this.items);
  final List<LibraryItem> items;

  @override
  Future<List<LibraryItem>> build() async => items;
}

class _FixedRuns extends VirtualRunsNotifier {
  _FixedRuns(this.items);
  final List<LibraryItem> items;

  @override
  Future<List<LibraryItem>> build() async => items;
}

/// Records what the Library pushed, so the route can be inspected without
/// mounting it.
class _RecordPushes extends NavigatorObserver {
  _RecordPushes(this.pushed);
  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

/// A downloaded workout with a cached (empty) preview, so the card draws
/// straight from cache instead of spinning forever.
LibraryItem _workoutItem(int i) => LibraryItem(
      name: 'workout_$i.json',
      type: LibraryItemType.workout,
      filePath: '/tmp/workout_$i.json',
      metadataJson: '{"name":"Workout $i","totalDurationSeconds":1800}',
      previewPoints: '[]',
    );

/// A treadmill that is connected and nothing else.
ConnectedDevicesState _connected() => ConnectedDevicesState(
      treadmill: _treadmill,
      treadmillState: BluetoothConnectionState.connected,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What the Library and the engine both ask before a run.
  bool canStart(ConnectedDevicesState devices) {
    final container = ProviderContainer(overrides: [
      connectedDevicesProvider.overrideWith(() => _FixedDevices(devices)),
    ]);
    addTearDown(container.dispose);
    return container.read(canStartSessionProvider);
  }

  group('Can we start? (§1)', () {
    test('a connected treadmill is ready', () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.connected,
        )),
        isTrue,
      );
    });

    test('nothing paired is not ready', () {
      expect(canStart(const ConnectedDevicesState()), isFalse);
    });

    // Mid-handshake there is no control point and no data stream yet, so a
    // run started here records exactly as much as no run at all.
    test('connecting is not ready', () {
      expect(
        canStart(const ConnectedDevicesState(isConnectingTreadmill: true)),
        isFalse,
      );
    });

    test('reconnecting is not ready', () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.disconnected,
          isReconnectingTreadmill: true,
        )),
        isFalse,
      );
    });

    // A drop is seen by two listeners, so the reconnect flag can be raised
    // while the connection state still reads `connected`. That window must
    // not be startable either.
    test('reconnecting outranks a connection state that has not caught up',
        () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.connected,
          isReconnectingTreadmill: true,
        )),
        isFalse,
      );
    });

    test('a treadmill that dropped for good is not ready', () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.disconnected,
        )),
        isFalse,
      );
    });
  });

  group('The heart rate sensor is never part of it (§1)', () {
    test('no strap does not stop a run', () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.connected,
        )),
        isTrue,
      );
    });

    test('a strap still reconnecting does not stop a run', () {
      expect(
        canStart(ConnectedDevicesState(
          treadmill: _treadmill,
          treadmillState: BluetoothConnectionState.connected,
          hrSensor: _strap,
          hrSensorState: BluetoothConnectionState.disconnected,
          isReconnectingHr: true,
        )),
        isTrue,
      );
    });

    test('a connected strap does not make up for a missing treadmill', () {
      expect(
        canStart(ConnectedDevicesState(
          hrSensor: _strap,
          hrSensorState: BluetoothConnectionState.connected,
        )),
        isFalse,
      );
    });
  });

  group('The engine refuses a run it cannot record (§2)', () {
    late int wakelockCalls;

    setUp(() {
      wakelockCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_wakelockToggleChannel, (message) async {
        wakelockCalls++;
        return const StandardMessageCodec().encodeMessage(<Object?>[null]);
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_wakelockToggleChannel, null);
      // BleService is a singleton; leave it as the next test expects it.
      BleService.instance.disableAutoReconnect();
      BleService.instance.onReconnected = null;
    });

    ProviderContainer containerWith({required bool ready}) {
      final container = ProviderContainer(overrides: [
        canStartSessionProvider.overrideWithValue(ready),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('with no treadmill it returns false and touches nothing', () async {
      final container = containerWith(ready: false);

      final started = await container
          .read(activeWorkoutProvider.notifier)
          .startWorkout(_workout());
      await pumpEventQueue();

      expect(started, isFalse);
      expect(container.read(activeWorkoutProvider), isNull,
          reason: 'a refused start must not publish a session of zeros');
      expect(wakelockCalls, 0,
          reason: 'the screen was held awake for a run that never began');
      expect(BleService.instance.autoReconnectEnabled, isFalse);
      expect(BleService.instance.onReconnected, isNull,
          reason: 'the reconnect hook was wired up for nothing');
    });

    test('with a connected treadmill it starts as it always did', () async {
      final container = containerWith(ready: true);

      final started = await container
          .read(activeWorkoutProvider.notifier)
          .startWorkout(_workout());
      await pumpEventQueue();

      expect(started, isTrue);
      expect(container.read(activeWorkoutProvider), isNotNull);
      expect(wakelockCalls, 1);
      expect(BleService.instance.autoReconnectEnabled, isTrue);
      expect(BleService.instance.onReconnected, isNotNull);

      // Stop the 1-second tick before the container goes away.
      container.read(activeWorkoutProvider.notifier).clear();
    });
  });

  // ── §3: the Library's half — greyed, but never mute ──
  //
  // The greyed play icon is drawn disabled while the card underneath keeps
  // taking the tap, so the refusal always gets said. That is the half of the
  // change with no unit test to protect it, so it is pinned here.
  group('The Library while nothing is paired (§3)', () {
    /// iPhone SE / 8 — the smallest screen sub3 supports.
    void useSmallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<_FixedDevices> pumpLibrary(
      WidgetTester tester, {
      ConnectedDevicesState? devices,
      int workouts = 1,
      List<NavigatorObserver> observers = const [],
    }) async {
      useSmallPhone(tester);
      final fake = _FixedDevices(devices ?? const ConnectedDevicesState());

      await tester.pumpWidget(ProviderScope(
        overrides: [
          connectedDevicesProvider.overrideWith(() => fake),
          workoutsProvider.overrideWith(
            () => _FixedWorkouts(
                [for (var i = 0; i < workouts; i++) _workoutItem(i)]),
          ),
          virtualRunsProvider.overrideWith(() => _FixedRuns(const [])),
        ],
        child: MaterialApp(
          navigatorObservers: observers,
          home: const Scaffold(body: LibraryScreen()),
        ),
      ));
      await tester.pump(); // the library list resolves off a Future
      return fake;
    }

    Finder pairInSnackBar() => find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Pair'),
        );

    Color? playIconColor(WidgetTester tester) => tester
        .widget<Icon>(find.byIcon(Icons.play_circle_filled).first)
        .color;

    testWidgets('the strip is the call to action and the play icon is dead',
        (tester) async {
      await pumpLibrary(tester);

      expect(find.text(connectTreadmillCallToAction), findsOneWidget);
      expect(find.text('Pair'), findsOneWidget);
      expect(playIconColor(tester), Colors.white.withValues(alpha: 0.20));
    });

    testWidgets('a tap on the greyed play icon says why, exactly once',
        (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.text('Workout 0'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(treadmillRequiredMessage), findsOneWidget);
      expect(pairInSnackBar(), findsOneWidget);
    });

    testWidgets('the refusal replaces itself instead of queueing',
        (tester) async {
      await pumpLibrary(tester, workouts: 2);

      // A rider poking at dead play buttons, at about the rate a rider pokes.
      for (final label in ['Workout 0', 'Workout 1', 'Workout 0']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.byType(SnackBar), findsOneWidget);

      // One replaced message drains in about five seconds; three queued 4 s
      // messages take the better part of fifteen.
      var drain = Duration.zero;
      const step = Duration(milliseconds: 100);
      while (find.byType(SnackBar).evaluate().isNotEmpty &&
          drain < const Duration(seconds: 30)) {
        await tester.pump(step);
        drain += step;
      }
      expect(drain, lessThan(const Duration(seconds: 8)),
          reason: 'the same sentence must not replay for a quarter of a '
              'minute over the bottom of the list');
    });

    testWidgets('Pair still works after its card has scrolled away',
        (tester) async {
      // The SnackBar outlives the card that raised it: 4 seconds is plenty of
      // time to fling the list past the 250 px cache extent, and a list item
      // that has been deactivated can no longer look up its Navigator.
      final pushed = <Route<dynamic>>[];
      await pumpLibrary(tester,
          workouts: 30, observers: [_RecordPushes(pushed)]);

      await tester.tap(find.text('Workout 0'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pump();
      expect(find.text('Workout 0'), findsNothing,
          reason: 'the card that raised the SnackBar is gone from the tree');

      final here = tester.element(find.byType(LibraryScreen));
      pushed.clear();
      await tester.tap(pairInSnackBar());

      // Deliberately not pumped: DevicePairingScreen would start a BLE scan
      // the test host cannot serve. The push is the whole assertion anyway —
      // a deactivated context throws inside the action, before any route.
      expect(tester.takeException(), isNull);
      expect(pushed, hasLength(1));
      expect((pushed.single as MaterialPageRoute).builder(here),
          isA<DevicePairingScreen>());
    });

    testWidgets('everything re-enables the moment the treadmill connects',
        (tester) async {
      final devices = await pumpLibrary(tester);
      expect(find.text(connectTreadmillCallToAction), findsOneWidget);

      devices.publish(_connected());
      await tester.pump();

      // The strip goes back to its chips, and the starts come back with it.
      expect(find.text(connectTreadmillCallToAction), findsNothing);
      expect(find.text('Connected'), findsOneWidget);
      expect(playIconColor(tester), isNot(Colors.white.withValues(alpha: 0.20)));

      await tester.tap(find.text('Workout 0'));
      await tester.pump();
      expect(find.text(treadmillRequiredMessage), findsNothing,
          reason: 'the gate is open, so the run is not refused');
    });
  });
}
