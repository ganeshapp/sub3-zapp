import 'package:flutter_test/flutter_test.dart';
import 'package:sub3/services/ftms_service.dart';

/// Collect everything `hrStream` publishes around [act]. The stream replays
/// the current reading before forwarding live packets, and the replay is
/// asynchronous, so the queue is drained before and after acting.
Future<List<int>> _watchHrStream(void Function() act) async {
  final seen = <int>[];
  final sub = FtmsService.instance.hrStream.listen((r) => seen.add(r.heartRate));
  await pumpEventQueue();
  act();
  await pumpEventQueue();
  await sub.cancel();
  return seen;
}

void main() {
  final svc = FtmsService.instance;

  setUp(() {
    svc.stopHrListening();
    svc.stopTreadmillListening();
  });

  group('A silent sensor stops counting', () {
    // A watch whose battery dies mid-run keeps its GATT link but stops
    // notifying. Replaying the last BPM would write a fabricated heart rate
    // into every TelemetryPoint for the rest of the run, into avg_hr, and
    // into the TCX.
    test('a frozen reading expires instead of being recorded forever',
        () async {
      svc.receiveHrPacketForTest([0x00, 168]);
      expect(svc.lastHr.heartRate, 168);

      final seen = await _watchHrStream(svc.expireHrForTest);

      expect(svc.lastHr.heartRate, 0);
      // The chips are told, so they fall back to `--` instead of 168 bpm.
      expect(seen, [168, 0]);
    });

    test('a fresh packet revives it', () {
      svc.receiveHrPacketForTest([0x00, 168]);
      svc.expireHrForTest();
      svc.receiveHrPacketForTest([0x00, 164]);
      expect(svc.lastHr.heartRate, 164);
    });

    // A watch that keeps broadcasting cadence but has stopped sending HR
    // must not have its dead BPM republished by every RSC packet.
    test('an RSC packet does not resurrect an expired BPM', () {
      svc.receiveHrPacketForTest([0x00, 168]);
      svc.expireHrForTest();

      svc.receiveRscPacketForTest([0x00, 0x00, 0x01, 84]);

      expect(svc.lastHr.heartRate, 0);
      expect(svc.lastHr.cadence, 84);
    });

    test('an explicit disconnect still clears everything', () async {
      svc.receiveHrPacketForTest([0x00, 168]);

      final seen = await _watchHrStream(svc.stopHrListening);

      expect(svc.lastHr.heartRate, 0);
      expect(svc.lastHr.cadence, isNull);
      expect(seen, [168, 0]);
    });
  });
}
