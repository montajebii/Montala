# Changelog

All notable changes to مُنتَلا / Montala are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release rules (see `docs/RELEASING.md`):

- Entries are written under `## [Unreleased]` while work happens and promoted
  by `python3 tools/release.py prepare --version X.Y.Z`.
- Every released version has a matching annotated `vX.Y.Z` git tag, and the
  tag must equal `version:` in `pubspec.yaml`.
- The `+N` build number in `pubspec.yaml` is the Android `versionCode`. It must
  increase for every published build, even when only the build number changes.
- Entries describe changes users can observe, not refactors. Anything omitted
  from here must not change behaviour.

## [Unreleased]

### Changed

- Bundled price history for the half-coin, quarter-coin and full-coin series
  extended through 2026-11-12 by the automated data sync.

## [1.2.0] - 2026-11-16

### Added

- Toolbox home: the app opens on an icon grid where each of the four tools is
  one tap away.
- Live price board: 13 assets (coins, 18k/24k gold, mesghal, world ounce,
  melted gold, silver) with side-by-side quotes from estjt.ir and tgju.org,
  change percentages, 60-second auto-refresh, pull-to-refresh and stale-data
  markers. The web build shows tgju only (estjt has no CORS headers).
- Personal net worth: record buys/sells with backdated dates and custom prices;
  the app derives current value, full value history, allocation, open and
  realised P&L, moving average, 30-day volatility and outlier markers. Data is
  stored on-device (SQLite natively, localStorage on web) and can be imported
  or exported as CSV.
- An explanation sheet (ⓘ) on every tool screen.
- Live board values now carry their unit (تومان/ریال/دلار) and follow the
  Toman/Rial display setting.
- CSV import accepts m0ntIsRich asset ids (`shemsh24`, `shemsh18`, `geram24`,
  `geram18`) and rejects unknown symbols with a line-specific error.
- New app icon across Android (including adaptive icons), Windows, web and
  maskable PWA icons; the web splash screen uses it too.
- Jalali date pickers gain double-arrow year jumps.

### Changed

- Android application id, namespace and Kotlin package are now
  `ir.m0nt.montala`; the Linux application id and Windows metadata follow the
  same name. Builds are a separate installation from versions published under
  `ir.montala.montala`, and app-private data does not carry over.
- Date pickers no longer offer dates before the underlying price data starts:
  profit/loss and basket valuation use the earliest date across all series,
  while the net-worth transaction form uses the earliest date of the selected
  asset.
- The About screen documents all four tools; its version label is generated
  from the build instead of being hard-coded.
- The valuation result scrolls into view and briefly highlights its border
  after calculating.
- The launcher's profit/loss icon is mirrored so it reads naturally in RTL.
- Bundled price history refreshed through 2026-11-14.

### Fixed

- estjt live quotes survive the site moving its board from a `<div>` to a
  `<main class="tt-tv__prices">`, and recognise both «طلا» and «طلای»
  spellings used by the site over time.
- Unknown asset names in an imported CSV no longer produce unusable
  transactions; the importer reports the offending line instead.

### Build

- Android release builds are signed with a dedicated 4096-bit upload key;
  `flutter build appbundle` now produces the signed AAB for store delivery.
- Introduced semantic version management, `CHANGELOG.md`, a release script and
  a version/tag/changelog consistency check used by CI.

## [1.0.1] - 2026-10-30

### Fixed

- GitHub release publishing failed because the publish job has no checkout;
  `gh release create` is now given the repository explicitly. No application
  changes — the app binary remained 1.0.0+1.

## [1.0.0] - 2026-10-30

### Added

- Hypothetical profit/loss: enter an amount and two dates and compare the
  outcome across eight Iranian assets, with ranking, growth charts and a
  40-day candle sheet per symbol.
- Basket valuation on a chosen date — built for mahr valuation — with a
  copyable result.
- Offline-first price history bundled from tgju.org, refreshable in-app, with
  Jalali dates, Persian numerals, Toman/Rial display and Open/Close basis
  settings.
- Flutter application for Android, Windows, Linux and the web (RTL,
  Vazirmatn).

[Unreleased]: https://github.com/montajebii/Montala/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/montajebii/Montala/compare/v1.0.1...v1.2.0
[1.0.1]: https://github.com/montajebii/Montala/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/montajebii/Montala/releases/tag/v1.0.0
