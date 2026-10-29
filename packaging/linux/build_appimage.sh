#!/usr/bin/env bash
# Build a single-file AppImage for مُنتَلا.
#
# Produces: dist/Montala-<version>-x86_64.AppImage
#
# Requirements (either already present or downloaded into .cache/appimage):
#   * a Linux release bundle  ->  flutter build linux --release
#   * appimagetool            ->  https://github.com/AppImage/AppImageKit
#   * linuxdeploy + gtk plugin (only needed to bundle GTK)
#
# This script is intentionally dependency-light: it builds an AppDir by hand and
# calls appimagetool. If appimagetool is missing it is downloaded once.
set -euo pipefail

APP_NAME="Montala"
APP_ID="ir.montala.montala"
VERSION="${VERSION:-1.0.0}"
ARCH="${ARCH:-x86_64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLE="$APP_ROOT/build/linux/x64/release/bundle"
DIST="$APP_ROOT/dist"
CACHE="$APP_ROOT/.cache/appimage"
APPDIR="$DIST/Montala.AppDir"

[[ -x "$BUNDLE/montala" ]] || {
  echo "error: no Linux bundle at $BUNDLE" >&2
  echo "       run: flutter build linux --release" >&2
  exit 1
}

mkdir -p "$DIST" "$CACHE"

# ---------------------------------------------------------------- AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/512x512/apps"

cp -r "$BUNDLE/." "$APPDIR/usr/bin/"

# Icon: prefer the 512px web icon, fall back to the Windows one.
ICON_SRC="$APP_ROOT/web/icons/Icon-512.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/512x512/apps/montala.png"
  cp "$ICON_SRC" "$APPDIR/montala.png"
fi

cp "$SCRIPT_DIR/montala.desktop" "$APPDIR/montala.desktop"
cp "$SCRIPT_DIR/montala.desktop" "$APPDIR/usr/share/applications/montala.desktop"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/usr/bin/montala" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# ------------------------------------------------------------ appimagetool
TOOL="$CACHE/appimagetool-$ARCH.AppImage"
if [[ ! -x "$TOOL" ]]; then
  echo "downloading appimagetool…"
  curl -fL --retry 3 -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
  chmod +x "$TOOL"
fi

OUT="$DIST/$APP_NAME-$VERSION-$ARCH.AppImage"
ARCH="$ARCH" "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT" ||
  ARCH="$ARCH" "$TOOL" "$APPDIR" "$OUT"

chmod +x "$OUT"
echo "built: $OUT"
