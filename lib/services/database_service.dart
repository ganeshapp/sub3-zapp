import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/workout_session.dart';

class DatabaseService {
  static Database? _db;

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
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
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
    return maps.map(WorkoutSession.fromMap).toList();
  }

  static Future<void> markUploadedToStrava(int id) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      {'is_uploaded_to_strava': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
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
