/// App-wide dependencies handed down through an InheritedWidget.
library;

import 'package:flutter/material.dart';

import '../core/calc/calculator.dart';
import '../core/settings/settings.dart';

class AppScope extends InheritedWidget {
  final Settings settings;
  final Calculator calculator;
  final Future<void> Function() refreshData;

  const AppScope({
    super.key,
    required this.settings,
    required this.calculator,
    required this.refreshData,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing from the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings || calculator != oldWidget.calculator;
}
