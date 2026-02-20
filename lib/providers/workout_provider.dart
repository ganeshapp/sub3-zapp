import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/telemetry.dart';
import '../models/workout_file.dart';
import '../services/ble_service.dart';
import '../services/ftms_service.dart';

// ── State ──

enum WorkoutPhase { countdown, running, paused, finished }

class ActiveWorkoutState {
  final WorkoutFile workoutFile;
  final WorkoutPhase phase;
  final int countdownRemaining;
  final int elapsedSeconds;

  // Live metrics (source of truth: treadmill broadcast)
  final double currentSpeedKmh;
  final double currentInclinePct;
  final double currentHr;
  final int currentCadence;
  final double totalDistanceKm;

  // Calculated averages
  final double avgSpeedKmh;
  final double avgHr;
  final double currentPaceMinPerKm;
  final double avgPaceMinPerKm;

  // JSON workout segment tracking
  final int currentSegmentIndex;
  final int segmentElapsedSeconds;
  final bool manualOverrideActive;

  // Telemetry array for TCX export
  final List<TelemetryPoint> telemetry;

  const ActiveWorkoutState({
    required this.workoutFile,
    this.phase = WorkoutPhase.countdown,
    this.countdownRemaining = 3,
    this.elapsedSeconds = 0,
    this.currentSpeedKmh = 0,
    this.currentInclinePct = 0,
    this.currentHr = 0,
    this.currentCadence = 0,
    this.totalDistanceKm = 0,
    this.avgSpeedKmh = 0,
    this.avgHr = 0,
    this.currentPaceMinPerKm = 0,
    this.avgPaceMinPerKm = 0,
    this.currentSegmentIndex = 0,
    this.segmentElapsedSeconds = 0,
    this.manualOverrideActive = false,
    this.telemetry = const [],
  });

  ActiveWorkoutState copyWith({
    WorkoutPhase? phase,
    int? countdownRemaining,
    int? elapsedSeconds,
    double? currentSpeedKmh,
    double? currentInclinePct,
    double? currentHr,
    int? currentCadence,
    double? totalDistanceKm,
    double? avgSpeedKmh,
    double? avgHr,
    double? currentPaceMinPerKm,
    double? avgPaceMinPerKm,
    int? currentSegmentIndex,
    int? segmentElapsedSeconds,
    bool? manualOverrideActive,
    List<TelemetryPoint>? telemetry,
  }) {
    return ActiveWorkoutState(
      workoutFile: workoutFile,
      phase: phase ?? this.phase,
      countdownRemaining: countdownRemaining ?? this.countdownRemaining,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      currentInclinePct: currentInclinePct ?? this.currentInclinePct,
      currentHr: currentHr ?? this.currentHr,
      currentCadence: currentCadence ?? this.currentCadence,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
      avgHr: avgHr ?? this.avgHr,
      currentPaceMinPerKm: currentPaceMinPerKm ?? this.currentPaceMinPerKm,
      avgPaceMinPerKm: avgPaceMinPerKm ?? this.avgPaceMinPerKm,
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      segmentElapsedSeconds:
          segmentElapsedSeconds ?? this.segmentElapsedSeconds,
      manualOverrideActive:
          manualOverrideActive ?? this.manualOverrideActive,
      telemetry: telemetry ?? this.telemetry,
    );
  }

  /// Progress fraction 0.0–1.0 for the visualizer.
  double get progress {
    if (workoutFile.isGpx) {
      final total = workoutFile.totalDistanceM;
      if (total <= 0) return 0;
      return (totalDistanceKm * 1000 / total).clamp(0.0, 1.0);
    } else {
      final total = workoutFile.totalDurationSeconds;
      if (total <= 0) return 0;
      return (elapsedSeconds / total).clamp(0.0, 1.0);
    }
  }

  /// Maximum heart rate recorded during the session.
  double get maxHr {
    if (telemetry.isEmpty) return 0;
    return telemetry
        .map((t) => t.heartRate ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Elevation gain computed from telemetry incline deltas (rough estimate).
  double get elevationGain {
    double gain = 0;
    for (var i = 1; i < telemetry.length; i++) {
      final dEle = telemetry[i].inclinePct - telemetry[i - 1].inclinePct;
      if (dEle > 0) gain += dEle;
    }
    return gain;
  }
}

// ── Notifier ──

class ActiveWorkoutNotifier extends Notifier<ActiveWorkoutState?> {
  Timer? _timer;

  @override
  ActiveWorkoutState? build() => null;

  // ── Lifecycle ──

  Future<void> startWorkout(WorkoutFile file) async {
    WakelockPlus.enable();
    BleService.instance.enableAutoReconnect();

    try {
      await FtmsService.instance.startListening();
      await FtmsService.instance.requestControl();
    } catch (_) {
      // BLE may not be connected yet; continue (metrics will read 0)
    }

    state = ActiveWorkoutState(workoutFile: file);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final s = state;
    if (s == null) return;

    try {
      switch (s.phase) {
        case WorkoutPhase.countdown:
          _handleCountdown(s);
        case WorkoutPhase.running:
          _handleRunningTick(s);
        case WorkoutPhase.paused:
        case WorkoutPhase.finished:
          break;
      }
    } catch (_) {
      // Prevent timer death from uncaught exceptions
    }
  }

  // ── Countdown (3-second safety start) ──

  void _handleCountdown(ActiveWorkoutState s) {
    final remaining = s.countdownRemaining - 1;
    if (remaining <= 0) {
      state = s.copyWith(phase: WorkoutPhase.running, countdownRemaining: 0);
      _sendInitialCommands();
    } else {
      state = s.copyWith(countdownRemaining: remaining);
    }
  }

  Future<void> _sendInitialCommands() async {
    try {
      await FtmsService.instance.startOrResume();
      _sendSegmentCommands();
    } catch (_) {}
  }

  // ── Running tick ──

  void _handleRunningTick(ActiveWorkoutState s) {
    final ftms = FtmsService.instance.lastFtms;
    final hr = FtmsService.instance.lastHr;

    final speedKmh = ftms.speedKmh;
    final incline = ftms.inclinePct ?? s.currentInclinePct;
    final heartRate = hr.heartRate.toDouble();
    final cadence = hr.cadence ?? s.currentCadence;
    final elapsed = s.elapsedSeconds + 1;

    // Distance: speed (km/h) × 1 second = speed / 3600 km
    final distDelta = speedKmh / 3600;
    final totalDist = s.totalDistanceKm + distDelta;

    // Current pace: min/km = 60 / speed  (guard div-by-zero)
    final currentPace = speedKmh > 0 ? 60.0 / speedKmh : 0.0;

    // Interpolate virtual GPS position for GPX routes
    double? lat;
    double? lon;
    if (s.workoutFile.isGpx) {
      final pos = s.workoutFile.interpolatePosition(totalDist * 1000);
      if (pos != null) {
        lat = pos.$1;
        lon = pos.$2;
      }
    }

    // Running averages from telemetry
    final newTelemetry = List<TelemetryPoint>.from(s.telemetry)
      ..add(TelemetryPoint(
        elapsedSeconds: elapsed,
        heartRate: heartRate > 0 ? heartRate : null,
        cadence: cadence > 0 ? cadence : null,
        speedKmh: speedKmh,
        inclinePct: incline,
        cumulativeDistanceKm: totalDist,
        paceMinPerKm: currentPace,
        latitude: lat,
        longitude: lon,
      ));

    final n = newTelemetry.length;
    final avgSpeed =
        newTelemetry.fold(0.0, (sum, t) => sum + t.speedKmh) / n;
    final hrPoints = newTelemetry.where((t) => (t.heartRate ?? 0) > 0);
    final avgHrVal = hrPoints.isNotEmpty
        ? hrPoints.fold(0.0, (sum, t) => sum + t.heartRate!) / hrPoints.length
        : 0.0;
    final avgPace = avgSpeed > 0 ? 60.0 / avgSpeed : 0.0;

    // JSON segment tracking
    var segIdx = s.currentSegmentIndex;
    var segElapsed = s.segmentElapsedSeconds + 1;
    var overrideActive = FtmsService.instance.manualOverrideActive;

    if (!s.workoutFile.isGpx && s.workoutFile.intervals != null) {
      final intervals = s.workoutFile.intervals!;

      // Check total workout duration first as a safeguard
      final totalDuration = s.workoutFile.totalDurationSeconds;
      if (totalDuration > 0 && elapsed >= totalDuration) {
        _finishWorkout();
        return;
      }

      // Advance past completed intervals (handles edge cases safely)
      if (segIdx < intervals.length &&
          intervals[segIdx].durationSeconds > 0 &&
          segElapsed >= intervals[segIdx].durationSeconds) {
        segIdx++;
        segElapsed = 0;
        FtmsService.instance.resetManualOverride();
        overrideActive = false;
        if (segIdx < intervals.length) {
          _sendSegmentCommands(segmentIndex: segIdx);
        }
      }
    }

    // GPX: auto-finish when distance exceeds route length
    if (s.workoutFile.isGpx &&
        totalDist * 1000 >= s.workoutFile.totalDistanceM) {
      _finishWorkout();
      return;
    }

    // GPX incline control (look-ahead)
    if (s.workoutFile.isGpx) {
      _sendGpxIncline(totalDist, s.workoutFile);
    }

    state = s.copyWith(
      elapsedSeconds: elapsed,
      currentSpeedKmh: speedKmh,
      currentInclinePct: incline,
      currentHr: heartRate,
      currentCadence: cadence,
      totalDistanceKm: totalDist,
      avgSpeedKmh: avgSpeed,
      avgHr: avgHrVal,
      currentPaceMinPerKm: currentPace,
      avgPaceMinPerKm: avgPace,
      currentSegmentIndex: segIdx,
      segmentElapsedSeconds: segElapsed,
      manualOverrideActive: overrideActive,
      telemetry: newTelemetry,
    );
  }

  // ── Execution engine: JSON ──

  Future<void> _sendSegmentCommands({int? segmentIndex}) async {
    final s = state;
    if (s == null || s.workoutFile.isGpx) return;
    final intervals = s.workoutFile.intervals;
    if (intervals == null) return;

    final idx = segmentIndex ?? s.currentSegmentIndex;
    if (idx >= intervals.length) return;

    final block = intervals[idx];
    try {
      if (!FtmsService.instance.manualOverrideActive) {
        await FtmsService.instance.setTargetSpeed(block.speedKmh);
      }
      await FtmsService.instance.setTargetIncline(block.inclinePct);
    } catch (_) {}
  }

  // ── Execution engine: GPX (incline only, speed is manual) ──

  double _lastSentGpxIncline = -1;

  Future<void> _sendGpxIncline(double distKm, WorkoutFile file) async {
    final points = file.gpxPoints;
    final smoothed = file.smoothedElevations;
    if (points == null || smoothed == null || points.length < 2) return;

    final distM = distKm * 1000;

    // Look-ahead: target ~30m ahead (≈3s at 10 km/h) for motor lag
    const lookAheadM = 30.0;
    final targetDistM = distM + lookAheadM;

    // Find the two bracketing points
    int i = 0;
    for (; i < points.length - 1; i++) {
      if (points[i + 1].cumulativeDistanceM >= targetDistM) break;
    }
    final next = min(i + 1, points.length - 1);

    // Compute grade between current and next point
    final dDist = points[next].cumulativeDistanceM -
        points[i].cumulativeDistanceM;
    final dEle = smoothed[next] - smoothed[i];
    final gradePct = dDist > 0 ? (dEle / dDist) * 100 : 0.0;

    // Only send if the level changed
    final level = FtmsService.clampInclineToLevel(gradePct);
    if (level.toDouble() != _lastSentGpxIncline) {
      _lastSentGpxIncline = level.toDouble();
      try {
        await FtmsService.instance.setTargetIncline(gradePct);
      } catch (_) {}
    }
  }

  // ── Controls ──

  Future<void> pauseWorkout() async {
    if (state?.phase != WorkoutPhase.running) return;
    try {
      await FtmsService.instance.pause();
    } catch (_) {}
    WakelockPlus.disable();
    state = state!.copyWith(phase: WorkoutPhase.paused);
  }

  Future<void> resumeWorkout() async {
    if (state?.phase != WorkoutPhase.paused) return;
    WakelockPlus.enable();
    try {
      await FtmsService.instance.startOrResume();
      _sendSegmentCommands();
    } catch (_) {}
    state = state!.copyWith(phase: WorkoutPhase.running);
  }

  Future<void> stopWorkout() async {
    try {
      await FtmsService.instance.stop();
    } catch (_) {}
    _finishWorkout();
  }

  void _finishWorkout() {
    _timer?.cancel();
    _timer = null;
    WakelockPlus.disable();
    BleService.instance.disableAutoReconnect();
    FtmsService.instance.dispose();
    state = state?.copyWith(phase: WorkoutPhase.finished);
  }

  /// Completely clear the workout state (called after summary screen).
  void clear() {
    _timer?.cancel();
    _timer = null;
    WakelockPlus.disable();
    state = null;
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState?>(
  ActiveWorkoutNotifier.new,
);
