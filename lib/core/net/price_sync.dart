/// Background price synchronisation at launch.
///
/// The task runs after the first frame, never blocks `runApp`, and reports
/// its progress through a [ChangeNotifier] so a thin strip can appear while
/// it works. A failure is not an app failure: the bundled archive stays in
/// place and the tools remain usable.
library;

import 'package:flutter/foundation.dart';

import 'updater.dart';

enum PriceSyncPhase { idle, running, success, failed }

@immutable
class PriceSyncState {
  final PriceSyncPhase phase;
  final DateTime? finishedAt;
  final List<SymbolUpdateResult> results;

  const PriceSyncState({
    this.phase = PriceSyncPhase.idle,
    this.finishedAt,
    this.results = const [],
  });

  bool get running => phase == PriceSyncPhase.running;

  /// True when at least one symbol could not be refreshed.
  bool get partial => results.any((r) => !r.ok);

  int get updatedSymbols => results.where((r) => r.ok).length;
}

class PriceSyncController extends ChangeNotifier {
  final Future<List<SymbolUpdateResult>> Function() _run;

  PriceSyncController({required Future<List<SymbolUpdateResult>> Function() run})
      : _run = run;

  PriceSyncState _state = const PriceSyncState();
  bool _started = false;

  PriceSyncState get state => _state;

  /// Starts at most once. Safe to call from a post-frame callback or a test.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _state = const PriceSyncState(phase: PriceSyncPhase.running);
    notifyListeners();
    try {
      final results = await _run();
      _state = PriceSyncState(
        phase: results.any((r) => r.ok)
            ? PriceSyncPhase.success
            : PriceSyncPhase.failed,
        finishedAt: DateTime.now(),
        results: results,
      );
    } catch (error) {
      debugPrint('background price update failed: $error');
      _state = PriceSyncState(
        phase: PriceSyncPhase.failed,
        finishedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  /// Test helper: allows a second [start] in the same controller.
  @visibleForTesting
  void reset() {
    _started = false;
    _state = const PriceSyncState();
    notifyListeners();
  }
}
