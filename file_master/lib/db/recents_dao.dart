import 'package:sqflite/sqflite.dart';

import '../models/recent_file.dart';

class RecentsDao {
  RecentsDao(this._db);

  final Database _db;

  static const int limit = 50;

  static const String table = 'recents';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        format TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        lastOpened INTEGER NOT NULL
      )
    ''');
  }

  Future<List<RecentFile>> getAll() async {
    final rows = await _db.query(
      table,
      orderBy: 'lastOpened DESC',
      limit: limit,
    );
    return rows.map(RecentFile.fromMap).toList();
  }

  Future<void> upsert(RecentFile file) async {
    await _db.insert(
      table,
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _prune();
  }

  Future<void> remove(String path) async {
    await _db.delete(table, where: 'path = ?', whereArgs: [path]);
  }

  Future<void> clear() async {
    await _db.delete(table);
  }

  Future<void> _prune() async {
    final ids = await _db.rawQuery(
      'SELECT id FROM $table ORDER BY lastOpened DESC LIMIT ? OFFSET ?',
      [limit, limit],
    );
    for (final row in ids) {
      await _db.delete(table, where: 'id = ?', whereArgs: [row['id']]);
    }
  }
}
