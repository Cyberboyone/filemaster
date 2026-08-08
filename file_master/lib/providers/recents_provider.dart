import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../db/recents_dao.dart';
import '../models/recent_file.dart';

final databaseProvider = FutureProvider<Database>((ref) async {
  final dir = await getDatabasesPath();
  final path = p.join(dir, 'file_master.db');
  return openDatabase(
    path,
    version: 1,
    onCreate: (db, version) => RecentsDao.createTable(db),
  );
});

final recentsDaoProvider = FutureProvider<RecentsDao>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return RecentsDao(db);
});

final recentsControllerProvider =
    NotifierProvider<RecentsController, AsyncValue<List<RecentFile>>>(
      RecentsController.new,
    );

class RecentsController extends Notifier<AsyncValue<List<RecentFile>>> {
  @override
  AsyncValue<List<RecentFile>> build() {
    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final dao = await ref.read(recentsDaoProvider.future);
      final files = await dao.getAll();
      state = AsyncValue.data(files);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> recordOpen(RecentFile file) async {
    try {
      final dao = await ref.read(recentsDaoProvider.future);
      await dao.upsert(file);
      await _load();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> remove(String path) async {
    final dao = await ref.read(recentsDaoProvider.future);
    await dao.remove(path);
    await _load();
  }

  Future<void> clear() async {
    final dao = await ref.read(recentsDaoProvider.future);
    await dao.clear();
    await _load();
  }
}
