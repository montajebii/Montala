/// Resolves where the SQLite file lives, per platform.
///
/// On native platforms sqflite exposes a per-app databases directory. On the web
/// there is no filesystem at all: the wasm factory stores databases in IndexedDB
/// and `getDatabasesPath()` is not implemented, so the database is opened by
/// bare name.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The value passed to [openDatabase] for [dbName].
Future<String> resolveDatabasePath(String dbName) async {
  final dir = await getDatabasesPath();
  return p.join(dir, dbName);
}
