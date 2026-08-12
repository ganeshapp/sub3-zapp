import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ftms_service.dart';

/// Well-known BLE service UUIDs.
class BleUuids {
  static final ftmsTreadmill = Guid('00001826-0000-1000-8000-00805f9b34fb');
  static final heartRate = Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final runningSpeedCadence = Guid('00001814-0000-1000-8000-00805f9b34fb');
}

enum BleDeviceRole { treadmill, heartRate }

/// Lightweight snapshot of a discovered BLE device and which role it can fill.
class DiscoveredDevice {
  final BluetoothDevice device;
  final String name;
  final BleDeviceRole role;

  const DiscoveredDevice({
    required this.device,
    required this.name,
    required this.role,
  });
}

/// Manages BLE scanning, connections, and auto-reconnect for exactly
/// one treadmill and one heart-rate sensor.
class BleService {
  BleService._();
  static final instance = BleService._();

  // ── Connected devices ──
  BluetoothDevice? _treadmill;
  BluetoothDevice? _hrSensor;

  BluetoothDevice? get treadmill => _treadmill;
  BluetoothDevice? get hrSensor => _hrSensor;

  // ── Auto-reconnect subscriptions ──
  StreamSubscription? _treadmillStateSub;
  StreamSubscription? _hrStateSub;

  bool _autoReconnectEnabled = false;
  bool get autoReconnectEnabled => _autoReconnectEnabled;

  final Map<BleDeviceRole, bool> _reconnecting = {
    BleDeviceRole.treadmill: false,
    BleDeviceRole.heartRate: false,
  };

  bool isReconnecting(BleDeviceRole role) => _reconnecting[role] ?? false;

  /// A paired HR sensor is brought back whatever the app is doing — a watch
  /// that drops out between runs has to be back before the next one starts.
  /// The treadmill only reconnects while a workout is running.
  bool willAutoReconnect(BleDeviceRole role) =>
      role == BleDeviceRole.heartRate || _autoReconnectEnabled;

  /// Fired when a role starts/stops a reconnect loop, so the UI can show a
  /// "reconnecting" chip instead of silently dropping the device. Set by the
  /// connected-devices notifier.
  void Function(BleDeviceRole role, bool reconnecting)? onReconnectingChanged;

  /// Fired once a dropped device is back and re-subscribed. The workout
  /// engine uses it to forget the last speed/incline it sent, because a
  /// treadmill that reset its target on disconnect would otherwise never be
  /// re-commanded for the rest of the segment. Set by the workout notifier.
  void Function(BleDeviceRole role)? onReconnected;

  // ── Scanning ──

  /// Start a BLE scan filtered to FTMS and HR service UUIDs.
  /// Results are emitted via [FlutterBluePlus.scanResults].
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (FlutterBluePlus.isScanningNow) return;
    await FlutterBluePlus.startScan(
      withServices: [BleUuids.ftmsTreadmill, BleUuids.heartRate, BleUuids.runningSpeedCadence],
      timeout: timeout,
      androidUsesFineLocation: false,
    );
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  /// Classify a scan result by its advertised service UUIDs.
  static BleDeviceRole? classifyDevice(ScanResult result) {
    final uuids = result.advertisementData.serviceUuids;
    if (uuids.contains(BleUuids.ftmsTreadmill)) return BleDeviceRole.treadmill;
    if (uuids.contains(BleUuids.heartRate)) return BleDeviceRole.heartRate;
    return null;
  }

  // ── Connection ──

  Future<void> connectDevice(BluetoothDevice device, BleDeviceRole role) async {
    await device.connect(autoConnect: false, mtu: null);
    await device.discoverServices();

    if (role == BleDeviceRole.treadmill) {
      _treadmill = device;
      _watchConnection(device, role);
      // Treadmill notifications belong to a workout; the engine subscribes
      // when one starts.
    } else {
      _hrSensor = device;
      _watchConnection(device, role);
      // Subscribe to the HR characteristic the moment the sensor connects,
      // and keep it up for the rest of the app session: a watch drops the
      // link when nobody is listening, and the status chips want a live BPM.
      try {
        await FtmsService.instance.startHrListening();
      } catch (_) {
        // The sensor is connected either way; notifications retry on the
        // next reconnect.
      }
    }
  }

  Future<void> disconnectDevice(BleDeviceRole role) async {
    if (role == BleDeviceRole.treadmill) {
      _treadmillStateSub?.cancel();
      _treadmillStateSub = null;
      _reconnecting[role] = false;
      await _treadmill?.disconnect();
      _treadmill = null;
      FtmsService.instance.stopTreadmillListening();
    } else {
      _hrStateSub?.cancel();
      _hrStateSub = null;
      _reconnecting[role] = false;
      await _hrSensor?.disconnect();
      _hrSensor = null;
      // The only place the HR subscription is ever torn down.
      FtmsService.instance.stopHrListening();
    }
  }

  // ── Auto-Reconnect Engine ──

  void enableAutoReconnect() => _autoReconnectEnabled = true;
  void disableAutoReconnect() => _autoReconnectEnabled = false;

  void _watchConnection(BluetoothDevice device, BleDeviceRole role) {
    final sub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          willAutoReconnect(role)) {
        _attemptReconnect(device, role);
      }
    });

    if (role == BleDeviceRole.treadmill) {
      _treadmillStateSub?.cancel();
      _treadmillStateSub = sub;
    } else {
      _hrStateSub?.cancel();
      _hrStateSub = sub;
    }
  }

  /// False once the user has disconnected this device or paired another in
  /// its place — a reconnect loop in flight must not drag it back.
  bool _stillPaired(BluetoothDevice device, BleDeviceRole role) {
    final current =
        role == BleDeviceRole.treadmill ? _treadmill : _hrSensor;
    return current != null && current.remoteId == device.remoteId;
  }

  Future<void> _attemptReconnect(BluetoothDevice device, BleDeviceRole role) async {
    if (_reconnecting[role] == true) return;
    _reconnecting[role] = true;
    onReconnectingChanged?.call(role, true);

    const maxAttempts = 10;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(Duration(seconds: 2 + i)); // progressive back-off
      if (!willAutoReconnect(role) || !_stillPaired(device, role)) break;
      try {
        await device.connect(autoConnect: false, mtu: null);
        await device.discoverServices();

        // Disconnecting invalidates the characteristic handles, so
        // notifications have to be re-enabled before anyone is told the
        // device is back — otherwise the HR sensor reconnects mute.
        try {
          if (role == BleDeviceRole.heartRate) {
            await FtmsService.instance.startHrListening();
          } else {
            await FtmsService.instance.startTreadmillListening();
            await FtmsService.instance.requestControl();
          }
        } catch (_) {}

        _reconnecting[role] = false;
        onReconnectingChanged?.call(role, false);
        onReconnected?.call(role);
        return;
      } catch (_) {
        // keep retrying
      }
    }

    // Out of attempts. Drop the HR subscription that died with the link so
    // `isHrListening` stops lying and a later run can re-subscribe.
    if (role == BleDeviceRole.heartRate) {
      FtmsService.instance.stopHrListening();
    }
    _reconnecting[role] = false;
    onReconnectingChanged?.call(role, false);
  }

  // ── Teardown ──

  Future<void> disposeAll() async {
    _autoReconnectEnabled = false;
    _reconnecting[BleDeviceRole.treadmill] = false;
    _reconnecting[BleDeviceRole.heartRate] = false;
    _treadmillStateSub?.cancel();
    _hrStateSub?.cancel();
    await _treadmill?.disconnect();
    await _hrSensor?.disconnect();
    _treadmill = null;
    _hrSensor = null;
    FtmsService.instance.dispose();
  }
}
