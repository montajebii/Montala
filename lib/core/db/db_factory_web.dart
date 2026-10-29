/// Web sqflite bootstrap.
///
/// The web build uses the in-memory store (see `memory_store.dart`), so no
/// database factory has to be installed. This file exists so `main.dart` can
/// import one entry point on every platform without touching `dart:io`.
library;

/// No-op on the web: there is no sqflite factory to select.
Future<void> initDatabaseFactoryForPlatform() async {}
