import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/workout_session.dart';

class DatabaseService {
  static Database? _db;

  /// Bumped to 3 for `workout_sessions.display_name` and
  /// `library_items.pr_trace`.
  static const schemaVersion = 3;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'sub3.db');

    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: createSchema,
      onUpgrade: migrate,
    );
  }

  /// Fresh install: the current schema.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE library_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        file_path TEXT,
        completion_count INTEGER NOT NULL DEFAULT 0,
        best_time_seconds INTEGER,
        sha TEXT,
        metadata_json TEXT,
        preview_points TEXT,
        pr_trace TEXT
      )
    ''');
    // is_uploaded_to_strava is a leftover from the removed Strava upload
    // feature. The column stays so old databases keep working; nothing
    // reads or writes it any more.
    await db.execute('''
      CREATE TABLE workout_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        file_name TEXT NOT NULL,
        display_name TEXT,
        type TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        distance_km REAL NOT NULL,
        avg_hr REAL,
        avg_pace REAL,
        avg_speed REAL,
        elevation_gain REAL,
        is_uploaded_to_strava INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Existing install: add the columns each version introduced. Never drops
  /// or rebuilds a table, so history and library stats survive an upgrade.
  static Future<void> migrate(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE library_items ADD COLUMN sha TEXT');
      await db.execute(
          'ALTER TABLE library_items ADD COLUMN metadata_json TEXT');
      await db.execute(
          'ALTER TABLE library_items ADD COLUMN preview_points TEXT');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE workout_sessions ADD COLUMN display_name TEXT');
      await db.execute('ALTER TABLE library_items ADD COLUMN pr_trace TEXT');
    }
  }

  // ── Library Items ──

  static Future<int> upsertLibraryItem(LibraryItem item) async {
    final db = await database;
    return db.insert(
      'library_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<LibraryItem>> getLibraryItems(LibraryItemType type) async {
    final db = await database;
    final maps = await db.query(
      'library_items',
      where: 'type = ?',
      whereArgs: [type.name],
      orderBy: 'name ASC',
    );
    return maps.map(LibraryItem.fromMap).toList();
  }

  static Future<LibraryItem?> getLibraryItemByName(String name) async {
    final db = await database;
    final maps = await db.query(
      'library_items',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return LibraryItem.fromMap(maps.first);
  }

  static Future<void> updateFilePath(int id, String filePath) async {
    final db = await database;
    await db.update(
      'library_items',
      {'file_path': filePath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateCachedPreview({
    required int id,
    required String sha,
    required String metadataJson,
    required String previewPoints,
  }) async {
    final db = await database;
    await db.update(
      'library_items',
      {
        'sha': sha,
        'metadata_json': metadataJson,
        'preview_points': previewPoints,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// True when a finished route run beats the stored best time (or is the
  /// first one). Only then does the PR — and the ghost trace runners race
  /// against — change hands.
  static bool isNewBest({
    required LibraryItemType type,
    required int elapsedSeconds,
    required bool routeCompleted,
    required int? currentBestSeconds,
  }) {
    if (type != LibraryItemType.gpx || !routeCompleted) return false;
    if (elapsedSeconds <= 0) return false;
    return currentBestSeconds == null || elapsedSeconds < currentBestSeconds;
  }

  /// Completion tracking: bump the library item's completion count and, for
  /// routes that were actually finished, record the best time. Callers must
  /// only call this for a genuinely completed run — see
  /// `ActiveWorkoutState.earnedCompletion`.
  ///
  /// [prTrace] is the run's distance trace; it is stored only when the run
  /// sets a new best, so the ghost always belongs to the PR.
  static Future<void> recordCompletion({
    required String fileName,
    required LibraryItemType type,
    required int elapsedSeconds,
    bool routeCompleted = false,
    String? prTrace,
  }) async {
    final item = await getLibraryItemByName(fileName);
    if (item == null || item.id == null) return;

    int? bestTime = item.bestTimeSeconds;
    if (type == LibraryItemType.gpx && routeCompleted && elapsedSeconds > 0) {
      bestTime =
          bestTime == null ? elapsedSeconds : min(bestTime, elapsedSeconds);
    }

    final newBest = isNewBest(
      type: type,
      elapsedSeconds: elapsedSeconds,
      routeCompleted: routeCompleted,
      currentBestSeconds: item.bestTimeSeconds,
    );

    final db = await database;
    await db.update(
      'library_items',
      {
        'completion_count': item.completionCount + 1,
        'best_time_seconds': bestTime,
        if (newBest && prTrace != null) 'pr_trace': prTrace,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Revert a [recordCompletion] (post-workout Discard after the session was
  /// already saved by an export): restore the pre-run count, best time and
  /// ghost trace.
  static Future<void> restoreCompletion({
    required String fileName,
    required int completionCount,
    required int? bestTimeSeconds,
    String? prTrace,
  }) async {
    final item = await getLibraryItemByName(fileName);
    if (item == null || item.id == null) return;

    final db = await database;
    await db.update(
      'library_items',
      {
        'completion_count': completionCount,
        'best_time_seconds': bestTimeSeconds,
        'pr_trace': prTrace,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // ── Workout Sessions ──

  static Future<int> insertSession(WorkoutSession session) async {
    final db = await database;
    return db.insert('workout_sessions', session.toMap());
  }

  static Future<List<WorkoutSession>> getAllSessions() async {
    final db = await database;
    final maps = await db.query(
      'workout_sessions',
      orderBy: 'date DESC',
    );
    final sessions = maps.map(WorkoutSession.fromMap).toList();

    // Back-fill rows saved before display_name existed: look the name up in
    // the library by file name, else fall back to a prettified file name.
    final missing = sessions
        .where((s) => s.displayName == null || s.displayName!.isEmpty)
        .map((s) => s.fileName)
        .toSet();
    if (missing.isEmpty) return sessions;

    final libraryNames = await _libraryDisplayNames(missing);
    return sessions.map((s) {
      if (s.displayName != null && s.displayName!.isNotEmpty) return s;
      return s.copyWith(
        displayName: libraryNames[s.fileName] ??
            WorkoutSession.prettifyFileName(s.fileName),
      );
    }).toList();
  }

  /// Map of file name → library display name, for the given file names.
  static Future<Map<String, String>> _libraryDisplayNames(
      Set<String> fileNames) async {
    if (fileNames.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(fileNames.length, '?').join(', ');
    final rows = await db.query(
      'library_items',
      columns: ['name', 'metadata_json'],
      where: 'name IN ($placeholders)',
      whereArgs: fileNames.toList(),
    );

    final result = <String, String>{};
    for (final row in rows) {
      final name = displayNameFromMetadata(row['metadata_json'] as String?);
      if (name != null) result[row['name'] as String] = name;
    }
    return result;
  }

  /// Pull the display name out of a cached library metadata blob.
  static String? displayNameFromMetadata(String? metadataJson) {
    if (metadataJson == null || metadataJson.isEmpty) return null;
    try {
      final meta = jsonDecode(metadataJson);
      if (meta is Map && meta['name'] != null) {
        final name = meta['name'].toString();
        return name.isEmpty ? null : name;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
