import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/ghost_trace.dart';
import '../models/telemetry.dart';
import '../models/workout_file.dart';
import '../services/ble_service.dart';
import '../services/ftms_service.dart';
import 'ble_provider.dart';

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
  final bool isManualControlEnabled;

  // Telemetry array for TCX export
  final List<TelemetryPoint> telemetry;

  /// The best-ever run on this route, to race against. Null for structured
  /// workouts and for routes with no PR yet.
  final GhostTrace? ghost;

  const ActiveWorkoutState({
    required this.workoutFile,
    this.ghost,
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
    this.isManualControlEnabled = false,
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
    bool? isManualControlEnabled,
    List<TelemetryPoint>? telemetry,
  }) {
    return ActiveWorkoutState(
      workoutFile: workoutFile,
      ghost: ghost,
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
      isManualControlEnabled:
          isManualControlEnabled ?? this.isManualControlEnabled,
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

  /// True when a route run actually reached the end — covered distance is at
  /// least 99% of the route. Below that the run still saves to history, it
  /// just doesn't earn a badge or a best time.
  bool get routeCompleted {
    if (!workoutFile.isGpx) return false;
    final total = workoutFile.totalDistanceM;
    if (total <= 0) return false;
    return totalDistanceKm * 1000 >= total * 0.99;
  }

  /// True when a structured workout ran to the end — elapsed time is at least
  /// 99% of the planned duration.
  bool get workoutCompleted {
    if (workoutFile.isGpx) return false;
    final total = workoutFile.totalDurationSeconds;
    if (total <= 0) return false;
    return elapsedSeconds >= total * 0.99;
  }

  /// Whether this session counts towards the library completion badge.
  bool get earnedCompletion => routeCompleted || workoutCompleted;

  // ── Ghost racing (routes only) ──

  /// How far the ghost has run, as a 0.0–1.0 fraction of the route, for the
  /// second dot on the map. Null when no ghost is armed.
  double? get ghostProgress {
    final g = ghost;
    if (g == null) return null;
    final total = workoutFile.totalDistanceM;
    if (total <= 0) return null;
    return (g.distanceAt(elapsedSeconds) / total).clamp(0.0, 1.0);
  }

  /// Seconds ahead (positive) or behind (negative) the ghost, judged at the
  /// distance covered so far. Null when there is no ghost, or once the route
  /// is further along than the ghost ever got.
  int? get ghostDeltaSeconds {
    final g = ghost;
    if (g == null) return null;
    final delta = g.deltaAt(
      elapsedSeconds: elapsedSeconds,
      distanceM: totalDistanceKm * 1000,
    );
    return delta?.round();
  }

  /// True once the ghost has run out of trace — it is standing at the finish.
  bool get ghostFinished =>
      ghost != null && ghost!.hasFinishedBy(elapsedSeconds);

  /// Maximum heart rate recorded during the session.
  double get maxHr {
    if (telemetry.isEmpty) return 0;
    return telemetry
        .map((t) => t.heartRate ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Elevation gain in meters, computed from cumulative altitude changes.
  double get elevationGain {
    double gain = 0;
    for (var i = 1; i < telemetry.length; i++) {
      final prev = telemetry[i - 1].altitude ?? 0;
      final curr = telemetry[i].altitude ?? 0;
      final delta = curr - prev;
      if (delta > 0) gain += delta;
    }
    return gain;
  }
}

// ── Notifier ──

class ActiveWorkoutNotifier extends Notifier<ActiveWorkoutState?> {
  Timer? _timer;

  // Physical stop detection
  int _zeroSpeedTicks = 0;
  bool _beltHasMoved = false;

  // JSON command tracking -- commands sent ONLY when target changes
  double _lastSentSpeed = -1;
  double _lastSentIncline = -1;

  // Physical control detection -- if the treadmill is decelerating while
  // below our commanded target, the user is using physical controls.
  // Once detected, ALL speed/incline commands are suspended until the
  // next interval transition or an explicit toggle back to auto.
  bool _commandsSuspended = false;
  double _prevReportedSpeed = 0;
  int _decelerationTicks = 0;

  // GPX incline tracking
  double _lastSentGpxIncline = -1;

  @override
  ActiveWorkoutState? build() => null;

  void _resetCommandState() {
    _lastSentSpeed = -1;
    _lastSentIncline = -1;
    _commandsSuspended = false;
    _prevReportedSpeed = 0;
    _decelerationTicks = 0;
    _lastSentGpxIncline = -1;
    _zeroSpeedTicks = 0;
    _beltHasMoved = false;
  }

  // ── Lifecycle ──

  /// [ghost] is the route's PR trace, armed only for the route being run.
  ///
  /// Returns true when the run actually started. With no treadmill connected
  /// there is no speed to record and nothing to control, so the run is refused
  /// before anything is touched — no wakelock, no auto-reconnect, no BLE
  /// subscriptions, no state — and refused again if the treadmill data
  /// subscription will not come up. The Library disables its start affordances
  /// so the first check should never fire; it is here so no call site can
  /// quietly create a session of zeros.
  Future<bool> startWorkout(WorkoutFile file, {GhostTrace? ghost}) async {
    if (!ref.read(canStartSessionProvider)) return false;

    // The treadmill subscription *is* the run: without it every tick records a
    // zero. A belt switched off keeps its GATT link until the supervision
    // timeout, so the gate above can still be true while the radio is dead —
    // and the subscribe is where that shows up. Refuse rather than open a
    // session of zeros. Nothing has been touched yet, so nothing to undo.
    try {
      await FtmsService.instance.startTreadmillListening();
    } catch (_) {
      return false;
    }

    _resetCommandState();
    WakelockPlus.enable();
    BleService.instance.enableAutoReconnect();
    BleService.instance.onReconnected = _handleReconnected;

    try {
      // The HR subscription was opened when the sensor connected and stays up
      // for the whole app session — starting a workout must never interrupt
      // it. It is only topped up if it never came up in the first place, and
      // HR is optional, so nothing here can stop the run.
      if (!FtmsService.instance.isHrListening) {
        await FtmsService.instance.startHrListening();
      }
      // Some firmware refuses control; the belt still runs, the rider drives
      // it by hand.
      await FtmsService.instance.requestControl();
    } catch (_) {}

    state = ActiveWorkoutState(
      workoutFile: file,
      ghost: file.isGpx ? ghost : null,
    );
    _startTimer();
    return true;
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

  /// Mid-run reconnect recovery: BleService has already resubscribed
  /// notifications and re-requested control; reset the dedupe sentinels and
  /// force a transition-style re-send, because a treadmill that dropped its
  /// target on disconnect would otherwise never be re-commanded — the
  /// rounded target still matches `_lastSentSpeed`/`_lastSentIncline`.
  void _handleReconnected(BleDeviceRole role) {
    if (role != BleDeviceRole.treadmill) return;
    final s = state;
    if (s == null || s.phase != WorkoutPhase.running) return;
    if (s.isManualControlEnabled) return;

    _lastSentSpeed = -1;
    _lastSentIncline = -1;
    _lastSentGpxIncline = -1;
    _commandsSuspended = false;
    if (s.workoutFile.isGpx) {
      _sendGpxIncline(s.totalDistanceKm, s.workoutFile);
    } else {
      _sendSegmentCommands(isTransition: true);
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
      await _sendSegmentCommands(isTransition: true);
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

    // Distance: speed (km/h) x 1 second = speed / 3600 km
    final distDelta = speedKmh / 3600;
    final totalDist = s.totalDistanceKm + distDelta;

    // Current pace: min/km = 60 / speed (guard div-by-zero)
    final currentPace = speedKmh > 0 ? 60.0 / speedKmh : 0.0;

    // Interpolate virtual GPS position and elevation for GPX routes
    double? lat;
    double? lon;
    double? altitude;
    if (s.workoutFile.isGpx) {
      final distM = totalDist * 1000;
      final pos = s.workoutFile.interpolatePosition(distM);
      if (pos != null) {
        lat = pos.$1;
        lon = pos.$2;
      }
      altitude = s.workoutFile.interpolateElevation(distM);
    } else {
      final prevAlt = s.telemetry.isNotEmpty
          ? (s.telemetry.last.altitude ?? 0.0)
          : 0.0;
      final horizDistM = distDelta * 1000;
      altitude = prevAlt + horizDistM * (incline / 100);
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
        altitude: altitude,
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

    if (!s.workoutFile.isGpx && s.workoutFile.intervals != null) {
      final intervals = s.workoutFile.intervals!;

      // Total duration safeguard
      final totalDuration = s.workoutFile.totalDurationSeconds;
      if (totalDuration > 0 && elapsed >= totalDuration) {
        _finishWorkout();
        return;
      }

      // Detect physical treadmill control: rapid deceleration while the
      // treadmill speed is already below our commanded target means the
      // user pressed stop/pause on the physical machine. A normal
      // commanded deceleration (e.g. 15 -> 6 transition) shows speed
      // ABOVE the new target while ramping down, not below it.
      if (!_commandsSuspended && segIdx < intervals.length) {
        final block = intervals[segIdx];
        final t = block.durationSeconds > 0
            ? (segElapsed / block.durationSeconds).clamp(0.0, 1.0)
            : 0.0;
        final targetSpeed = block.speedAt(t);
        if (speedKmh < _prevReportedSpeed - 0.3 &&
            speedKmh < targetSpeed - 1.0) {
          _decelerationTicks++;
          if (_decelerationTicks >= 2) {
            _commandsSuspended = true;
          }
        } else {
          _decelerationTicks = 0;
        }
      }
      _prevReportedSpeed = speedKmh;

      // Advance past completed intervals
      var transitioned = false;
      if (segIdx < intervals.length &&
          intervals[segIdx].durationSeconds > 0 &&
          segElapsed >= intervals[segIdx].durationSeconds) {
        segIdx++;
        segElapsed = 0;
        transitioned = true;
        _lastSentSpeed = -1;
        _lastSentIncline = -1;
        _commandsSuspended = false;
        _decelerationTicks = 0;
      }

      // Send commands only when target changes (ramp progression or
      // transition). Never re-send the same value as a keep-alive.
      if (!s.isManualControlEnabled && !_commandsSuspended) {
        _sendSegmentCommands(
          segmentIndex: segIdx,
          segElapsed: segElapsed,
          isTransition: transitioned,
        );
      }
    }

    // GPX: auto-finish when distance exceeds route length
    if (s.workoutFile.isGpx &&
        totalDist * 1000 >= s.workoutFile.totalDistanceM) {
      _finishWorkout();
      return;
    }

    // GPX incline control (look-ahead) -- only when not in manual mode
    if (s.workoutFile.isGpx && !s.isManualControlEnabled) {
      _sendGpxIncline(totalDist, s.workoutFile);
    }

    // Physical stop detection: belt was running but speed dropped to
    // near-zero. Use generous thresholds to catch deceleration.
    if (speedKmh > 2.0) {
      _beltHasMoved = true;
      _zeroSpeedTicks = 0;
    } else if (_beltHasMoved && speedKmh < 1.0) {
      _zeroSpeedTicks++;
      if (_zeroSpeedTicks >= 3) {
        _finishWorkout();
        return;
      }
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
      telemetry: newTelemetry,
    );
  }

  // ── Execution engine: JSON ──

  /// Send speed/incline ONLY when the interpolated target actually changes.
  /// On interval transitions, retry once after a brief gap for BLE
  /// reliability -- this is a one-shot, not a continuous loop.
  Future<void> _sendSegmentCommands({
    int? segmentIndex,
    int? segElapsed,
    bool isTransition = false,
  }) async {
    final s = state;
    if (s == null || s.workoutFile.isGpx) return;
    if (s.isManualControlEnabled || _commandsSuspended) return;
    final intervals = s.workoutFile.intervals;
    if (intervals == null) return;

    final idx = segmentIndex ?? s.currentSegmentIndex;
    if (idx >= intervals.length) return;

    final block = intervals[idx];
    final elapsed = segElapsed ?? s.segmentElapsedSeconds;
    final t = block.durationSeconds > 0
        ? (elapsed / block.durationSeconds).clamp(0.0, 1.0)
        : 0.0;

    final targetSpeed = block.speedAt(t);
    final targetIncline = block.inclineAt(t);

    final roundedSpeed = (targetSpeed * 10).round() / 10;
    final roundedIncline = (targetIncline * 10).round() / 10;

    final valueChanged = roundedSpeed != _lastSentSpeed ||
        roundedIncline != _lastSentIncline;
    if (!valueChanged) return;

    _lastSentSpeed = roundedSpeed;
    _lastSentIncline = roundedIncline;

    try {
      await FtmsService.instance.setTargetSpeed(roundedSpeed);
      await FtmsService.instance.setTargetIncline(roundedIncline);
      if (isTransition) {
        await Future.delayed(const Duration(milliseconds: 300));
        await FtmsService.instance.setTargetSpeed(roundedSpeed);
        await FtmsService.instance.setTargetIncline(roundedIncline);
      }
    } catch (_) {}
  }

  // ── Execution engine: GPX (incline only, speed is manual) ──

  Future<void> _sendGpxIncline(double distKm, WorkoutFile file) async {
    final points = file.gpxPoints;
    final smoothed = file.smoothedElevations;
    if (points == null || smoothed == null || points.length < 2) return;

    final distM = distKm * 1000;

    // Look-ahead ~30m (approx 3s at 10 km/h) for motor lag
    const lookAheadM = 30.0;
    final targetDistM = distM + lookAheadM;

    int i = 0;
    for (; i < points.length - 1; i++) {
      if (points[i + 1].cumulativeDistanceM >= targetDistM) break;
    }
    final next = min(i + 1, points.length - 1);

    final dDist = points[next].cumulativeDistanceM -
        points[i].cumulativeDistanceM;
    final dEle = smoothed[next] - smoothed[i];
    final gradePct = dDist > 0 ? (dEle / dDist) * 100 : 0.0;

    final level = FtmsService.clampInclineToLevel(gradePct);
    if (level.toDouble() != _lastSentGpxIncline) {
      _lastSentGpxIncline = level.toDouble();
      try {
        await FtmsService.instance.setTargetIncline(gradePct);
      } catch (_) {}
    }
  }

  // ── Controls ──

  Future<void> toggleManualControl() async {
    final s = state;
    if (s == null || s.phase != WorkoutPhase.running) return;

    final wasManual = s.isManualControlEnabled;
    state = s.copyWith(isManualControlEnabled: !wasManual);

    if (wasManual) {
      _lastSentSpeed = -1;
      _lastSentIncline = -1;
      _commandsSuspended = false;
      _decelerationTicks = 0;
      if (!s.workoutFile.isGpx) {
        _sendSegmentCommands();
      } else {
        _lastSentGpxIncline = -1;
        _sendGpxIncline(s.totalDistanceKm, s.workoutFile);
      }
    }
  }

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
    _lastSentSpeed = -1;
    _lastSentIncline = -1;
    _commandsSuspended = false;
    _decelerationTicks = 0;
    try {
      await FtmsService.instance.startOrResume();
      await _sendSegmentCommands(isTransition: true);
    } catch (_) {}
    state = state!.copyWith(phase: WorkoutPhase.running);
  }

  Future<void> stopWorkout() async {
    await _finishWorkout();
  }

  Future<void> _finishWorkout() async {
    _timer?.cancel();
    _timer = null;
    try {
      await FtmsService.instance.stop();
    } catch (_) {}
    WakelockPlus.disable();
    BleService.instance.disableAutoReconnect();
    BleService.instance.onReconnected = null;
    // Treadmill only — the HR sensor keeps its subscription (and therefore
    // its link) between runs.
    FtmsService.instance.stopTreadmillListening();
    state = state?.copyWith(phase: WorkoutPhase.finished);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _resetCommandState();
    BleService.instance.onReconnected = null;
    WakelockPlus.disable();
    state = null;
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState?>(
  ActiveWorkoutNotifier.new,
);
