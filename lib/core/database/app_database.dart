import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// ── Tables ──────────────────────────────────────────────────────
// Add your Drift table classes here. Example:
//
// class Credentials extends Table {
//   IntColumn get id => integer().autoIncrement()();
//   TextColumn get title => text().withLength(min: 1, max: 128)();
//   TextColumn get encryptedPayload => text()();
//   DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
// }

// ── Database ────────────────────────────────────────────────────
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'lockbox.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
