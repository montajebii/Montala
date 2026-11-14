/// Web portfolio store: a JSON document in SharedPreferences.
///
/// The web price store is session-only by design, but user-entered trades are
/// irreplaceable data, so they live in localStorage instead.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'portfolio_models.dart';
import 'portfolio_store.dart';

class PrefsPortfolioStore implements PortfolioStore {
  static const _key = 'portfolio_transactions_v1';
  List<PortfolioTx>? _cache;

  Future<List<PortfolioTx>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return _cache!;
    }
    final list = (jsonDecode(raw) as List)
        .map((e) => PortfolioTx.fromJson(e as Map<String, dynamic>))
        .toList();
    _sort(list);
    _cache = list;
    return list;
  }

  void _sort(List<PortfolioTx> list) {
    list.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      [for (final tx in _cache ?? const <PortfolioTx>[]) tx.toJson()],
    );
    await prefs.setString(_key, json);
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

  @override
  Future<void> close() async {
    _cache = null;
  }
}

/// Factory used by the conditional import in `portfolio_store.dart`.
PortfolioStore createPlatformPortfolioStore() => PrefsPortfolioStore();
