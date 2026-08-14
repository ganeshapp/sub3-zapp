import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ble_service.dart';
import '../services/ftms_service.dart';

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

// ── Live heart rate ──

/// The heart rate coming off the paired sensor right now, or null until the
/// first packet arrives. Fed by the subscription BleService opens when the
/// sensor connects, so it keeps ticking across navigation and workouts.
final liveHeartRateProvider = StreamProvider<int?>((ref) {
  return FtmsService.instance.hrStream
      .map((reading) => reading.heartRate > 0 ? reading.heartRate : null);
});

// ── Connected device state ──

class ConnectedDevicesState {
  final BluetoothDevice? treadmill;
  final BluetoothDevice? hrSensor;
  final BluetoothConnectionState treadmillState;
  final BluetoothConnectionState hrSensorState;
  final bool isConnectingTreadmill;
  final bool isConnectingHr;

  /// True while the auto-reconnect engine is bringing a dropped device back.
  /// The device keeps its slot so the UI can say "Reconnecting..." instead of
  /// pretending the sensor was never paired.
  final bool isReconnectingTreadmill;
  final bool isReconnectingHr;

  const ConnectedDevicesState({
    this.treadmill,
    this.hrSensor,
    this.treadmillState = BluetoothConnectionState.disconnected,
    this.hrSensorState = BluetoothConnectionState.disconnected,
    this.isConnectingTreadmill = false,
    this.isConnectingHr = false,
    this.isReconnectingTreadmill = false,
    this.isReconnectingHr = false,
  });

  bool get isTreadmillConnected =>
      treadmill != null && treadmillState == BluetoothConnectionState.connected;
  bool get isHrConnected =>
      hrSensor != null && hrSensorState == BluetoothConnectionState.connected;

  ConnectedDevicesState copyWith({
    BluetoothDevice? treadmill,
    BluetoothDevice? hrSensor,
    BluetoothConnectionState? treadmillState,
    BluetoothConnectionState? hrSensorState,
    bool? isConnectingTreadmill,
    bool? isConnectingHr,
    bool? isReconnectingTreadmill,
    bool? isReconnectingHr,
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
      isReconnectingTreadmill:
          isReconnectingTreadmill ?? this.isReconnectingTreadmill,
      isReconnectingHr: isReconnectingHr ?? this.isReconnectingHr,
    );
  }
}

class ConnectedDevicesNotifier extends Notifier<ConnectedDevicesState> {
  StreamSubscription? _treadmillSub;
  StreamSubscription? _hrSub;

  @override
  ConnectedDevicesState build() {
    BleService.instance.onReconnectingChanged = _handleReconnectingChanged;
    return const ConnectedDevicesState();
  }

  void _handleReconnectingChanged(BleDeviceRole role, bool reconnecting) {
    if (role == BleDeviceRole.treadmill) {
      if (reconnecting) {
        state = state.copyWith(isReconnectingTreadmill: true);
      } else {
        final back = BleService.instance.treadmill?.isConnected ?? false;
        state = back
            ? state.copyWith(
                isReconnectingTreadmill: false,
                treadmillState: BluetoothConnectionState.connected,
              )
            : state.copyWith(
                isReconnectingTreadmill: false,
                clearTreadmill: true,
                treadmillState: BluetoothConnectionState.disconnected,
              );
      }
    } else {
      if (reconnecting) {
        state = state.copyWith(isReconnectingHr: true);
      } else {
        final back = BleService.instance.hrSensor?.isConnected ?? false;
        state = back
            ? state.copyWith(
                isReconnectingHr: false,
                hrSensorState: BluetoothConnectionState.connected,
              )
            : state.copyWith(
                isReconnectingHr: false,
                clearHrSensor: true,
                hrSensorState: BluetoothConnectionState.disconnected,
              );
      }
    }
  }

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
          if (connState == BluetoothConnectionState.disconnected) {
            if (BleService.instance.willAutoReconnect(role)) {
              // Keep the slot filled; the reconnect engine is on it and will
              // clear the flag through onReconnectingChanged.
              state = state.copyWith(
                treadmillState: connState,
                isReconnectingTreadmill: true,
              );
            } else {
              state = state.copyWith(
                clearTreadmill: true,
                treadmillState: BluetoothConnectionState.disconnected,
                isReconnectingTreadmill: false,
              );
            }
          } else {
            state = state.copyWith(
              treadmillState: connState,
              isReconnectingTreadmill: false,
            );
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
          if (connState == BluetoothConnectionState.disconnected) {
            if (BleService.instance.willAutoReconnect(role)) {
              state = state.copyWith(
                hrSensorState: connState,
                isReconnectingHr: true,
              );
            } else {
              state = state.copyWith(
                clearHrSensor: true,
                hrSensorState: BluetoothConnectionState.disconnected,
                isReconnectingHr: false,
              );
            }
          } else {
            state = state.copyWith(
              hrSensorState: connState,
              isReconnectingHr: false,
            );
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
        isReconnectingTreadmill: false,
      );
    } else {
      _hrSub?.cancel();
      _hrSub = null;
      state = state.copyWith(
        clearHrSensor: true,
        hrSensorState: BluetoothConnectionState.disconnected,
        isReconnectingHr: false,
      );
    }
  }
}

final connectedDevicesProvider =
    NotifierProvider<ConnectedDevicesNotifier, ConnectedDevicesState>(
  ConnectedDevicesNotifier.new,
);

// ── Ready to start ──

/// What a refused start says, wherever it is refused, so the Library and the
/// engine never explain themselves differently.
const treadmillRequiredMessage =
    'Connect your treadmill first — there is nothing to record without it.';

/// The Library device strip's call to action while nothing is paired.
const connectTreadmillCallToAction = 'Connect your treadmill to start a run';

/// The treadmill must be connected before a session can start: without it
/// there is no speed to record and nothing to control, and the run saves as a
/// row of zeros.
///
/// A device that is still connecting — or reconnecting after a drop — is not
/// ready either: starting mid-handshake gives the same empty run. The heart
/// rate sensor is deliberately not considered; a run without a strap is still
/// a run.
final canStartSessionProvider = Provider<bool>((ref) {
  final devices = ref.watch(connectedDevicesProvider);
  if (devices.isConnectingTreadmill || devices.isReconnectingTreadmill) {
    return false;
  }
  return devices.isTreadmillConnected;
});
