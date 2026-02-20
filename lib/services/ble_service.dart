import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Well-known BLE service UUIDs.
class BleUuids {
  static final ftmsTreadmill = Guid('00001826-0000-1000-8000-00805f9b34fb');
  static final heartRate = Guid('0000180d-0000-1000-8000-00805f9b34fb');
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

  // ── Scanning ──

  /// Start a BLE scan filtered to FTMS and HR service UUIDs.
  /// Results are emitted via [FlutterBluePlus.scanResults].
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (FlutterBluePlus.isScanningNow) return;
    await FlutterBluePlus.startScan(
      withServices: [BleUuids.ftmsTreadmill, BleUuids.heartRate],
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
    } else {
      _hrSensor = device;
      _watchConnection(device, role);
    }
  }

  Future<void> disconnectDevice(BleDeviceRole role) async {
    if (role == BleDeviceRole.treadmill) {
      _treadmillStateSub?.cancel();
      _treadmillStateSub = null;
      await _treadmill?.disconnect();
      _treadmill = null;
    } else {
      _hrStateSub?.cancel();
      _hrStateSub = null;
      await _hrSensor?.disconnect();
      _hrSensor = null;
    }
  }

  // ── Auto-Reconnect Engine ──

  void enableAutoReconnect() => _autoReconnectEnabled = true;
  void disableAutoReconnect() => _autoReconnectEnabled = false;

  void _watchConnection(BluetoothDevice device, BleDeviceRole role) {
    final sub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          _autoReconnectEnabled) {
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

  Future<void> _attemptReconnect(BluetoothDevice device, BleDeviceRole role) async {
    const maxAttempts = 10;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(Duration(seconds: 2 + i)); // progressive back-off
      try {
        await device.connect(autoConnect: false, mtu: null);
        await device.discoverServices();
        return;
      } catch (_) {
        // keep retrying
      }
    }
  }

  // ── Teardown ──

  Future<void> disposeAll() async {
    _autoReconnectEnabled = false;
    _treadmillStateSub?.cancel();
    _hrStateSub?.cancel();
    await _treadmill?.disconnect();
    await _hrSensor?.disconnect();
    _treadmill = null;
    _hrSensor = null;
  }
}
