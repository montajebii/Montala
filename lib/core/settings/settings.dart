/// Persistent user preferences (SharedPreferences-backed).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../util/format.dart';

class Settings extends ChangeNotifier {
  static const _kInToman = 'in_toman';
  static const _kBasis = 'price_basis';
  static const _kSplit = 'split_amount';
  static const _kAutoUpdate = 'auto_update';
  static const _kLastUpdate = 'last_update_iso';

  late SharedPreferences _prefs;

  bool _inToman = true;
  PriceBasis _basis = PriceBasis.close;
  bool _splitAmount = false;
  bool _autoUpdate = true;
  DateTime? _lastUpdate;

  bool get inToman => _inToman;
  PriceBasis get basis => _basis;
  bool get splitAmount => _splitAmount;
  bool get autoUpdate => _autoUpdate;
  DateTime? get lastUpdate => _lastUpdate;
  UnitDisplay get unit => _inToman ? UnitDisplay.toman : UnitDisplay.rial;

  /// True when the cached data is older than [maxAge].
  bool isStale({Duration maxAge = const Duration(hours: 12)}) {
    final last = _lastUpdate;
    if (last == null) return true;
    return DateTime.now().difference(last) > maxAge;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _inToman = _prefs.getBool(_kInToman) ?? true;
    _splitAmount = _prefs.getBool(_kSplit) ?? false;
    _autoUpdate = _prefs.getBool(_kAutoUpdate) ?? true;
    final basisName = _prefs.getString(_kBasis);
    _basis = basisName == 'open' ? PriceBasis.open : PriceBasis.close;
    final last = _prefs.getString(_kLastUpdate);
    _lastUpdate = last == null ? null : DateTime.tryParse(last);
    notifyListeners();
  }

  Future<void> setInToman(bool v) async {
    _inToman = v;
    await _prefs.setBool(_kInToman, v);
    notifyListeners();
  }

  Future<void> setBasis(PriceBasis v) async {
    _basis = v;
    await _prefs.setString(_kBasis, v == PriceBasis.open ? 'open' : 'close');
    notifyListeners();
  }

  Future<void> setSplitAmount(bool v) async {
    _splitAmount = v;
    await _prefs.setBool(_kSplit, v);
    notifyListeners();
  }

  Future<void> setAutoUpdate(bool v) async {
    _autoUpdate = v;
    await _prefs.setBool(_kAutoUpdate, v);
    notifyListeners();
  }

  Future<void> setLastUpdate(DateTime v) async {
    _lastUpdate = v;
    await _prefs.setString(_kLastUpdate, v.toIso8601String());
    notifyListeners();
  }
}
