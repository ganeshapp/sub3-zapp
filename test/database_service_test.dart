import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sub3/models/library_item.dart';
import 'package:sub3/services/database_service.dart';

/// Column names of [table] in [db].
Future<Set<String>> columnsOf(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toSet();
}

/// The schema exactly as version 2 shipped it (v1.2.1 and earlier).
Future<void> createV2Schema(Database db) async {
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
      preview_points TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE workout_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      file_name TEXT NOT NULL,
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('schema v3', () {
    test('fresh install has display_name and pr_trace', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DatabaseService.schemaVersion,
          onCreate: DatabaseService.createSchema,
          onUpgrade: DatabaseService.migrate,
        ),
      );
      addTearDown(db.close);

      expect(await columnsOf(db, 'workout_sessions'), contains('display_name'));
      expect(await columnsOf(db, 'library_items'), contains('pr_trace'));
      // The Strava column stays in place, unused.
      expect(await columnsOf(db, 'workout_sessions'),
          contains('is_uploaded_to_strava'));
    });

    test('upgrade from v2 adds the columns and keeps existing rows', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await createV2Schema(db);
      await db.insert('library_items', {
        'name': 'route1152412195.gpx',
        'type': 'gpx',
        'completion_count': 4,
        'best_time_seconds': 2400,
      });
      await db.insert('workout_sessions', {
        'date': DateTime(2026, 2, 21).toIso8601String(),
        'file_name': 'route1152412195.gpx',
        'type': 'gpx',
        'duration_seconds': 2400,
        'distance_km': 7.8,
      });

      await DatabaseService.migrate(db, 2, DatabaseService.schemaVersion);

      expect(await columnsOf(db, 'workout_sessions'), contains('display_name'));
      expect(await columnsOf(db, 'library_items'), contains('pr_trace'));

      final items = await db.query('library_items');
      expect(items.single['completion_count'], 4);
      expect(items.single['best_time_seconds'], 2400);
      expect(items.single['pr_trace'], isNull);

      final sessions = await db.query('workout_sessions');
      expect(sessions.single['file_name'], 'route1152412195.gpx');
      expect(sessions.single['display_name'], isNull);
    });

    test('upgrade from v1 runs both steps', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await db.execute('''
        CREATE TABLE library_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          type TEXT NOT NULL,
          file_path TEXT,
          completion_count INTEGER NOT NULL DEFAULT 0,
          best_time_seconds INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE workout_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          file_name TEXT NOT NULL,
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

      await DatabaseService.migrate(db, 1, DatabaseService.schemaVersion);

      expect(
        await columnsOf(db, 'library_items'),
        containsAll(['sha', 'metadata_json', 'preview_points', 'pr_trace']),
      );
      expect(await columnsOf(db, 'workout_sessions'), contains('display_name'));
    });
  });

  group('New best rule (what earns the PR and its ghost)', () {
    test('first finished route sets the best time', () {
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 2400,
          routeCompleted: true,
          currentBestSeconds: null,
        ),
        true,
      );
    });

    test('only a faster finish takes the PR', () {
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 2399,
          routeCompleted: true,
          currentBestSeconds: 2400,
        ),
        true,
      );
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 2400,
          routeCompleted: true,
          currentBestSeconds: 2400,
        ),
        false,
      );
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 2500,
          routeCompleted: true,
          currentBestSeconds: 2400,
        ),
        false,
      );
    });

    test('a route the runner quit early never sets a best time', () {
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 300,
          routeCompleted: false,
          currentBestSeconds: 2400,
        ),
        false,
      );
    });

    test('structured workouts have no best time at all', () {
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.workout,
          elapsedSeconds: 1800,
          routeCompleted: true,
          currentBestSeconds: null,
        ),
        false,
      );
    });

    test('a zero-length run is ignored', () {
      expect(
        DatabaseService.isNewBest(
          type: LibraryItemType.gpx,
          elapsedSeconds: 0,
          routeCompleted: true,
          currentBestSeconds: null,
        ),
        false,
      );
    });
  });

  group('displayNameFromMetadata', () {
    test('reads the cached library name', () {
      expect(
        DatabaseService.displayNameFromMetadata(
            '{"_v":4,"name":"Hillview (Rail Corridor) to Holland V"}'),
        'Hillview (Rail Corridor) to Holland V',
      );
    });

    test('returns null for missing, empty or broken metadata', () {
      expect(DatabaseService.displayNameFromMetadata(null), isNull);
      expect(DatabaseService.displayNameFromMetadata(''), isNull);
      expect(DatabaseService.displayNameFromMetadata('{"_v":4}'), isNull);
      expect(DatabaseService.displayNameFromMetadata('{"name":""}'), isNull);
      expect(DatabaseService.displayNameFromMetadata('not json'), isNull);
    });
  });
}
