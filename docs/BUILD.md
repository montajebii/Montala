# Build notes

Everything needed to reproduce the release artefacts from a clean checkout, and
the non-obvious environment constraints this project was developed under.

## Quick start

```bash
# from the repository root
python3 tools/sync_app_assets.py       # pull datasets from the tgju-asset-history engine repo
#   add --remote <url-base> to pull from a published engine repo, or --local <dir>
#   for a local checkout; every file is sanity-checked before it lands in assets/data

flutter pub get
flutter test
./tools/build_all.sh                   # web + linux + android (windows: run on windows)
```

Artifacts land in `app/dist/`:

| File | Target |
|---|---|
| `Montala-<v>-web.zip` | static site (GitHub Pages, any static host) |
| `Montala-<v>-x86_64.AppImage` | Linux, single executable |
| `Montala-<v>-linux-x64.tar.gz` | Linux, plain directory bundle |
| `android/app-*-release.apk` | Android, per ABI |

Windows must be built on Windows (`flutter build windows --release`, then
`iscc packaging\windows\montala.iss`).

## Toolchain versions used

| Tool | Version |
|---|---|
| Flutter | 3.47.8 (stable), Dart 3.13.7 |
| JDK | 21 |
| Gradle | 9.3.1 (Android wrapper) |
| AGP | 9.1.0 |
| Android compileSdk / targetSdk | 36 |
| Android minSdk | 24 (Android 7.0) |

## Network constraints (important)

The development machine cannot reach `dl.google.com`,
`storage.googleapis.com`, `repo.maven.apache.org` or `plugins.gradle.org`
(all return 403 / connection reset). The build is wired to mirrors:

| Purpose | Mirror |
|---|---|
| Dart packages | `PUB_HOSTED_URL=https://pub.flutter-io.cn` |
| Flutter engine / SDK | `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` |
| Maven (Google + Central) | Aliyun, declared in `android/settings.gradle.kts` |
| Flutter Android engine jars | `https://storage.flutter-io.cn/download.flutter.io` declared in `android/build.gradle.kts` |

If you build on an unrestricted network you can drop these, but they are
harmless elsewhere.

### Android SDK components

`compileSdk 36` needs `platforms;android-36` and `build-tools;36.0.0`, which the
SDK manager could not download here. They were mirrored from the installed
35.0.0 tree. On a normal machine just run:

```bash
sdkmanager --install "platforms;android-36" "build-tools;36.0.0"
```

The NDK is **not** required: the app ships no native code of its own. Two
dependency pins avoid accidentally pulling one in — see `pubspec.yaml`:

* `shared_preferences_android: 2.3.0` — later versions depend on `jni`, which
  compiles native code (needs NDK + CMake).
* `sqflite_android: 2.4.0` — 2.4.5 references `Build.VERSION_CODES.BAKLAVA` and
  `Thread.threadId()`, which only exist in a real API 36 `android.jar`.

## Linux desktop requirements

`flutter build linux` needs `cmake`, `ninja` and `clang`. If they are absent and
you have no root access, they can be installed into a prefix:

```bash
python3 -m pip install --user cmake ninja      # works for cmake + ninja
```

Clang is available as a distribution package; extract it to a prefix and put
thin wrappers on `PATH` if root is unavailable.

## Platform architecture

| Platform | Price storage | Notes |
|---|---|---|
| Android | SQLite (sqflite plugin) | seeded from bundled CSVs on first run |
| Windows / Linux | SQLite (sqflite FFI) | `sqfliteFfiInit()` at startup |
| Web | in-memory table | no IndexedDB/SQLite; ~1.4 MB CSV parsed at load |

The web backend is deliberately not SQLite. The wasm route needs an IndexedDB
filesystem shim (`sqlite3.wasm` + a shared worker) that fails opaquely on some
browsers and took the whole app down at startup with
`DatabaseException(getDatabasesPath is null)`. Since the dataset is tiny, the web
build parses the CSVs into memory instead. Consequence: on the web a page reload
re-seeds from the bundled data (updates made in the session are not persisted).

## Regenerating the web SQLite shim

Only needed if you switch the web backend back to SQLite:

```bash
cd app
dart run sqflite_common_ffi_web:setup     # writes web/sqlite3.wasm, web/sqflite_sw.js
```

## Rebuilding the icons

The launcher icons are generated procedurally (teal rounded square with a gold
rising curve) so no binary asset has to be committed:

```bash
cd app
python3 - <<'PY'
# see packaging/README.md for the exact script
PY
```

`build_all.sh` does not regenerate them; they are committed under
`web/icons/`, `android/app/src/main/res/mipmap-*/` and
`windows/runner/resources/app_icon.ico`.
