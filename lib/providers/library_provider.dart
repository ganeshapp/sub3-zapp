import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../services/database_service.dart';
import '../services/github_service.dart';
import '../services/library_sync_service.dart';

/// Manages the library list: serves cached items instantly, then syncs with
/// GitHub in the background using SHA comparison.
class LibraryListNotifier extends AsyncNotifier<List<LibraryItem>> {
  LibraryItemType get _type => LibraryItemType.workout;
  bool _syncing = false;

  @override
  Future<List<LibraryItem>> build() async {
    final cached = await LibrarySyncService.getCached(_type);
    // Trigger background sync without blocking the initial load
    _backgroundSync();
    return cached;
  }

  Future<void> _backgroundSync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final synced = await LibrarySyncService.syncWithGitHub(
        type: _type,
        onProgress: (partial) {
          state = AsyncValue.data(partial);
        },
      );
      state = AsyncValue.data(synced);
    } catch (e) {
      // If sync fails, keep the cached data that's already loaded
      final current = state.valueOrNull;
      if (current == null || current.isEmpty) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> refreshFromCloud() async {
    state = const AsyncValue.loading();
    _syncing = false;
    try {
      final cached = await LibrarySyncService.getCached(_type);
      if (cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      }
      final synced = await LibrarySyncService.syncWithGitHub(
        type: _type,
        onProgress: (partial) {
          state = AsyncValue.data(partial);
        },
      );
      state = AsyncValue.data(synced);
    } catch (e) {
      final cached = await LibrarySyncService.getCached(_type);
      if (cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      } else {
        state = AsyncValue.error(e, StackTrace.current);
      }
    }
  }

  Future<void> downloadFile(String fileName, String downloadUrl) async {
    final content = await GitHubService.downloadFileContent(downloadUrl);

    final dir = await getApplicationDocumentsDirectory();
    final subDir =
        _type == LibraryItemType.workout ? 'workouts' : 'virtualrun';
    final folder = Directory(p.join(dir.path, subDir));
    if (!folder.existsSync()) folder.createSync(recursive: true);

    final filePath = p.join(folder.path, fileName);
    await File(filePath).writeAsString(content);

    final existing = await DatabaseService.getLibraryItemByName(fileName);
    if (existing?.id != null) {
      await DatabaseService.updateFilePath(existing!.id!, filePath);
    } else {
      await DatabaseService.upsertLibraryItem(
        LibraryItem(name: fileName, type: _type, filePath: filePath),
      );
    }

    final updated = await LibrarySyncService.getCached(_type);
    state = AsyncValue.data(updated);
  }
}

class WorkoutsNotifier extends LibraryListNotifier {
  @override
  LibraryItemType get _type => LibraryItemType.workout;
}

class VirtualRunsNotifier extends LibraryListNotifier {
  @override
  LibraryItemType get _type => LibraryItemType.gpx;
}

final workoutsProvider =
    AsyncNotifierProvider<WorkoutsNotifier, List<LibraryItem>>(
  WorkoutsNotifier.new,
);

final virtualRunsProvider =
    AsyncNotifierProvider<VirtualRunsNotifier, List<LibraryItem>>(
  VirtualRunsNotifier.new,
);
