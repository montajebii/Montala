/// Guards the release invariants that are easy to get wrong by hand:
/// pubspec version, in-app version constants and the changelog must agree.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/app_version.dart';

String _read(String path) => File(path).readAsStringSync();

String _persian(String ascii) {
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  final out = StringBuffer();
  for (final ch in ascii.codeUnits) {
    if (ch >= 0x30 && ch <= 0x39) {
      out.write(digits[ch - 0x30]);
    } else {
      out.writeCharCode(ch);
    }
  }
  return out.toString().replaceAll('.', '٫');
}

void main() {
  final pubspec = _read('pubspec.yaml');
  final versionMatch = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);

  test('pubspec declares a semantic version with a build number', () {
    expect(versionMatch, isNotNull,
        reason: 'pubspec.yaml must declare version: X.Y.Z+N');
    expect(int.parse(versionMatch!.group(2)!), greaterThan(0),
        reason: 'the +N build number is the Android versionCode and must be set');
  });

  test('in-app version constants match pubspec.yaml', () {
    expect(kAppVersion, versionMatch!.group(1));
    expect(kAppVersionFa, _persian(kAppVersion));
  });

  test('CHANGELOG.md has a dated section for the current version', () {
    final changelog = _read('CHANGELOG.md');
    final heading = RegExp(
      '^## \\[${RegExp.escape(kAppVersion)}\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\$',
      multiLine: true,
    );
    expect(heading.hasMatch(changelog), isTrue,
        reason: 'add a "## [$kAppVersion] - YYYY-MM-DD" section; '
            'tools/release.py prepare writes it for you');
  });
}
