#!/usr/bin/env bash
# Build every distributable artefact for مُنتَلا.
#
#   ./tools/build_all.sh                     # web + linux + android
#   ./tools/build_all.sh --no-sync --no-pub  # use the current local material
#   ./tools/build_all.sh --check-only        # dataset gate, no build
#   ./tools/build_all.sh web linux           # pick targets explicitly
#
# Flags:
#   --no-sync              skip refreshing the bundled datasets
#   --no-pub               skip `flutter pub get` and build with --no-pub
#   --allow-debug-signing  package Android artefacts without key.properties
#   --check-only           verify datasets (24h freshness + source drift),
#                          run the dataset test, then exit without building
#
# Artefacts land in dist/ (and dist/android for the signed AAB + APKs) together
# with a SHA256SUMS file. Android output is refused unless it is signed with the
# release upload key, see docs/RELEASING.md.
#
# Environment notes
# -----------------
# This repository was developed on a network where dl.google.com,
# storage.googleapis.com and repo.maven.apache.org are unreachable. The build
# therefore relies on:
#   PUB_HOSTED_URL=https://pub.flutter-io.cn
#   FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
#   the Aliyun Maven mirrors wired into android/settings.gradle.kts
# and on COMPOSE mirrors of the Android SDK components in $ANDROID_HOME. See
# docs/BUILD.md for the full setup. (CI runners need none of these mirrors.)
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$APP_DIR/dist"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SYNC=1
PUB=1
CHECK_ONLY=0
ALLOW_DEBUG_SIGNING=0
TARGETS=()
for arg in "$@"; do
  case "$arg" in
    --no-sync) SYNC=0 ;;
    --no-pub) PUB=0 ;;
    --check-only) CHECK_ONLY=1 ;;
    --allow-debug-signing) ALLOW_DEBUG_SIGNING=1 ;;
    -h|--help) usage; exit 0 ;;
    web|linux|android|windows) TARGETS+=("$arg") ;;
    *) die "unknown argument '$arg' (see --help)" ;;
  esac
done
[[ ${#TARGETS[@]} -gt 0 ]] || TARGETS=(web linux android)

command -v flutter >/dev/null || die "flutter not on PATH"

VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$APP_DIR/pubspec.yaml" | head -1)"
[[ -n "$VERSION" ]] || die "could not read version from pubspec.yaml"

PUB_ARG=""
[[ $PUB -eq 0 ]] && PUB_ARG="--no-pub"

mkdir -p "$DIST"

# ------------------------------------------------------------ release sanity
log "Checking version, changelog and tag consistency"
( cd "$APP_DIR" && python3 tools/release.py check )

if [[ $CHECK_ONLY -eq 1 ]]; then
  log "Checking bundled datasets (drift + 24h freshness), no build"
  ( cd "$APP_DIR" && python3 tools/sync_app_assets.py --check ) || \
    die "dataset freshness check failed — run tools/sync_app_assets.py"
  if [[ $PUB -eq 1 ]]; then
    ( cd "$APP_DIR" && flutter pub get )
  fi
  ( cd "$APP_DIR" && flutter test test/dataset_integration_test.dart $PUB_ARG )
  log "Dataset check passed"
  exit 0
fi

if [[ $SYNC -eq 1 ]]; then
  log "Syncing bundled seed datasets from the engine repo"
  ( cd "$APP_DIR" && python3 tools/sync_app_assets.py ) || die "dataset sync failed"
else
  log "Skipping dataset sync (--no-sync)"
fi

if [[ $PUB -eq 1 ]]; then
  log "Fetching packages"
  ( cd "$APP_DIR" && flutter pub get )
fi

log "Analyzing and testing"
( cd "$APP_DIR" && flutter analyze $PUB_ARG )
( cd "$APP_DIR" && flutter test $PUB_ARG )

# ------------------------------------------------------------------ helpers
signing_ready() { [[ -f "$APP_DIR/android/key.properties" ]]; }
apksigner() {
  local tool
  tool="$(find "$SDK_ROOT/build-tools" -maxdepth 2 -name apksigner -type f 2>/dev/null \
    | sort -V | tail -1)"
  [[ -n "$tool" ]] || die "apksigner not found under $SDK_ROOT/build-tools"
  printf '%s' "$tool"
}
verify_android() {
  local apk="$1" aab="$2" signer
  signer="$(apksigner)"
  "$signer" verify --print-certs "$apk" | grep -q "CN=Montala" \
    || die "APK is not signed with the Montala upload key: $apk"
  keytool -printcert -jarfile "$aab" 2>/dev/null | grep -q "CN=Montala" \
    || die "AAB is not signed with the Montala upload key: $aab"
  log "Android signatures verified (upload key: CN=Montala)"
}

# ------------------------------------------------------------------- targets
for target in "${TARGETS[@]}"; do
  case "$target" in
    web)
      log "Building web"
      ( cd "$APP_DIR" && flutter build web --release $PUB_ARG )
      rm -rf "$DIST/web"
      cp -r "$APP_DIR/build/web" "$DIST/web"
      # The wasm SQLite files are only needed by the old backend; the web build
      # now keeps prices in memory. Drop them so they are not shipped.
      rm -f "$DIST/web/sqlite3.wasm" "$DIST/web/sqflite_sw.js"
      python3 "$APP_DIR/tools/make_zip.py" \
        "$DIST/Montala-$VERSION-web.zip" "$DIST/web" web
      echo "  -> $DIST/Montala-$VERSION-web.zip"
      ;;

    linux)
      log "Building Linux"
      ( cd "$APP_DIR" && flutter build linux --release $PUB_ARG )
      rm -rf "$DIST/linux"
      cp -r "$APP_DIR/build/linux/x64/release/bundle" "$DIST/linux"
      cp "$APP_DIR/packaging/linux/montala.desktop" "$DIST/linux/"
      ( cd "$DIST" && tar czf "Montala-$VERSION-linux-x64.tar.gz" linux )
      echo "  -> $DIST/Montala-$VERSION-linux-x64.tar.gz"
      if [[ -x "$APP_DIR/packaging/linux/build_appimage.sh" ]]; then
        log "Building AppImage"
        ( cd "$APP_DIR" && VERSION="$VERSION" ./packaging/linux/build_appimage.sh ) || \
          echo "  (AppImage step skipped — appimagetool unavailable)"
        rm -rf "$DIST/Montala.AppDir"
      fi
      ;;

    android)
      log "Building signed Android AAB and APKs"
      if ! signing_ready && [[ $ALLOW_DEBUG_SIGNING -eq 0 ]]; then
        die "android/key.properties is missing — refusing to package a store build.
     See docs/RELEASING.md, or pass --allow-debug-signing for a local test build."
      fi
      ( cd "$APP_DIR" && flutter build appbundle --release $PUB_ARG )
      ( cd "$APP_DIR" && flutter build apk --release --split-per-abi $PUB_ARG )

      rm -rf "$DIST/android"
      mkdir -p "$DIST/android"
      cp "$APP_DIR/build/app/outputs/bundle/release/app-release.aab" \
        "$DIST/android/Montala-$VERSION.aab"
      for abi in arm64-v8a armeabi-v7a x86_64; do
        src="$APP_DIR/build/app/outputs/flutter-apk/app-$abi-release.apk"
        [[ -f "$src" ]] || continue
        cp "$src" "$DIST/android/Montala-$VERSION-$abi.apk"
      done

      if signing_ready; then
        verify_android "$DIST/android/Montala-$VERSION-arm64-v8a.apk" \
          "$DIST/android/Montala-$VERSION.aab"
      else
        echo "  (WARNING: debug-signed artefacts in dist/android)"
      fi
      for f in "$DIST"/android/Montala-"$VERSION"*; do echo "  -> $f"; done
      ;;

    windows)
      log "Building Windows"
      [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OS" == "Windows_NT" ]] || \
        die "Windows builds must run on Windows"
      ( cd "$APP_DIR" && flutter build windows --release $PUB_ARG )
      if command -v iscc >/dev/null; then
        ( cd "$APP_DIR" && iscc /DAppVersion="$VERSION" packaging/windows/montala.iss )
        echo "  -> $DIST/Montala-$VERSION-windows-x64-setup.exe"
      else
        echo "  (Inno Setup 'iscc' not found — zipping the Release folder instead)"
        python3 "$APP_DIR/tools/make_zip.py" \
          "$DIST/Montala-$VERSION-windows-x64.zip" \
          "$APP_DIR/build/windows/x64/runner/Release" Montala
      fi
      ;;

    *)
      die "unknown target '$target' (expected: web linux android windows)"
      ;;
  esac
done

# --------------------------------------------------------------- checksums
log "Writing SHA256SUMS"
(
  cd "$DIST"
  for f in \
    "Montala-$VERSION-web.zip" \
    "Montala-$VERSION-linux-x64.tar.gz" \
    "Montala-$VERSION-x86_64.AppImage" \
    "android/Montala-$VERSION.aab" \
    "android/Montala-$VERSION-arm64-v8a.apk" \
    "android/Montala-$VERSION-armeabi-v7a.apk" \
    "android/Montala-$VERSION-x86_64.apk" \
    "Montala-$VERSION-windows-x64-setup.exe" \
    "Montala-$VERSION-windows-x64.zip"; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done | while IFS= read -r f; do sha256sum "$f"; done > SHA256SUMS
  cat SHA256SUMS
)

log "Done — artefacts for v$VERSION in $DIST"
ls -lh "$DIST" 2>/dev/null || true
