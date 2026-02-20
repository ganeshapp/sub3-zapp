import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import 'database_service.dart';
import 'github_service.dart';
import 'workout_parser.dart';

class LibrarySyncService {
  /// Get cached items from local DB for the given type.
  static Future<List<LibraryItem>> getCached(LibraryItemType type) {
    return DatabaseService.getLibraryItems(type);
  }

  /// Sync with GitHub: compare SHAs, fetch/parse only changed files.
  /// Returns the updated list after sync completes.
  /// Calls [onProgress] with the updated list after each file is synced,
  /// so the UI can update incrementally.
  static Future<List<LibraryItem>> syncWithGitHub({
    required LibraryItemType type,
    void Function(List<LibraryItem>)? onProgress,
  }) async {
    final cloudFiles = type == LibraryItemType.workout
        ? await GitHubService.fetchWorkouts()
        : await GitHubService.fetchVirtualRuns();

    final result = <LibraryItem>[];

    for (final file in cloudFiles) {
      final existing = await DatabaseService.getLibraryItemByName(file.name);

      if (existing != null && existing.sha == file.sha && existing.hasCachedPreview) {
        result.add(existing);
        continue;
      }

      // SHA changed or no cached preview -- fetch and parse
      try {
        final content =
            await GitHubService.downloadFileContent(file.downloadUrl);
        final metadata = _extractMetadata(file.name, content);
        final preview = _extractPreviewPoints(file.name, content);

        // Save the raw file locally if it's being downloaded for the first time
        String? filePath = existing?.filePath;
        if (filePath == null) {
          filePath = await _saveFile(file.name, content, type);
        } else {
          // Update existing file content (SHA changed means content changed)
          await File(filePath).writeAsString(content);
        }

        final item = LibraryItem(
          id: existing?.id,
          name: file.name,
          type: type,
          filePath: filePath,
          completionCount: existing?.completionCount ?? 0,
          bestTimeSeconds: existing?.bestTimeSeconds,
          sha: file.sha,
          metadataJson: jsonEncode(metadata),
          previewPoints: jsonEncode(preview),
        );

        await DatabaseService.upsertLibraryItem(item);
        final saved = await DatabaseService.getLibraryItemByName(file.name);
        result.add(saved ?? item);
      } catch (_) {
        // If fetch fails, keep existing or add a stub
        result.add(existing ?? LibraryItem(name: file.name, type: type));
      }

      onProgress?.call(List.unmodifiable(result));
    }

    return result;
  }

  static Future<String> _saveFile(
      String name, String content, LibraryItemType type) async {
    final dir = await getApplicationDocumentsDirectory();
    final subDir = type == LibraryItemType.workout ? 'workouts' : 'virtualrun';
    final folder = Directory(p.join(dir.path, subDir));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final filePath = p.join(folder.path, name);
    await File(filePath).writeAsString(content);
    return filePath;
  }

  /// Extract metadata map from file content.
  static Map<String, dynamic> _extractMetadata(
      String fileName, String content) {
    try {
      if (fileName.endsWith('.gpx')) {
        final wf = WorkoutParser.parseContent(fileName, content);
        final distKm = wf.totalDistanceM / 1000;
        final displayName =
            WorkoutParser.extractDisplayName(fileName, content);
        double elevGain = 0;
        if (wf.gpxPoints != null && wf.gpxPoints!.length >= 2) {
          for (var i = 1; i < wf.gpxPoints!.length; i++) {
            final d =
                wf.gpxPoints![i].elevation - wf.gpxPoints![i - 1].elevation;
            if (d > 0) elevGain += d;
          }
        }
        return {
          'name': displayName,
          'distanceKm': double.parse(distKm.toStringAsFixed(2)),
          'elevationGain': elevGain.round(),
          'pointCount': wf.gpxPoints?.length ?? 0,
        };
      } else {
        final wf = WorkoutParser.parseContent(fileName, content);
        final displayName =
            WorkoutParser.extractDisplayName(fileName, content);
        final maxSpeed = wf.intervals != null && wf.intervals!.isNotEmpty
            ? wf.intervals!.map((i) => i.speedKmh).reduce(max)
            : 0.0;
        return {
          'name': displayName,
          'totalDurationSeconds': wf.totalDurationSeconds,
          'maxSpeed': double.parse(maxSpeed.toStringAsFixed(1)),
          'intervalCount': wf.intervals?.length ?? 0,
        };
      }
    } catch (_) {
      return {'name': fileName.replaceAll(RegExp(r'\.(json|gpx)$'), '')};
    }
  }

  /// Extract simplified preview points for CustomPaint.
  /// JSON: list of {d, s} maps (duration, speed per interval).
  /// GPX: list of [lat, lon] pairs, downsampled to ~80 points max.
  static List<dynamic> _extractPreviewPoints(
      String fileName, String content) {
    try {
      if (fileName.endsWith('.gpx')) {
        final wf = WorkoutParser.parseContent(fileName, content);
        final pts = wf.gpxPoints ?? [];
        if (pts.isEmpty) return [];

        final step = pts.length <= 80 ? 1 : (pts.length / 80).ceil();
        final sampled = <List<double>>[];
        for (var i = 0; i < pts.length; i += step) {
          sampled.add([
            double.parse(pts[i].lat.toStringAsFixed(6)),
            double.parse(pts[i].lon.toStringAsFixed(6)),
          ]);
        }
        // Always include last point
        if (sampled.isEmpty ||
            sampled.last[0] != pts.last.lat ||
            sampled.last[1] != pts.last.lon) {
          sampled.add([
            double.parse(pts.last.lat.toStringAsFixed(6)),
            double.parse(pts.last.lon.toStringAsFixed(6)),
          ]);
        }
        return sampled;
      } else {
        final wf = WorkoutParser.parseContent(fileName, content);
        final intervals = wf.intervals ?? [];
        return intervals
            .map((i) => {'d': i.durationSeconds, 's': i.speedKmh})
            .toList();
      }
    } catch (_) {
      return [];
    }
  }
}
