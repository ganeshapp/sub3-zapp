import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../providers/workout_provider.dart';
import '../services/workout_parser.dart';
import 'live_workout_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Structured Workouts'),
              Tab(text: 'Virtual Runs'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LibraryTab(
                  itemsProvider: workoutsProvider,
                  emptyIcon: Icons.fitness_center,
                  emptyLabel: 'No workouts found',
                ),
                _LibraryTab(
                  itemsProvider: virtualRunsProvider,
                  emptyIcon: Icons.terrain,
                  emptyLabel: 'No virtual runs found',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTab extends ConsumerWidget {
  final AsyncNotifierProvider<LibraryListNotifier, List<LibraryItem>>
      itemsProvider;
  final IconData emptyIcon;
  final String emptyLabel;

  const _LibraryTab({
    required this.itemsProvider,
    required this.emptyIcon,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsProvider);

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => ref.read(itemsProvider.notifier).refreshFromCloud(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyView(icon: emptyIcon, label: emptyLabel);
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(itemsProvider.notifier).refreshFromCloud(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return _RichCard(
                item: item,
                onStart: item.isDownloaded
                    ? () => _launchWorkout(context, ref, item)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

Future<void> _launchWorkout(
    BuildContext context, WidgetRef ref, LibraryItem item) async {
  if (item.filePath == null) return;
  try {
    final file = await WorkoutParser.parseFile(item.filePath!);
    ref.read(activeWorkoutProvider.notifier).startWorkout(file);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LiveWorkoutScreen()),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load file: $e')),
      );
    }
  }
}

// ── Rich Card (instant from cache) ──

class _RichCard extends StatelessWidget {
  final LibraryItem item;
  final VoidCallback? onStart;

  const _RichCard({required this.item, this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGpx = item.type == LibraryItemType.gpx;
    final meta = _decodeMeta();
    final preview = _decodePreview();

    return GestureDetector(
      onTap: item.isDownloaded ? onStart : null,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mini visualizer (instant from cached preview_points)
            SizedBox(
              height: 64,
              width: double.infinity,
              child: preview != null && preview.isNotEmpty
                  ? CustomPaint(
                      painter: isGpx
                          ? _MiniRoutePainter(points: preview)
                          : _MiniBarPainter(bars: preview),
                    )
                  : item.hasCachedPreview
                      ? const SizedBox.shrink()
                      : Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
            ),

            // Info row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 12),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: item.isDownloaded
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isGpx ? Icons.terrain : Icons.fitness_center,
                      color: item.isDownloaded
                          ? theme.colorScheme.primary
                          : Colors.white38,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title + subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(meta),
                          style:
                              theme.textTheme.titleLarge?.copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _buildSubtitle(meta, isGpx),
                      ],
                    ),
                  ),

                  // Badges + action
                  _buildTrailing(theme, isGpx),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _decodeMeta() {
    if (item.metadataJson == null) return null;
    try {
      return jsonDecode(item.metadataJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? _decodePreview() {
    if (item.previewPoints == null) return null;
    try {
      return jsonDecode(item.previewPoints!) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _displayName(Map<String, dynamic>? meta) {
    if (meta != null && meta['name'] != null) {
      return meta['name'].toString();
    }
    return item.name
        .replaceAll(RegExp(r'\.(json|gpx)$'), '')
        .replaceAll('_', ' ');
  }

  Widget _buildSubtitle(Map<String, dynamic>? meta, bool isGpx) {
    final parts = <String>[];

    if (meta != null) {
      if (isGpx) {
        final dist = (meta['distanceKm'] as num?)?.toDouble() ?? 0;
        if (dist > 0) parts.add('${dist.toStringAsFixed(1)} km');
        final elev = (meta['elevationGain'] as num?)?.toInt() ?? 0;
        if (elev > 0) parts.add('$elev m gain');
      } else {
        final dur = (meta['totalDurationSeconds'] as num?)?.toInt() ?? 0;
        if (dur > 0) parts.add(_fmtDuration(dur));
        final maxSpd = (meta['maxSpeed'] as num?)?.toDouble() ?? 0;
        if (maxSpd > 0) parts.add('${maxSpd.toStringAsFixed(1)} km/h peak');
      }
    }

    if (parts.isEmpty) {
      parts.add(item.isDownloaded ? 'Ready to run' : 'Syncing...');
    }

    return Text(
      parts.join('  ·  '),
      style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildTrailing(ThemeData theme, bool isGpx) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Completion count badge
        if (item.completionCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    size: 12, color: Colors.green.shade400),
                const SizedBox(width: 3),
                Text(
                  '${item.completionCount}x',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.green.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],

        // PR badge for GPX
        if (isGpx && item.bestTimeSeconds != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events,
                    size: 12, color: Colors.amber.shade400),
                const SizedBox(width: 3),
                Text(
                  _fmtDuration(item.bestTimeSeconds!),
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.amber.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],

        // Play icon
        if (item.isDownloaded)
          Icon(Icons.play_circle_filled,
              color: theme.colorScheme.primary, size: 28),
      ],
    );
  }

  String _fmtDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (s < 600) return '${m}m ${sec.toString().padLeft(2, '0')}s';
    return '${m}m';
  }
}

// ── Mini bar chart painter (JSON intervals from cached preview_points) ──

class _MiniBarPainter extends CustomPainter {
  final List<dynamic> bars;
  _MiniBarPainter({required this.bars});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    int totalDur = 0;
    double maxSpeed = 1.0;
    for (final b in bars) {
      final d = ((b as Map)['d'] as num?)?.toInt() ?? 0;
      final s = (b['s'] as num?)?.toDouble() ?? 0;
      totalDur += d;
      if (s > maxSpeed) maxSpeed = s;
    }
    if (totalDur == 0) return;

    const hPad = 6.0;
    const vPad = 8.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - vPad * 2;

    final barPaint = Paint()..color = Colors.red.withValues(alpha: 0.25);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.red.withValues(alpha: 0.15);

    double x = hPad;
    for (final b in bars) {
      final d = ((b as Map)['d'] as num?)?.toInt() ?? 0;
      final s = (b['s'] as num?)?.toDouble() ?? 0;
      final w = (d / totalDur) * drawW;
      final h = (s / maxSpeed) * drawH;
      final rect = Rect.fromLTWH(x, size.height - vPad - h, w, h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), barPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), borderPaint);
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarPainter old) => false;
}

// ── Mini route map painter (GPX from cached preview_points) ──

class _MiniRoutePainter extends CustomPainter {
  final List<dynamic> points;
  _MiniRoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const pad = 10.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;

    double minLat = (points.first as List)[0].toDouble();
    double maxLat = minLat;
    double minLon = (points.first as List)[1].toDouble();
    double maxLon = minLon;

    for (final p in points) {
      final lat = (p as List)[0].toDouble();
      final lon = p[1].toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    final latRange = (maxLat - minLat).clamp(1e-6, double.infinity);
    final lonRange = (maxLon - minLon).clamp(1e-6, double.infinity);
    final scaleX = drawW / lonRange;
    final scaleY = drawH / latRange;
    final scale = min(scaleX, scaleY);
    final offsetX = pad + (drawW - lonRange * scale) / 2;
    final offsetY = pad + (drawH - latRange * scale) / 2;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final lat = (points[i] as List)[0].toDouble();
      final lon = (points[i] as List)[1].toDouble();
      final x = offsetX + (lon - minLon) * scale;
      final y = offsetY + (maxLat - lat) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.red.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.red.withValues(alpha: 0.6);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniRoutePainter old) => false;
}

// ── Empty/Error views ──

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyView({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(label, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 56,
                color: theme.colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Failed to load', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
