#!/usr/bin/env bash
# Build every distributable artefact for مُنتَلا.
#
#   ./tools/build_all.sh            # web + linux (+ android if the SDK is set)
#   ./tools/build_all.sh web linux  # pick targets explicitly
#
# Artifacts land in app/dist/. Android APKs land in
# app/build/app/outputs/flutter-apk/ as well.
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
REPO_DIR="$(cd "$APP_DIR/.." && pwd)"
DIST="$APP_DIR/dist"
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$APP_DIR/pubspec.yaml" | head -1)"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter not on PATH"

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(web linux android)
fi

mkdir -p "$DIST"

# ---------------------------------------------------------------- preprocessing
# Pull the freshest datasets from the tgju-asset-history engine repo (local
# checkout when present, otherwise its raw main branch), sanity-checked.
log "Syncing bundled seed datasets from the engine repo"
( cd "$APP_DIR" && python3 tools/sync_app_assets.py ) || die "dataset sync failed"

log "Fetching packages"
( cd "$APP_DIR" && flutter pub get )

log "Analyzing and testing"
( cd "$APP_DIR" && flutter analyze )
( cd "$APP_DIR" && flutter test )

for target in "${TARGETS[@]}"; do
  case "$target" in
    web)
      log "Building web"
      ( cd "$APP_DIR" && flutter build web --release )
      rm -rf "$DIST/web"
      cp -r "$APP_DIR/build/web" "$DIST/web"
      # The wasm SQLite files are only needed by the old backend; the web build
      # now keeps prices in memory. Drop them so they are not shipped.
      rm -f "$DIST/web/sqlite3.wasm" "$DIST/web/sqflite_sw.js"
      python3 "$APP_DIR/tools/make_zip.py" "$DIST/Montala-$VERSION-web.zip" "$DIST/web" web
      echo "  -> $DIST/Montala-$VERSION-web.zip"
      ;;

    linux)
      log "Building Linux"
      ( cd "$APP_DIR" && flutter build linux --release )
      rm -rf "$DIST/linux"
      cp -r "$APP_DIR/build/linux/x64/release/bundle" "$DIST/linux"
      cp "$APP_DIR/packaging/linux/montala.desktop" "$DIST/linux/"
      ( cd "$DIST" && tar czf "Montala-$VERSION-linux-x64.tar.gz" linux )
      echo "  -> $DIST/Montala-$VERSION-linux-x64.tar.gz"
      if [[ -x "$APP_DIR/packaging/linux/build_appimage.sh" ]]; then
        log "Building AppImage"
        ( cd "$APP_DIR" && VERSION="$VERSION" ./packaging/linux/build_appimage.sh ) || \
          echo "  (AppImage step skipped — appimagetool unavailable)"
      fi
      ;;

    android)
      log "Building Android APKs (per ABI)"
      [[ -n "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]] || \
        echo "  (ANDROID_HOME not set — relying on android/local.properties)"
      ( cd "$APP_DIR" && flutter build apk --release --split-per-abi )
      mkdir -p "$DIST/android"
      cp "$APP_DIR"/build/app/outputs/flutter-apk/*-release.apk "$DIST/android/" 2>/dev/null || true
      for f in "$DIST"/android/*-release.apk; do
        [[ -e "$f" ]] && echo "  -> $f"
      done
      ;;

    windows)
      log "Building Windows"
      [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OS" == "Windows_NT" ]] || \
        die "Windows builds must run on Windows"
      ( cd "$APP_DIR" && flutter build windows --release )
      if command -v iscc >/dev/null; then
        ( cd "$APP_DIR" && iscc packaging/windows/montala.iss )
        echo "  -> $DIST/Montala-$VERSION-windows-x64-setup.exe"
      else
        echo "  (Inno Setup 'iscc' not found — zip the Release folder instead)"
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

log "Done — artefacts in $DIST"
ls -lh "$DIST" 2>/dev/null || true
