import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';

// ── Adapter state (on/off/unauthorized) ──

final bleAdapterStateProvider = StreamProvider<BluetoothAdapterState>((ref) {
  return FlutterBluePlus.adapterState;
});

// ── Scanning ──

final bleScanningProvider = StreamProvider<bool>((ref) {
  return FlutterBluePlus.isScanning;
});

final bleScanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  return FlutterBluePlus.scanResults;
});

// ── Connected device state ──

class ConnectedDevicesState {
  final BluetoothDevice? treadmill;
  final BluetoothDevice? hrSensor;
  final BluetoothConnectionState treadmillState;
  final BluetoothConnectionState hrSensorState;
  final bool isConnectingTreadmill;
  final bool isConnectingHr;

  const ConnectedDevicesState({
    this.treadmill,
    this.hrSensor,
    this.treadmillState = BluetoothConnectionState.disconnected,
    this.hrSensorState = BluetoothConnectionState.disconnected,
    this.isConnectingTreadmill = false,
    this.isConnectingHr = false,
  });

  ConnectedDevicesState copyWith({
    BluetoothDevice? treadmill,
    BluetoothDevice? hrSensor,
    BluetoothConnectionState? treadmillState,
    BluetoothConnectionState? hrSensorState,
    bool? isConnectingTreadmill,
    bool? isConnectingHr,
    bool clearTreadmill = false,
    bool clearHrSensor = false,
  }) {
    return ConnectedDevicesState(
      treadmill: clearTreadmill ? null : (treadmill ?? this.treadmill),
      hrSensor: clearHrSensor ? null : (hrSensor ?? this.hrSensor),
      treadmillState: treadmillState ?? this.treadmillState,
      hrSensorState: hrSensorState ?? this.hrSensorState,
      isConnectingTreadmill: isConnectingTreadmill ?? this.isConnectingTreadmill,
      isConnectingHr: isConnectingHr ?? this.isConnectingHr,
    );
  }
}

class ConnectedDevicesNotifier extends Notifier<ConnectedDevicesState> {
  StreamSubscription? _treadmillSub;
  StreamSubscription? _hrSub;

  @override
  ConnectedDevicesState build() => const ConnectedDevicesState();

  Future<void> connectDevice(BluetoothDevice device, BleDeviceRole role) async {
    if (role == BleDeviceRole.treadmill) {
      state = state.copyWith(isConnectingTreadmill: true);
    } else {
      state = state.copyWith(isConnectingHr: true);
    }

    try {
      await BleService.instance.connectDevice(device, role);

      if (role == BleDeviceRole.treadmill) {
        _treadmillSub?.cancel();
        _treadmillSub = device.connectionState.listen((connState) {
          state = state.copyWith(treadmillState: connState);
          if (connState == BluetoothConnectionState.disconnected) {
            state = state.copyWith(clearTreadmill: true,
                treadmillState: BluetoothConnectionState.disconnected);
          }
        });
        state = state.copyWith(
          treadmill: device,
          treadmillState: BluetoothConnectionState.connected,
          isConnectingTreadmill: false,
        );
      } else {
        _hrSub?.cancel();
        _hrSub = device.connectionState.listen((connState) {
          state = state.copyWith(hrSensorState: connState);
          if (connState == BluetoothConnectionState.disconnected) {
            state = state.copyWith(clearHrSensor: true,
                hrSensorState: BluetoothConnectionState.disconnected);
          }
        });
        state = state.copyWith(
          hrSensor: device,
          hrSensorState: BluetoothConnectionState.connected,
          isConnectingHr: false,
        );
      }
    } catch (e) {
      if (role == BleDeviceRole.treadmill) {
        state = state.copyWith(isConnectingTreadmill: false);
      } else {
        state = state.copyWith(isConnectingHr: false);
      }
      rethrow;
    }
  }

  Future<void> disconnectDevice(BleDeviceRole role) async {
    await BleService.instance.disconnectDevice(role);
    if (role == BleDeviceRole.treadmill) {
      _treadmillSub?.cancel();
      _treadmillSub = null;
      state = state.copyWith(
        clearTreadmill: true,
        treadmillState: BluetoothConnectionState.disconnected,
      );
    } else {
      _hrSub?.cancel();
      _hrSub = null;
      state = state.copyWith(
        clearHrSensor: true,
        hrSensorState: BluetoothConnectionState.disconnected,
      );
    }
  }
}

final connectedDevicesProvider =
    NotifierProvider<ConnectedDevicesNotifier, ConnectedDevicesState>(
  ConnectedDevicesNotifier.new,
);
