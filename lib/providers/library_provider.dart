import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../services/github_service.dart';
import '../services/database_service.dart';

/// Merged view: cloud file listing + local DB state for each item type.
class LibraryListNotifier extends AsyncNotifier<List<LibraryItem>> {
  LibraryItemType get _type => LibraryItemType.workout;

  @override
  Future<List<LibraryItem>> build() => _refresh();

  Future<List<LibraryItem>> _refresh() async {
    final cloudFiles = _type == LibraryItemType.workout
        ? await GitHubService.fetchWorkouts()
        : await GitHubService.fetchVirtualRuns();

    final items = <LibraryItem>[];
    for (final file in cloudFiles) {
      final existing = await DatabaseService.getLibraryItemByName(file.name);
      if (existing != null) {
        items.add(existing);
      } else {
        items.add(LibraryItem(name: file.name, type: _type));
      }
    }
    return items;
  }

  Future<void> refreshFromCloud() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_refresh);
  }

  Future<void> downloadFile(String fileName, String downloadUrl) async {
    final content = await GitHubService.downloadFileContent(downloadUrl);

    final dir = await getApplicationDocumentsDirectory();
    final subDir = _type == LibraryItemType.workout ? 'workouts' : 'virtualrun';
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

    state = await AsyncValue.guard(_refresh);
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

/// Holds the download URLs fetched from GitHub, keyed by file name.
final _cloudUrlCacheProvider =
    StateProvider<Map<String, String>>((ref) => {});

/// Fetches cloud URLs once and caches them for the download buttons.
final workoutCloudUrlsProvider = FutureProvider<Map<String, String>>((ref) async {
  final files = await GitHubService.fetchWorkouts();
  final map = {for (final f in files) f.name: f.downloadUrl};
  ref.read(_cloudUrlCacheProvider.notifier).state = {
    ...ref.read(_cloudUrlCacheProvider),
    ...map,
  };
  return map;
});

final virtualRunCloudUrlsProvider = FutureProvider<Map<String, String>>((ref) async {
  final files = await GitHubService.fetchVirtualRuns();
  final map = {for (final f in files) f.name: f.downloadUrl};
  ref.read(_cloudUrlCacheProvider.notifier).state = {
    ...ref.read(_cloudUrlCacheProvider),
    ...map,
  };
  return map;
});
