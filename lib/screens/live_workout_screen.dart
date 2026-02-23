import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/workout_provider.dart';
import '../widgets/workout_visualizer.dart';
import 'post_workout_screen.dart';

class LiveWorkoutScreen extends ConsumerWidget {
  const LiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(activeWorkoutProvider);
    if (workout == null) {
      return const Scaffold(body: Center(child: Text('No active workout')));
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

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final isPaused = workout.phase == WorkoutPhase.paused;

    return GestureDetector(
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
          ),

          // Distance progress bar for GPX routes
          if (workout.workoutFile.isGpx) ...[
            const SizedBox(height: 8),
            _DistanceProgressBar(
              currentKm: workout.totalDistanceKm,
              totalKm: workout.workoutFile.totalDistanceM / 1000,
            ),
          ],
          const SizedBox(height: 12),

          // Metric tiles — 3×3 grid
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MetricTile(
                  label: 'HR',
                  value: workout.currentHr > 0
                      ? '${workout.currentHr.round()}'
                      : '--',
                  unit: 'bpm',
                  color: Colors.red,
                ),
                _MetricTile(
                  label: 'PACE',
                  value: _fmtPace(workout.currentPaceMinPerKm),
                  unit: '/km',
                ),
                _MetricTile(
                  label: 'AVG PACE',
                  value: _fmtPace(workout.avgPaceMinPerKm),
                  unit: '/km',
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
                ),
                _MetricTile(
                  label: 'INCLINE',
                  value: workout.currentInclinePct.toStringAsFixed(1),
                  unit: '%',
                  color: Colors.green,
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
                ),
                _MetricTile(
                  label: 'AVG HR',
                  value: workout.avgHr > 0
                      ? '${workout.avgHr.round()}'
                      : '--',
                  unit: 'bpm',
                ),
              ],
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
    );
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

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
              letterSpacing: 1,
            ),
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
    );
  }
}
