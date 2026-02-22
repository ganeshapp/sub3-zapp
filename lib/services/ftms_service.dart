import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

/// BLE characteristic UUIDs.
class _CharUuids {
  static final treadmillData = Guid('00002acd-0000-1000-8000-00805f9b34fb');
  static final controlPoint = Guid('00002ad9-0000-1000-8000-00805f9b34fb');
  static final hrMeasurement = Guid('00002a37-0000-1000-8000-00805f9b34fb');
  static final rscMeasurement = Guid('00002a53-0000-1000-8000-00805f9b34fb');
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
  StreamSubscription? _rscDataSub;

  FtmsReading _lastFtms = const FtmsReading(speedKmh: 0);
  HrReading _lastHr = const HrReading(heartRate: 0);
  int? _rscCadence;

  FtmsReading get lastFtms => _lastFtms;
  HrReading get lastHr => HrReading(
        heartRate: _lastHr.heartRate,
        cadence: _lastHr.cadence ?? _rscCadence,
      );

  

  // ── Subscribe to BLE notifications ──

  Future<void> startListening() async {
    await _subscribeFtms();
    await _subscribeHr();
    await _subscribeRsc();
  }

  Future<void> _subscribeFtms() async {
    final device = BleService.instance.treadmill;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.ftmsTreadmill,
        _CharUuids.treadmillData);
    if (char == null) return;

    await char.setNotifyValue(true);
    _ftmsDataSub?.cancel();
    _ftmsDataSub = char.onValueReceived.listen(_parseFtmsData);
  }

  Future<void> _subscribeHr() async {
    final device = BleService.instance.hrSensor;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.heartRate,
        _CharUuids.hrMeasurement);
    if (char == null) return;

    await char.setNotifyValue(true);
    _hrDataSub?.cancel();
    _hrDataSub = char.onValueReceived.listen(_parseHrData);
  }

  Future<void> _subscribeRsc() async {
    final device = BleService.instance.hrSensor;
    if (device == null) return;

    final char = _findCharacteristic(
        device, BleUuids.runningSpeedCadence, _CharUuids.rscMeasurement);
    if (char == null) return;

    await char.setNotifyValue(true);
    _rscDataSub?.cancel();
    _rscDataSub = char.onValueReceived.listen(_parseRscData);
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

  // ── Parse RSC Measurement (0x2A53) ──

  void _parseRscData(List<int> value) {
    if (value.length < 4) return;
    // Byte 0: flags, Bytes 1-2: speed (uint16, 1/256 m/s), Byte 3: cadence (uint8)
    _rscCadence = value[3];
  }

  // ── FTMS Control Point Writes ──

  Future<void> _writeControlPoint(List<int> payload) async {
    final device = BleService.instance.treadmill;
    if (device == null) return;

    final char = _findCharacteristic(device, BleUuids.ftmsTreadmill,
        _CharUuids.controlPoint);
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

  /// Set target speed in km/h.
  Future<void> setTargetSpeed(double kmh) async {
    final raw = (kmh * 100).round();
    final lo = raw & 0xFF;
    final hi = (raw >> 8) & 0xFF;
    await _writeControlPoint([0x02, lo, hi]);
  }

  /// Set target inclination in percent, clamped to 0-18%.
  /// FTMS Control Point opcode 0x03 takes a sint16 in 0.1% units.
  Future<void> setTargetIncline(double pct) async {
    final clamped = pct.clamp(0.0, 18.0);
    final raw = (clamped * 10).round(); // 1% → 10, 5% → 50
    final lo = raw & 0xFF;
    final hi = (raw >> 8) & 0xFF;
    await _writeControlPoint([0x03, lo, hi]);
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
    _rscDataSub?.cancel();
    _ftmsDataSub = null;
    _hrDataSub = null;
    _rscDataSub = null;
    _lastFtms = const FtmsReading(speedKmh: 0);
    _lastHr = const HrReading(heartRate: 0);
    _rscCadence = null;
  }
}
