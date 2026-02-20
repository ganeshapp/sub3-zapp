import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                  urlsProvider: workoutCloudUrlsProvider,
                  emptyIcon: Icons.fitness_center,
                  emptyLabel: 'No workouts found',
                ),
                _LibraryTab(
                  itemsProvider: virtualRunsProvider,
                  urlsProvider: virtualRunCloudUrlsProvider,
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
  final FutureProvider<Map<String, String>> urlsProvider;
  final IconData emptyIcon;
  final String emptyLabel;

  const _LibraryTab({
    required this.itemsProvider,
    required this.urlsProvider,
    required this.emptyIcon,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsProvider);
    final urlsAsync = ref.watch(urlsProvider);

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

        final urls = urlsAsync.valueOrNull ?? {};

        return RefreshIndicator(
          onRefresh: () => ref.read(itemsProvider.notifier).refreshFromCloud(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final downloadUrl = urls[item.name];
              return _LibraryItemTile(
                item: item,
                downloadUrl: downloadUrl,
                onDownload: downloadUrl != null
                    ? () => ref
                        .read(itemsProvider.notifier)
                        .downloadFile(item.name, downloadUrl)
                    : null,
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

class _LibraryItemTile extends StatefulWidget {
  final LibraryItem item;
  final String? downloadUrl;
  final VoidCallback? onDownload;
  final VoidCallback? onStart;

  const _LibraryItemTile({
    required this.item,
    this.downloadUrl,
    this.onDownload,
    this.onStart,
  });

  @override
  State<_LibraryItemTile> createState() => _LibraryItemTileState();
}

class _LibraryItemTileState extends State<_LibraryItemTile> {
  bool _downloading = false;

  Future<void> _handleDownload() async {
    if (widget.onDownload == null) return;
    setState(() => _downloading = true);
    try {
      widget.onDownload!();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String get _displayName {
    final name = widget.item.name;
    if (name.endsWith('.json') || name.endsWith('.gpx')) {
      return name.substring(0, name.lastIndexOf('.'));
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return GestureDetector(
      onTap: item.isDownloaded ? widget.onStart : null,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.isDownloaded
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.type == LibraryItemType.workout
                  ? Icons.fitness_center
                  : Icons.terrain,
              color: item.isDownloaded
                  ? theme.colorScheme.primary
                  : Colors.white38,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (item.completionCount > 0) ...[
                      Icon(Icons.check_circle,
                          size: 14, color: Colors.green.shade400),
                      const SizedBox(width: 4),
                      Text(
                        '${item.completionCount}x',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 12, color: Colors.green.shade400),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (item.type == LibraryItemType.gpx &&
                        item.bestTimeSeconds != null) ...[
                      Icon(Icons.emoji_events,
                          size: 14, color: Colors.amber.shade400),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(item.bestTimeSeconds!),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 12, color: Colors.amber.shade400),
                      ),
                    ],
                    if (item.completionCount == 0 &&
                        item.bestTimeSeconds == null)
                      Text(
                        item.isDownloaded ? 'Ready to run' : 'Not downloaded',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (item.isDownloaded)
            Icon(Icons.play_circle_filled, color: theme.colorScheme.primary, size: 26)
          else if (_downloading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: _handleDownload,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.download,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

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
          Icon(icon, size: 64,
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
            Icon(Icons.cloud_off, size: 56,
                color: theme.colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Failed to load', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
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
