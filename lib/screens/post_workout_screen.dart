import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ghost_trace.dart';
import '../models/library_item.dart';
import '../models/workout_session.dart';
import '../providers/library_provider.dart';
import '../providers/workout_provider.dart';
import '../providers/stats_provider.dart';
import '../services/database_service.dart';
import '../services/tcx_file_manager.dart';
import '../services/tcx_generator.dart';
import '../widgets/metric_info.dart';

class PostWorkoutScreen extends ConsumerStatefulWidget {
  const PostWorkoutScreen({super.key});

  @override
  ConsumerState<PostWorkoutScreen> createState() => _PostWorkoutScreenState();
}

class _PostWorkoutScreenState extends ConsumerState<PostWorkoutScreen> {
  bool _exporting = false;
  int? _savedSessionId;

  /// In-flight save, memoized so concurrent callers (Save & Exit tapped while
  /// an export is still saving) await the SAME insert instead of both passing
  /// the `_savedSessionId == null` check.
  Future<int?>? _saveFuture;

  /// Pre-run library-item snapshot taken before recordCompletion, so
  /// Discard can revert the badge / best-time bump.
  LibraryItem? _completionBackup;
  LibraryItemType? _completionType;

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
                    workout.workoutFile.displayName,
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
                      // Scrollable: 4 rows of tiles do not fit a 375×667
                      // phone, and the last two (Elev. Gain, Data Points)
                      // would otherwise be unreachable — including their
                      // metric-help dialog.
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
                          infoKey: MetricInfo.avgSpeed,
                        ),
                        _SummaryTile(
                          icon: Icons.directions_run,
                          label: 'Avg Pace',
                          value: _fmtPace(workout.avgPaceMinPerKm),
                          infoKey: MetricInfo.avgPace,
                        ),
                        _SummaryTile(
                          icon: Icons.favorite,
                          label: 'Avg HR',
                          value: workout.avgHr > 0
                              ? '${workout.avgHr.round()} bpm'
                              : '--',
                          infoKey: MetricInfo.heartRate,
                        ),
                        _SummaryTile(
                          icon: Icons.favorite_border,
                          label: 'Max HR',
                          value: workout.maxHr > 0
                              ? '${workout.maxHr.round()} bpm'
                              : '--',
                          infoKey: MetricInfo.heartRate,
                        ),
                        _SummaryTile(
                          icon: Icons.landscape,
                          label: 'Elev. Gain',
                          value:
                              '${workout.elevationGain.toStringAsFixed(0)} m',
                          infoKey: MetricInfo.elevationGain,
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
                      // Export row: save the TCX where the user can find it
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: () => _saveTcx(workout),
                                icon: const Icon(Icons.download, size: 20),
                                label: Text(
                                  TcxFileManager.supportsDownloads
                                      ? 'Save TCX to Downloads'
                                      : 'Save TCX',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.blueGrey.shade600,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: () => _shareTcx(workout),
                                icon: const Icon(Icons.ios_share, size: 18),
                                label: const Text('Share'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ),
                        ],
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

          // Loading overlay while the TCX is written / shared
          if (_exporting)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.deepOrange),
                    const SizedBox(height: 20),
                    Text(
                      'Preparing TCX file...',
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
    final int? sessionId;
    try {
      sessionId = await _ensureSaved(w);
    } catch (e) {
      // Without this the button would silently do nothing, and the screen
      // has no way out other than Discard.
      _snack('Save failed: $e', Colors.red.shade700);
      return;
    }
    if (sessionId == null) return;
    ref.read(activeWorkoutProvider.notifier).clear();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Saves the session + TCX file once, caches the ID for subsequent operations.
  /// A failed save clears the memo so the next tap genuinely retries the
  /// insert instead of replaying the cached error forever.
  Future<int?> _ensureSaved(ActiveWorkoutState w) {
    if (_savedSessionId != null) return Future.value(_savedSessionId);
    return _saveFuture ??= _save(w).catchError((Object e, StackTrace st) {
      _saveFuture = null;
      return Future<int?>.error(e, st);
    });
  }

  Future<int?> _save(ActiveWorkoutState w) async {
    final now = DateTime.now();
    final session = WorkoutSession(
      date: now,
      fileName: w.workoutFile.name,
      displayName: w.workoutFile.displayName,
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

    // Completion tracking: only a genuinely finished route (≥99% of the
    // distance) or a structured workout that ran to the end earns the badge.
    // Snapshot the library row first so Discard can revert the bump.
    if (w.earnedCompletion) {
      final type =
          w.workoutFile.isGpx ? LibraryItemType.gpx : LibraryItemType.workout;
      _completionBackup =
          await DatabaseService.getLibraryItemByName(w.workoutFile.name);
      _completionType = type;
      await DatabaseService.recordCompletion(
        fileName: w.workoutFile.name,
        type: type,
        elapsedSeconds: w.elapsedSeconds,
        routeCompleted: w.routeCompleted,
        prTrace: _buildPrTrace(w),
      );
      await _reloadLibrary(type);
    }

    // Refresh the stats screen provider
    ref.invalidate(statsProvider);

    return _savedSessionId;
  }

  /// The ghost future runs race against: cumulative metres, one sample per
  /// second, from a route that was actually finished. The database keeps it
  /// only if this run turns out to be the new best.
  String? _buildPrTrace(ActiveWorkoutState w) {
    if (!w.routeCompleted) return null;
    final metres = <double>[
      0,
      ...w.telemetry.map((t) => t.cumulativeDistanceKm * 1000),
    ];
    return GhostTrace.fromDistances(metres)?.toJson();
  }

  Future<void> _reloadLibrary(LibraryItemType type) async {
    if (type == LibraryItemType.workout) {
      await ref.read(workoutsProvider.notifier).reloadFromCache();
    } else {
      await ref.read(virtualRunsProvider.notifier).reloadFromCache();
    }
  }

  /// Export name: `Sub3_<display name>_<yyyy-MM-dd>`.
  String _exportName(ActiveWorkoutState w) {
    final now = DateTime.now();
    final datePart = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return 'Sub3_${w.workoutFile.displayName}_$datePart';
  }

  Future<void> _saveTcx(ActiveWorkoutState w) async {
    if (_exporting) return;
    if (_nothingToExport(w)) return;
    final origin = _shareOrigin();
    setState(() => _exporting = true);
    try {
      final sessionId = await _ensureSaved(w);
      if (sessionId == null) throw Exception('Could not save this run');

      if (!TcxFileManager.supportsDownloads) {
        // iOS has no Downloads folder — hand it to the share sheet instead.
        await TcxFileManager.shareTcx(sessionId, _exportName(w),
            sharePositionOrigin: origin);
        _snack('Shared — save the TCX from the share sheet.',
            Colors.green.shade700);
        return;
      }

      final path =
          await TcxFileManager.exportToDownloads(sessionId, _exportName(w));
      _snack('Saved to $path', Colors.green.shade700);
    } catch (e) {
      _snack('Save failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareTcx(ActiveWorkoutState w) async {
    if (_exporting) return;
    if (_nothingToExport(w)) return;
    final origin = _shareOrigin();
    setState(() => _exporting = true);
    try {
      final sessionId = await _ensureSaved(w);
      if (sessionId == null) throw Exception('Could not save this run');
      await TcxFileManager.shareTcx(sessionId, _exportName(w),
          sharePositionOrigin: origin);
    } catch (e) {
      _snack('Share failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// iPad anchors the share popover to a rectangle; everywhere else this is
  /// ignored.
  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// A run with no telemetry has no TCX file to save or share.
  bool _nothingToExport(ActiveWorkoutState w) {
    if (w.telemetry.isNotEmpty) return false;
    _snack('Nothing to export — this run has no data.', Colors.orange.shade800);
    return true;
  }

  void _snack(String message, Color background) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        duration: const Duration(seconds: 4),
      ),
    );
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
            onPressed: () async {
              Navigator.pop(ctx);
              await _undoSave();
              if (!mounted) return;
              ref.read(activeWorkoutProvider.notifier).clear();
              Navigator.of(this.context).popUntil((route) => route.isFirst);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  /// Exporting a TCX saves the session first, so Discard has to undo that:
  /// remove the row, its TCX file, and the completion badge bump.
  Future<void> _undoSave() async {
    if (_savedSessionId == null) return;
    try {
      await DatabaseService.deleteSession(_savedSessionId!);
      await TcxFileManager.delete(_savedSessionId!);

      final backup = _completionBackup;
      if (backup != null) {
        await DatabaseService.restoreCompletion(
          fileName: backup.name,
          completionCount: backup.completionCount,
          bestTimeSeconds: backup.bestTimeSeconds,
          prTrace: backup.prTrace,
        );
        if (_completionType != null) await _reloadLibrary(_completionType!);
      }

      _savedSessionId = null;
      _saveFuture = null;
      _completionBackup = null;
      _completionType = null;
      ref.invalidate(statsProvider);
    } catch (_) {
      // Best-effort cleanup; still leave the post-workout screen.
    }
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

  /// Glossary key: when set, the tile shows a `(?)` and tapping anywhere on
  /// it explains the metric in plain words.
  final String? infoKey;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.infoKey,
  });

  @override
  Widget build(BuildContext context) {
    final hasInfo = MetricInfo.has(infoKey);

    return GestureDetector(
      onTap: hasInfo ? () => showMetricInfo(context, infoKey) : null,
      child: Container(
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
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white38)),
                ),
                if (hasInfo) ...[
                  const SizedBox(width: 4),
                  const MetricInfoCue(),
                ],
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
      ),
    );
  }
}
