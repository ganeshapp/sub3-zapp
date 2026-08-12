import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/workout_provider.dart';
import '../widgets/metric_info.dart';
import '../widgets/workout_visualizer.dart';
import 'post_workout_screen.dart';

class LiveWorkoutScreen extends ConsumerWidget {
  const LiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(activeWorkoutProvider);
    if (workout == null) {
      // Backstop: never let the user back out of a screen that is about to
      // become a running workout.
      return const PopScope(
        canPop: false,
        child: Scaffold(body: Center(child: Text('No active workout'))),
      );
    }

    if (workout.phase == WorkoutPhase.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PostWorkoutScreen()),
        );
      });
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: workout.phase == WorkoutPhase.countdown
              ? _CountdownView(remaining: workout.countdownRemaining)
              : _DashboardView(workout: workout),
        ),
      ),
    );
  }
}

// ── 3-second countdown ──

class _CountdownView extends StatelessWidget {
  final int remaining;
  const _CountdownView({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'GET READY',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$remaining',
            style: GoogleFonts.inter(
              fontSize: 96,
              fontWeight: FontWeight.w800,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live dashboard ──

class _DashboardView extends ConsumerStatefulWidget {
  final ActiveWorkoutState workout;
  const _DashboardView({required this.workout});

  @override
  ConsumerState<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<_DashboardView> {
  bool _confirmingStop = false;
  final _screenshotKey = GlobalKey();
  final _capturedMarks = <int>{};

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final isPaused = workout.phase == WorkoutPhase.paused;

    // Auto-screenshot every 10 minutes (600 seconds)
    if (workout.phase == WorkoutPhase.running) {
      final mark = workout.elapsedSeconds ~/ 600;
      if (mark > 0 && !_capturedMarks.contains(mark)) {
        _capturedMarks.add(mark);
        WidgetsBinding.instance.addPostFrameCallback((_) => _takeScreenshot());
      }
    }

    return RepaintBoundary(
      key: _screenshotKey,
      child: GestureDetector(
      onTap: _confirmingStop ? () => setState(() => _confirmingStop = false) : null,
      behavior: HitTestBehavior.translucent,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Top row: timer + file name
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtDuration(workout.elapsedSeconds),
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isPaused ? Colors.amber : Colors.white,
                ),
              ),
              Flexible(
                child: Text(
                  workout.workoutFile.displayName,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white38),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Visualizer
          WorkoutVisualizer(
            workoutFile: workout.workoutFile,
            progress: workout.progress,
            ghostProgress: workout.ghostProgress,
          ),

          // Distance progress bar for GPX routes
          if (workout.workoutFile.isGpx) ...[
            const SizedBox(height: 8),
            _DistanceProgressBar(
              currentKm: workout.totalDistanceKm,
              totalKm: workout.workoutFile.totalDistanceM / 1000,
            ),
            // Ghost race: how far ahead of (or behind) your PR you are
            if (workout.ghost != null) ...[
              const SizedBox(height: 6),
              _GhostDeltaChip(
                deltaSeconds: workout.ghostDeltaSeconds,
                ghostFinished: workout.ghostFinished,
              ),
            ],
          ],
          const SizedBox(height: 12),

          // Metric tiles — 3×3 grid. Tile aspect ratio is computed from the
          // space actually available so the grid always fits (short screens,
          // the GPX progress bar, the ghost delta chip) instead of clipping
          // rows behind NeverScrollableScrollPhysics.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final tileW = (constraints.maxWidth - spacing * 2) / 3;
                final tileH = (constraints.maxHeight - spacing * 2) / 3;
                final ratio =
                    tileH > 0 ? (tileW / tileH).clamp(0.5, 4.0) : 1.15;
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: ratio.toDouble(),
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MetricTile(
                      label: 'HR',
                      value: workout.currentHr > 0
                          ? '${workout.currentHr.round()}'
                          : '--',
                      unit: 'bpm',
                      color: Colors.red,
                      infoKey: MetricInfo.heartRate,
                    ),
                    _MetricTile(
                      label: 'PACE',
                      value: _fmtPace(workout.currentPaceMinPerKm),
                      unit: '/km',
                      infoKey: MetricInfo.pace,
                    ),
                    _MetricTile(
                      label: 'AVG PACE',
                      value: _fmtPace(workout.avgPaceMinPerKm),
                      unit: '/km',
                      infoKey: MetricInfo.avgPace,
                    ),
                    _MetricTile(
                      label: 'SPEED',
                      value: workout.currentSpeedKmh.toStringAsFixed(1),
                      unit: 'km/h',
                    ),
                    _MetricTile(
                      label: 'AVG SPEED',
                      value: workout.avgSpeedKmh.toStringAsFixed(1),
                      unit: 'km/h',
                      infoKey: MetricInfo.avgSpeed,
                    ),
                    _MetricTile(
                      label: 'INCLINE',
                      value: workout.currentInclinePct.toStringAsFixed(1),
                      unit: '%',
                      color: Colors.green,
                      infoKey: MetricInfo.incline,
                    ),
                    _MetricTile(
                      label: 'DISTANCE',
                      value: workout.totalDistanceKm.toStringAsFixed(2),
                      unit: 'km',
                      color: Colors.blue,
                    ),
                    _MetricTile(
                      label: 'CADENCE',
                      value: workout.currentCadence > 0
                          ? '${workout.currentCadence}'
                          : '--',
                      unit: 'spm',
                      infoKey: MetricInfo.cadence,
                    ),
                    _MetricTile(
                      label: 'AVG HR',
                      value: workout.avgHr > 0
                          ? '${workout.avgHr.round()}'
                          : '--',
                      unit: 'bpm',
                      infoKey: MetricInfo.heartRate,
                    ),
                  ],
                );
              },
            ),
          ),

          // Manual control toggle
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => ref
                  .read(activeWorkoutProvider.notifier)
                  .toggleManualControl(),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: workout.isManualControlEnabled
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: workout.isManualControlEnabled
                        ? Colors.amber
                        : Colors.white12,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      workout.isManualControlEnabled
                          ? Icons.pan_tool
                          : Icons.smart_toy,
                      size: 16,
                      color: workout.isManualControlEnabled
                          ? Colors.amber
                          : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      workout.isManualControlEnabled
                          ? 'MANUAL CONTROL'
                          : 'AUTO CONTROL',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: workout.isManualControlEnabled
                            ? Colors.amber
                            : Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _confirmingStop
                ? SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      onPressed: () {
                        setState(() => _confirmingStop = false);
                        ref
                            .read(activeWorkoutProvider.notifier)
                            .stopWorkout();
                      },
                      icon: const Icon(Icons.stop, size: 28),
                      label: const Text('CONFIRM STOP'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: GoogleFonts.inter(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      // STOP
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _confirmingStop = true),
                            icon: const Icon(Icons.stop, size: 22),
                            label: const Text('STOP'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(
                                  color: Colors.red, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              textStyle: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // PAUSE / RESUME
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: () {
                              if (isPaused) {
                                ref
                                    .read(activeWorkoutProvider.notifier)
                                    .resumeWorkout();
                              } else {
                                ref
                                    .read(activeWorkoutProvider.notifier)
                                    .pauseWorkout();
                              }
                            },
                            icon: Icon(
                                isPaused ? Icons.play_arrow : Icons.pause,
                                size: 24),
                            label: Text(isPaused ? 'RESUME' : 'PAUSE'),
                            style: FilledButton.styleFrom(
                              backgroundColor: isPaused
                                  ? Colors.green
                                  : Colors.amber.shade800,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              textStyle: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  Future<void> _takeScreenshot() async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) return;
      }

      final boundary = _screenshotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List bytes = byteData.buffer.asUint8List();
      await Gal.putImageBytes(bytes, album: 'Sub3');
    } catch (_) {}
  }

  String _fmtDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtPace(double minPerKm) {
    if (minPerKm <= 0 || minPerKm > 30) return '--:--';
    final m = minPerKm.floor();
    final s = ((minPerKm - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Distance progress bar (GPX only) ──

class _DistanceProgressBar extends StatelessWidget {
  final double currentKm;
  final double totalKm;

  const _DistanceProgressBar({
    required this.currentKm,
    required this.totalKm,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (totalKm - currentKm).clamp(0.0, totalKm);
    final fraction = totalKm > 0 ? (currentKm / totalKm).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${currentKm.toStringAsFixed(2)} km',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
              Text(
                '${remaining.toStringAsFixed(2)} km left',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                ),
              ),
              Text(
                '${totalKm.toStringAsFixed(2)} km',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metric tile ──

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? color;

  /// Glossary key: shows a small `(?)` beside the label and explains the
  /// metric in plain words when the tile is tapped.
  final String? infoKey;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
    this.infoKey,
  });

  @override
  Widget build(BuildContext context) {
    final hasInfo = MetricInfo.has(infoKey);

    return GestureDetector(
      onTap: hasInfo ? () => showMetricInfo(context, infoKey) : null,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (hasInfo) ...[
                  const SizedBox(width: 3),
                  const MetricInfoCue(size: 10),
                ],
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color ?? Colors.white,
                ),
              ),
            ),
            Text(
              unit,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ghost race delta chip (GPX with a PR trace only) ──

class _GhostDeltaChip extends StatelessWidget {
  /// Seconds ahead (positive) or behind (negative) your best-ever run, at the
  /// distance covered so far. Null once you are past the ghost's last point.
  final int? deltaSeconds;
  final bool ghostFinished;

  const _GhostDeltaChip({
    required this.deltaSeconds,
    required this.ghostFinished,
  });

  @override
  Widget build(BuildContext context) {
    final delta = deltaSeconds;

    final IconData icon;
    final Color color;
    final String text;

    if (delta == null) {
      icon = Icons.flag;
      color = Colors.white54;
      text = 'PR finished';
    } else if (delta >= 0) {
      icon = Icons.arrow_drop_up;
      color = Colors.green;
      text = '${_fmt(delta)} ahead of PR';
    } else {
      icon = Icons.arrow_drop_down;
      color = Colors.amber;
      text = '${_fmt(-delta)} behind PR';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          if (ghostFinished && delta != null) ...[
            const SizedBox(width: 6),
            Text(
              '· ghost finished',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
