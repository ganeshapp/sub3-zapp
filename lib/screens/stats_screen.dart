import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/workout_session.dart';
import '../providers/stats_provider.dart';
import '../services/database_service.dart';
import '../services/tcx_file_manager.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(statsProvider);
    final weeklySessions = ref.watch(weeklySessionsProvider);
    final monthlySessions = ref.watch(monthlySessionsProvider);
    final yearlySessions = ref.watch(yearlySessionsProvider);
    final lifetimeSessions = ref.watch(lifetimeSessionsProvider);

    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sessions) {
        return RefreshIndicator(
          onRefresh: () => ref.read(statsProvider.notifier).refresh(),
          child: sessions.isEmpty
              ? _EmptyState(theme: theme)
              : _buildContent(context, theme, sessions, weeklySessions,
                  monthlySessions, yearlySessions, lifetimeSessions),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List<WorkoutSession> sessions,
    List<WorkoutSession> weekly,
    List<WorkoutSession> monthly,
    List<WorkoutSession> yearly,
    List<WorkoutSession> lifetime,
  ) {
    return CustomScrollView(
      slivers: [
        // Volume cards -- 2×2 grid
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _VolumeCard(
                      label: 'This Week',
                      distance: _totalDistance(weekly),
                      duration: _totalDuration(weekly),
                      icon: Icons.calendar_today,
                    ),
                    const SizedBox(width: 12),
                    _VolumeCard(
                      label: 'This Month',
                      distance: _totalDistance(monthly),
                      duration: _totalDuration(monthly),
                      icon: Icons.date_range,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _VolumeCard(
                      label: 'This Year',
                      distance: _totalDistance(yearly),
                      duration: _totalDuration(yearly),
                      icon: Icons.event_note,
                    ),
                    const SizedBox(width: 12),
                    _VolumeCard(
                      label: 'Lifetime',
                      distance: _totalDistance(lifetime),
                      duration: _totalDuration(lifetime),
                      icon: Icons.all_inclusive,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Section title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Run History', style: theme.textTheme.titleLarge),
          ),
        ),

        // History list
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _HistoryCard(session: sessions[index]);
            },
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  double _totalDistance(List<WorkoutSession> sessions) =>
      sessions.fold(0.0, (sum, s) => sum + s.distanceKm);

  int _totalDuration(List<WorkoutSession> sessions) =>
      sessions.fold(0, (sum, s) => sum + s.durationSeconds);
}

// ── Empty state ──

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.bar_chart, size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text('No runs yet',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Complete a workout to see your stats here.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Volume card ──

class _VolumeCard extends StatelessWidget {
  final String label;
  final double distance;
  final int duration;
  final IconData icon;

  const _VolumeCard({
    required this.label,
    required this.distance,
    required this.duration,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 16),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${distance.toStringAsFixed(1)} km',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 2),
            Text(
              _fmtDuration(duration),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ── History card ──

class _HistoryCard extends ConsumerWidget {
  final WorkoutSession session;
  const _HistoryCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isGpx = session.type == 'gpx';
    final displayName = session.title;

    return GestureDetector(
      onLongPress: () => _showActionsMenu(context, ref),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isGpx ? Icons.terrain : Icons.fitness_center,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _fmtDate(session.date),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),

            // Metrics column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${session.distanceKm.toStringAsFixed(2)} km',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtPace(session.avgPace),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),

            // 3-dot menu — built after checking which export files exist,
            // so each entry only appears when its file is really there.
            Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: Colors.white30),
                onPressed: () => _showPopupMenu(buttonContext, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which export files this session really has: legacy sessions have only a
  /// TCX, and so does a session whose FIT generation failed at save time.
  Future<(bool, bool)> _availableFormats() async {
    if (session.id == null) return (false, false);
    return (
      await TcxFileManager.hasFit(session.id!),
      await TcxFileManager.hasTcx(session.id!),
    );
  }

  Future<void> _showPopupMenu(BuildContext context, WidgetRef ref) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final (hasFit, hasTcx) = await _availableFormats();
    if (!context.mounted) return;

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF2C2C2C),
      items: [
        if (hasFit)
          PopupMenuItem(
            value: 'saveFit',
            child: _menuRow(
                Icons.download,
                TcxFileManager.supportsDownloads
                    ? 'Save FIT to Downloads'
                    : 'Save FIT'),
          ),
        if (hasFit)
          PopupMenuItem(
            value: 'shareFit',
            child: _menuRow(Icons.ios_share, 'Share FIT'),
          ),
        if (hasTcx)
          PopupMenuItem(
            value: 'saveTcx',
            child: _menuRow(
                Icons.download,
                TcxFileManager.supportsDownloads
                    ? 'Save TCX to Downloads'
                    : 'Save TCX'),
          ),
        if (hasTcx)
          PopupMenuItem(
            value: 'shareTcx',
            child: _menuRow(Icons.ios_share, 'Share TCX'),
          ),
        PopupMenuItem(
          value: 'delete',
          child: _menuRow(Icons.delete_outline, 'Delete Workout',
              color: Colors.red),
        ),
      ],
    );
    if (selected == null || !context.mounted) return;

    if (selected == 'saveFit') _saveFit(context);
    if (selected == 'shareFit') _shareFit(context);
    if (selected == 'saveTcx') _saveTcx(context);
    if (selected == 'shareTcx') _shareTcx(context);
    if (selected == 'delete') _deleteWorkout(context, ref);
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.white70),
        const SizedBox(width: 8),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    );
  }

  Future<void> _showActionsMenu(BuildContext context, WidgetRef ref) async {
    final (hasFit, hasTcx) = await _availableFormats();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (hasFit)
              ListTile(
                leading: const Icon(Icons.download, color: Colors.white70),
                title: Text(TcxFileManager.supportsDownloads
                    ? 'Save FIT to Downloads'
                    : 'Save FIT File'),
                subtitle: Text(TcxFileManager.supportsDownloads
                    ? 'FIT file in your Downloads folder'
                    : 'Save the FIT from the share sheet'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveFit(context);
                },
              ),
            if (hasFit)
              ListTile(
                leading: const Icon(Icons.ios_share, color: Colors.white70),
                title: const Text('Share FIT'),
                subtitle: const Text('Send the FIT to another app'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareFit(context);
                },
              ),
            if (hasTcx)
              ListTile(
                leading: const Icon(Icons.download, color: Colors.white70),
                title: Text(TcxFileManager.supportsDownloads
                    ? 'Save TCX to Downloads'
                    : 'Save TCX File'),
                subtitle: Text(TcxFileManager.supportsDownloads
                    ? 'TCX file in your Downloads folder'
                    : 'Save the TCX from the share sheet'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveTcx(context);
                },
              ),
            if (hasTcx)
              ListTile(
                leading: const Icon(Icons.ios_share, color: Colors.white70),
                title: const Text('Share TCX'),
                subtitle: const Text('Send the TCX to another app'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareTcx(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Delete Workout', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Remove from history'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteWorkout(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteWorkout(BuildContext context, WidgetRef ref) async {
    if (session.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Delete Workout?'),
        content: const Text('This will permanently remove this run from your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DatabaseService.deleteSession(session.id!);
      // The stored FIT/TCX belong to this session only — don't leave them
      // behind.
      await TcxFileManager.delete(session.id!);
      ref.invalidate(statsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Workout deleted.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Export name: `Sub3_<display name>_<yyyy-MM-dd>`.
  String get _exportName {
    final datePart =
        '${session.date.year}-${session.date.month.toString().padLeft(2, '0')}-${session.date.day.toString().padLeft(2, '0')}';
    return 'Sub3_${session.title}_$datePart';
  }

  /// iPad anchors the share popover to a rectangle; everywhere else this is
  /// ignored. Taken before any await, while the row is still mounted.
  Rect? _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<bool> _hasTcx(BuildContext context) async {
    if (session.id == null) return false;
    if (await TcxFileManager.hasTcx(session.id!)) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TCX file not available for this session.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  Future<bool> _hasFit(BuildContext context) async {
    if (session.id == null) return false;
    if (await TcxFileManager.hasFit(session.id!)) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FIT file not available for this session.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  Future<void> _saveFit(BuildContext context) async {
    final origin = _shareOrigin(context);
    if (!await _hasFit(context)) return;

    try {
      if (!TcxFileManager.supportsDownloads) {
        // iOS has no Downloads folder — hand it to the share sheet instead.
        await TcxFileManager.shareFit(session.id!, _exportName,
            sharePositionOrigin: origin);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Shared — save the FIT from the share sheet.'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final path =
          await TcxFileManager.exportFitToDownloads(session.id!, _exportName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _shareFit(BuildContext context) async {
    final origin = _shareOrigin(context);
    if (!await _hasFit(context)) return;

    try {
      await TcxFileManager.shareFit(session.id!, _exportName,
          sharePositionOrigin: origin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _saveTcx(BuildContext context) async {
    final origin = _shareOrigin(context);
    if (!await _hasTcx(context)) return;

    try {
      if (!TcxFileManager.supportsDownloads) {
        // iOS has no Downloads folder — hand it to the share sheet instead.
        await TcxFileManager.shareTcx(session.id!, _exportName,
            sharePositionOrigin: origin);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Shared — save the TCX from the share sheet.'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final path =
          await TcxFileManager.exportTcxToDownloads(session.id!, _exportName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _shareTcx(BuildContext context) async {
    final origin = _shareOrigin(context);
    if (!await _hasTcx(context)) return;

    try {
      await TcxFileManager.shareTcx(session.id!, _exportName,
          sharePositionOrigin: origin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String _fmtDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtPace(double? pace) {
    if (pace == null || pace <= 0 || pace > 30) return '--:-- /km';
    final m = pace.floor();
    final s = ((pace - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }
}
