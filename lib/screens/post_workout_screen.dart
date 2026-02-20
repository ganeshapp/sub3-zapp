import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/workout_session.dart';
import '../providers/workout_provider.dart';
import '../providers/stats_provider.dart';
import '../services/database_service.dart';
import '../services/strava_service.dart';
import '../services/tcx_file_manager.dart';
import '../services/tcx_generator.dart';

class PostWorkoutScreen extends ConsumerStatefulWidget {
  const PostWorkoutScreen({super.key});

  @override
  ConsumerState<PostWorkoutScreen> createState() => _PostWorkoutScreenState();
}

class _PostWorkoutScreenState extends ConsumerState<PostWorkoutScreen> {
  bool _uploading = false;
  bool _uploaded = false;
  int? _savedSessionId;

  @override
  Widget build(BuildContext context) {
    final workout = ref.watch(activeWorkoutProvider);
    if (workout == null) {
      return const Scaffold(body: Center(child: Text('No workout data')));
    }

    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFF121212),
            appBar: AppBar(
              title: const Text('Workout Summary'),
              automaticallyImplyLeading: false,
            ),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Title
                  Text(
                    workout.workoutFile.name
                        .replaceAll(RegExp(r'\.(json|gpx)$'), ''),
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    workout.workoutFile.isGpx
                        ? 'Virtual Run'
                        : 'Structured Workout',
                    style:
                        GoogleFonts.inter(fontSize: 14, color: Colors.white54),
                  ),
                  const SizedBox(height: 24),

                  // Summary grid — 4 rows × 2 cols
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.65,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _SummaryTile(
                          icon: Icons.timer,
                          label: 'Duration',
                          value: _fmtDuration(workout.elapsedSeconds),
                        ),
                        _SummaryTile(
                          icon: Icons.straighten,
                          label: 'Distance',
                          value:
                              '${workout.totalDistanceKm.toStringAsFixed(2)} km',
                        ),
                        _SummaryTile(
                          icon: Icons.speed,
                          label: 'Avg Speed',
                          value:
                              '${workout.avgSpeedKmh.toStringAsFixed(1)} km/h',
                        ),
                        _SummaryTile(
                          icon: Icons.directions_run,
                          label: 'Avg Pace',
                          value: _fmtPace(workout.avgPaceMinPerKm),
                        ),
                        _SummaryTile(
                          icon: Icons.favorite,
                          label: 'Avg HR',
                          value: workout.avgHr > 0
                              ? '${workout.avgHr.round()} bpm'
                              : '--',
                        ),
                        _SummaryTile(
                          icon: Icons.favorite_border,
                          label: 'Max HR',
                          value: workout.maxHr > 0
                              ? '${workout.maxHr.round()} bpm'
                              : '--',
                        ),
                        _SummaryTile(
                          icon: Icons.landscape,
                          label: 'Elev. Gain',
                          value:
                              '${workout.elevationGain.toStringAsFixed(0)} m',
                        ),
                        _SummaryTile(
                          icon: Icons.timeline,
                          label: 'Data Points',
                          value: '${workout.telemetry.length}',
                        ),
                      ],
                    ),
                  ),

                  // Action buttons
                  Column(
                    children: [
                      // Upload to Strava
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _uploaded
                              ? null
                              : () => _uploadToStrava(workout),
                          icon: _uploaded
                              ? const Icon(Icons.check, size: 20)
                              : const Icon(Icons.upload, size: 20),
                          label: Text(_uploaded
                              ? 'Uploaded to Strava'
                              : 'Upload to Strava'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                _uploaded ? Colors.green : Colors.deepOrange,
                            disabledBackgroundColor: Colors.green.shade800,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Save & Discard row
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => _discard(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Discard'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: () =>
                                    _saveAndExit(context, workout),
                                icon: const Icon(Icons.save, size: 20),
                                label: const Text('Save & Exit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay during Strava upload
          if (_uploading)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.deepOrange),
                    const SizedBox(height: 20),
                    Text(
                      'Uploading to Strava...',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Actions ──

  Future<void> _saveAndExit(
      BuildContext context, ActiveWorkoutState w) async {
    final sessionId = await _ensureSaved(w);
    if (sessionId == null) return;
    ref.read(activeWorkoutProvider.notifier).clear();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Saves the session + TCX file once, caches the ID for subsequent operations.
  Future<int?> _ensureSaved(ActiveWorkoutState w) async {
    if (_savedSessionId != null) return _savedSessionId;
    final now = DateTime.now();
    final session = WorkoutSession(
      date: now,
      fileName: w.workoutFile.name,
      type: w.workoutFile.isGpx ? 'gpx' : 'workout',
      durationSeconds: w.elapsedSeconds,
      distanceKm: w.totalDistanceKm,
      avgHr: w.avgHr > 0 ? w.avgHr : null,
      avgPace: w.avgPaceMinPerKm > 0 ? w.avgPaceMinPerKm : null,
      avgSpeed: w.avgSpeedKmh > 0 ? w.avgSpeedKmh : null,
      elevationGain: w.elevationGain,
    );
    _savedSessionId = await DatabaseService.insertSession(session);

    // Persist the TCX file for future export from history
    if (_savedSessionId != null && w.telemetry.isNotEmpty) {
      final startTime = now.subtract(Duration(seconds: w.elapsedSeconds));
      final tcx = TcxGenerator.generate(
        startTime: startTime,
        telemetry: w.telemetry,
        totalDistanceM: w.totalDistanceKm * 1000,
        totalTimeSeconds: w.elapsedSeconds,
      );
      await TcxFileManager.save(_savedSessionId!, tcx);
    }

    // Refresh the stats screen provider
    ref.invalidate(statsProvider);

    return _savedSessionId;
  }

  Future<void> _uploadToStrava(ActiveWorkoutState w) async {
    final linked = await StravaService.isLinked;
    if (!linked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link your Strava account in Settings first.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _uploading = true);

    try {
      // Save session first so we can mark it as uploaded
      final sessionId = await _ensureSaved(w);

      // Generate TCX from telemetry
      final startTime =
          DateTime.now().subtract(Duration(seconds: w.elapsedSeconds));
      final tcx = TcxGenerator.generate(
        startTime: startTime,
        telemetry: w.telemetry,
        totalDistanceM: w.totalDistanceKm * 1000,
        totalTimeSeconds: w.elapsedSeconds,
      );

      final activityName = w.workoutFile.name
          .replaceAll(RegExp(r'\.(json|gpx)$'), '');

      await StravaService.uploadTcx(
        tcxContent: tcx,
        activityName: 'Sub3 $activityName',
      );

      // Mark as uploaded in DB
      if (sessionId != null) {
        await DatabaseService.markUploadedToStrava(sessionId);
      }

      setState(() {
        _uploading = false;
        _uploaded = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Successfully uploaded to Strava!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Strava upload failed: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _discard(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Discard Workout?'),
        content: const Text(
            'This will permanently delete this session\'s data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(activeWorkoutProvider.notifier).clear();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  // ── Formatters ──

  String _fmtDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _fmtPace(double minPerKm) {
    if (minPerKm <= 0 || minPerKm > 30) return '--:--';
    final m = minPerKm.floor();
    final s = ((minPerKm - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }
}

// ── Summary tile ──

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white38),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
