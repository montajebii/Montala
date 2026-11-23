/// Web portfolio store: JSON documents in SharedPreferences.
///
/// The web price store is session-only by design, but user-entered trades and
/// the generated value history are irreplaceable, so they live in
/// localStorage instead.
///
/// The v1 → v2 migration is write-then-verify: the new document is written,
/// read back and compared with the parsed v1 rows; only then is the old key
/// removed. If anything fails, v1 stays in place and the in-memory list is
/// still returned, so no user data is ever dropped.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portfolio_models.dart';
import 'portfolio_store.dart';

class PrefsPortfolioStore implements PortfolioStore {
  static const keyV1 = 'portfolio_transactions_v1';
  static const keyV2 = 'portfolio_transactions_v2';
  static const snapshotsKeyV2 = 'portfolio_snapshots_v2';

  List<PortfolioTx>? _cache;
  List<PortfolioSnapshot>? _snapshotCache;

  Future<List<PortfolioTx>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final v2 = prefs.getString(keyV2);
    if (v2 != null && v2.isNotEmpty) {
      try {
        final list = _decodeTxs(v2);
        _sort(list);
        _cache = list;
        return list;
      } catch (error) {
        debugPrint('portfolio v2 document is unreadable: $error');
      }
    }

    final v1 = prefs.getString(keyV1);
    if (v1 == null || v1.isEmpty) {
      _cache = [];
      return _cache!;
    }

    final list = _decodeTxs(v1);
    _sort(list);
    _cache = list;
    await _verifyAndMigrate(prefs, list);
    return list;
  }

  List<PortfolioTx> _decodeTxs(String raw) => [
        for (final entry in jsonDecode(raw) as List)
          PortfolioTx.fromJson(entry as Map<String, dynamic>),
      ];

  Future<void> _verifyAndMigrate(
    SharedPreferences prefs,
    List<PortfolioTx> list,
  ) async {
    final json = jsonEncode([for (final tx in list) tx.toJson()]);
    final wrote = await prefs.setString(keyV2, json);
    if (!wrote) return;
    final readBack = prefs.getString(keyV2);
    if (readBack == null) return;
    final List<PortfolioTx> parsed;
    try {
      parsed = _decodeTxs(readBack);
    } catch (error) {
      debugPrint('portfolio migration verification failed: $error');
      return;
    }
    if (parsed.length != list.length) return;
    for (var i = 0; i < list.length; i++) {
      if (parsed[i].id != list[i].id ||
          parsed[i].timestamp != list[i].timestamp ||
          parsed[i].assetId != list[i].assetId ||
          parsed[i].type != list[i].type ||
          parsed[i].units != list[i].units ||
          parsed[i].unitPriceToman != list[i].unitPriceToman ||
          parsed[i].totalToman != list[i].totalToman ||
          parsed[i].incomplete != list[i].incomplete) {
        return;
      }
    }
    // Verification passed: the v2 document is the source of truth now.
    await prefs.remove(keyV1);
  }

  void _sort(List<PortfolioTx> list) {
    list.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) return byTime;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      [for (final tx in _cache ?? const <PortfolioTx>[]) tx.toJson()],
    );
    if (!await prefs.setString(keyV2, json)) {
      throw StateError('could not persist the portfolio transaction log');
    }
  }

  int _nextId() =>
      (_cache ?? const <PortfolioTx>[]).fold(0, (m, t) => math.max(m, t.id ?? 0)) + 1;

  @override
  Future<List<PortfolioTx>> transactions() => _load();

  @override
  Future<PortfolioTx> addTransaction(PortfolioTx tx) async {
    final list = await _load();
    final saved = tx.copyWith(id: _nextId());
    list.add(saved);
    _sort(list);
    await _persist();
    return saved;
  }

  @override
  Future<void> updateTransaction(PortfolioTx tx) async {
    final list = await _load();
    final i = list.indexWhere((t) => t.id == tx.id);
    if (i == -1) return;
    list[i] = tx;
    _sort(list);
    await _persist();
  }

  @override
  Future<void> deleteTransaction(int id) async {
    final list = await _load();
    list.removeWhere((t) => t.id == id);
    await _persist();
  }

  @override
  Future<void> replaceAll(List<PortfolioTx> txs) async {
    _cache = [
      for (var i = 0; i < txs.length; i++) txs[i].copyWith(id: i + 1),
    ];
    _sort(_cache!);
    await _persist();
  }

  Future<List<PortfolioSnapshot>> _loadSnapshots() async {
    final cached = _snapshotCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(snapshotsKeyV2);
    if (raw == null || raw.isEmpty) {
      _snapshotCache = [];
      return _snapshotCache!;
    }
    List<PortfolioSnapshot> list;
    try {
      list = [
        for (final entry in jsonDecode(raw) as List)
          PortfolioSnapshot.fromJson(entry as Map<String, dynamic>),
      ];
    } catch (error) {
      debugPrint('portfolio snapshot document is unreadable: $error');
      list = [];
    }
    list.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) return byTime;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    _snapshotCache = list;
    return list;
  }

  Future<void> _persistSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      [for (final s in _snapshotCache ?? const <PortfolioSnapshot>[]) s.toJson()],
    );
    if (!await prefs.setString(snapshotsKeyV2, json)) {
      throw StateError('could not persist the portfolio value history');
    }
  }

  @override
  Future<List<PortfolioSnapshot>> snapshots() => _loadSnapshots();

  @override
  Future<PortfolioSnapshot> addSnapshot(PortfolioSnapshot snapshot) async {
    final list = await _loadSnapshots();
    final id = _snapshotCache!
        .fold(0, (m, s) => math.max(m, s.id ?? 0)) + 1;
    final saved = snapshot.copyWith(id: id);
    list.add(saved);
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _persistSnapshots();
    return saved;
  }

  @override
  Future<void> updateSnapshotTimestamp(int id, DateTime timestamp) async {
    final list = await _loadSnapshots();
    final i = list.indexWhere((s) => s.id == id);
    if (i == -1) return;
    list[i] = list[i].copyWith(timestamp: timestamp);
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _persistSnapshots();
  }

  @override
  Future<void> replaceAllSnapshots(List<PortfolioSnapshot> snapshots) async {
    _snapshotCache = [
      for (var i = 0; i < snapshots.length; i++)
        snapshots[i].copyWith(id: i + 1),
    ];
    _snapshotCache!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _persistSnapshots();
  }

  @override
  Future<void> close() async {
    _cache = null;
    _snapshotCache = null;
  }
}

/// Factory used by the conditional import in `portfolio_store.dart`.
PortfolioStore createPlatformPortfolioStore() => PrefsPortfolioStore();
