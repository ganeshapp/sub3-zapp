import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

/// FTMS characteristic UUIDs.
class _FtmsUuids {
  static final treadmillData = Guid('00002acd-0000-1000-8000-00805f9b34fb');
  static final controlPoint = Guid('00002ad9-0000-1000-8000-00805f9b34fb');
  static final hrMeasurement = Guid('00002a37-0000-1000-8000-00805f9b34fb');
}

/// Parsed snapshot from the FTMS Treadmill Data characteristic.
class FtmsReading {
  final double speedKmh;
  final double? avgSpeedKmh;
  final double? totalDistanceM;
  final double? inclinePct;

  const FtmsReading({
    required this.speedKmh,
    this.avgSpeedKmh,
    this.totalDistanceM,
    this.inclinePct,
  });
}

/// Parsed heart-rate + optional cadence from the HR Measurement characteristic.
class HrReading {
  final int heartRate;
  final int? cadence;

  const HrReading({required this.heartRate, this.cadence});
}

/// Hardware abstraction layer for FTMS treadmill control and sensor reads.
class FtmsService {
  FtmsService._();
  static final instance = FtmsService._();

  StreamSubscription? _ftmsDataSub;
  StreamSubscription? _hrDataSub;

  FtmsReading _lastFtms = const FtmsReading(speedKmh: 0);
  HrReading _lastHr = const HrReading(heartRate: 0);

  FtmsReading get lastFtms => _lastFtms;
  HrReading get lastHr => _lastHr;

  double _lastCommandedSpeedKmh = 0;
  bool _manualOverrideActive = false;

  bool get manualOverrideActive => _manualOverrideActive;

  /// Threshold for detecting manual speed override (km/h).
  static const _overrideThreshold = 0.5;

  // ── Subscribe to BLE notifications ──

  Future<void> startListening() async {
    await _subscribeFtms();
    await _subscribeHr();
  }

  Future<void> _subscribeFtms() async {
    final device = BleService.instance.treadmill;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.ftmsTreadmill,
        _FtmsUuids.treadmillData);
    if (char == null) return;

    await char.setNotifyValue(true);
    _ftmsDataSub?.cancel();
    _ftmsDataSub = char.onValueReceived.listen(_parseFtmsData);
  }

  Future<void> _subscribeHr() async {
    final device = BleService.instance.hrSensor;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.heartRate,
        _FtmsUuids.hrMeasurement);
    if (char == null) return;

    await char.setNotifyValue(true);
    _hrDataSub?.cancel();
    _hrDataSub = char.onValueReceived.listen(_parseHrData);
  }

  BluetoothCharacteristic? _findCharacteristic(
      BluetoothDevice device, Guid serviceUuid, Guid charUuid) {
    for (final svc in device.servicesList) {
      if (svc.uuid == serviceUuid) {
        for (final c in svc.characteristics) {
          if (c.uuid == charUuid) return c;
        }
      }
    }
    return null;
  }

  // ── Parse FTMS Treadmill Data (0x2ACD) ──

  void _parseFtmsData(List<int> value) {
    if (value.length < 4) return;
    final bytes = Uint8List.fromList(value);
    final bd = ByteData.sublistView(bytes);

    final flags = bd.getUint16(0, Endian.little);
    var offset = 2;

    // Bit 0 of flags: if 0, Instantaneous Speed is present (uint16, 0.01 km/h)
    double speed = 0;
    if ((flags & 0x01) == 0) {
      speed = bd.getUint16(offset, Endian.little) * 0.01;
      offset += 2;
    }

    double? avgSpeed;
    if ((flags & 0x02) != 0 && offset + 2 <= bytes.length) {
      avgSpeed = bd.getUint16(offset, Endian.little) * 0.01;
      offset += 2;
    }

    double? totalDist;
    if ((flags & 0x04) != 0 && offset + 3 <= bytes.length) {
      totalDist = (bytes[offset] | (bytes[offset + 1] << 8) |
              (bytes[offset + 2] << 16))
          .toDouble();
      offset += 3;
    }

    double? incline;
    if ((flags & 0x08) != 0 && offset + 4 <= bytes.length) {
      incline = bd.getInt16(offset, Endian.little) * 0.1;
      offset += 4; // incline + ramp angle
    }

    _lastFtms = FtmsReading(
      speedKmh: speed,
      avgSpeedKmh: avgSpeed,
      totalDistanceM: totalDist,
      inclinePct: incline,
    );

    // Manual override detection: physical speed differs from commanded speed
    if (_lastCommandedSpeedKmh > 0 &&
        (speed - _lastCommandedSpeedKmh).abs() > _overrideThreshold) {
      _manualOverrideActive = true;
    }
  }

  // ── Parse Heart Rate Measurement (0x2A37) ──

  void _parseHrData(List<int> value) {
    if (value.isEmpty) return;
    final flags = value[0];
    int hr;
    int offset;

    if ((flags & 0x01) == 0) {
      hr = value[1];
      offset = 2;
    } else {
      hr = value[1] | (value[2] << 8);
      offset = 3;
    }

    // Sensor contact bits
    offset += ((flags & 0x04) != 0) ? 0 : 0; // contact flag doesn't add bytes

    // Energy expended
    if ((flags & 0x08) != 0) offset += 2;

    // RR-Interval (can derive cadence from this for running)
    int? cadence;
    if ((flags & 0x10) != 0 && offset + 2 <= value.length) {
      final rr = value[offset] | (value[offset + 1] << 8);
      if (rr > 0) {
        cadence = (60000 / (rr * 1024 / 1024)).round();
      }
    }

    _lastHr = HrReading(heartRate: hr, cadence: cadence);
  }

  // ── FTMS Control Point Writes ──

  Future<void> _writeControlPoint(List<int> payload) async {
    final device = BleService.instance.treadmill;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.ftmsTreadmill,
        _FtmsUuids.controlPoint);
    if (char == null) return;

    await char.write(payload, withoutResponse: false);
  }

  /// Request control of the treadmill (must be called before other commands).
  Future<void> requestControl() async {
    await _writeControlPoint([0x00]);
  }

  /// Start or resume the treadmill belt.
  Future<void> startOrResume() async {
    await _writeControlPoint([0x07]);
  }

  /// Stop the treadmill.
  Future<void> stop() async {
    await _writeControlPoint([0x08, 0x01]);
  }

  /// Pause the treadmill.
  Future<void> pause() async {
    await _writeControlPoint([0x08, 0x02]);
  }

  /// Set target speed in km/h. Records the command for override detection.
  Future<void> setTargetSpeed(double kmh) async {
    _lastCommandedSpeedKmh = kmh;
    _manualOverrideActive = false;
    final raw = (kmh * 100).round();
    final lo = raw & 0xFF;
    final hi = (raw >> 8) & 0xFF;
    await _writeControlPoint([0x02, lo, hi]);
  }

  /// Set target inclination. Direct 1:1 mapping from percentage to level,
  /// clamped to the treadmill's 0-18 range.
  Future<void> setTargetIncline(double pct) async {
    final level = clampInclineToLevel(pct);
    final lo = level & 0xFF;
    final hi = (level >> 8) & 0xFF;
    await _writeControlPoint([0x03, lo, hi]);
  }

  /// Reset the manual override flag at the start of a new interval block.
  void resetManualOverride() {
    _manualOverrideActive = false;
  }

  // ── Incline Clamping ──

  /// Direct 1:1 map: percentage → integer level, clamped to 0-18.
  /// e.g. 5% → level 5, 0% → level 0, 20% → level 18.
  static int clampInclineToLevel(double pct) {
    return pct.round().clamp(0, 18);
  }

  // ── Teardown ──

  void dispose() {
    _ftmsDataSub?.cancel();
    _hrDataSub?.cancel();
    _ftmsDataSub = null;
    _hrDataSub = null;
    _lastFtms = const FtmsReading(speedKmh: 0);
    _lastHr = const HrReading(heartRate: 0);
    _lastCommandedSpeedKmh = 0;
    _manualOverrideActive = false;
  }
}
