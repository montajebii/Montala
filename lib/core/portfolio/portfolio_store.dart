/// Persistence for portfolio transactions and value snapshots.
///
/// Two backends behind the usual conditional import:
///  * native — a small dedicated SQLite database (`montala_portfolio.db`),
///  * web — JSON documents in SharedPreferences (the price store on the web
///    is deliberately session-only, but user-entered trades must survive
///    reloads).
library;

import 'portfolio_models.dart';
import 'portfolio_store_io.dart'
    if (dart.library.js_interop) 'portfolio_store_web_io.dart' as platform;

/// Port of m0ntIsRich's transaction log + value history, minus the flat files.
abstract class PortfolioStore {
  /// All transactions ordered by timestamp then id, ascending.
  Future<List<PortfolioTx>> transactions();

  /// Inserts [tx], returning it with its assigned id.
  Future<PortfolioTx> addTransaction(PortfolioTx tx);

  Future<void> updateTransaction(PortfolioTx tx);

  Future<void> deleteTransaction(int id);

  /// Replaces the whole table (import path). Ids are reassigned.
  Future<void> replaceAll(List<PortfolioTx> txs);

  /// All value snapshots ordered by timestamp then id, ascending.
  Future<List<PortfolioSnapshot>> snapshots();

  /// Inserts [snapshot], returning it with its assigned id.
  Future<PortfolioSnapshot> addSnapshot(PortfolioSnapshot snapshot);

  /// Moves the last snapshot's timestamp without appending a duplicate row
  /// (used when a launch sees an unchanged total).
  Future<void> updateSnapshotTimestamp(int id, DateTime timestamp);

  /// Replaces the whole snapshot history (import path).
  Future<void> replaceAllSnapshots(List<PortfolioSnapshot> snapshots);

  Future<void> close();
}

/// Factory chosen at compile time by the conditional import above.
PortfolioStore createPortfolioStore() =>
    platform.createPlatformPortfolioStore();
