import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lockbox/core/database/app_database.dart';

/// Single shared instance of the Drift database.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
