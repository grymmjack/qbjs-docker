#!/usr/bin/env bash
#
# qbjs-tauri.sh -- scaffold (and optionally build) a Tauri native desktop app
#                  around a built QBJS web bundle (dist/).
#
# Tauri is the modern NWJS replacement: small native binaries that use the OS
# webview. This script copies the Tauri template, drops your bundle in as the
# frontend, and fills in the config tokens Tauri requires (notably a real semver
# version, which the raw template leaves as a placeholder).
#
# Usage:
#   qbjs-tauri.sh --dist dist --name "My App" [options]
#
# Options (env in parens):
#   --dist <dir>        Built web bundle to wrap             (default: dist)
#   --name <name>       Product name / window title          (default: "QBJS App")
#   --id <id>           Reverse-domain app id                (default: org.qbjs.<slug>)
#   --version <semver>  App version                          (default: 0.1.0)
#   --out <dir>         Where to scaffold the Tauri project  (default: tauri-app)
#   --icon <png>        Square PNG for icon generation       (default: <dist>/logo-256.png)
#   --build             Also run: npm install, tauri icon, tauri build
#
# Requirements for --build: Node + Rust; on Linux also libwebkit2gtk-4.1-dev,
# libgtk-3-dev, patchelf (see README). Without --build it only scaffolds, so you
# can inspect/tweak before building.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${QBJS_TEMPLATES:-$SCRIPT_DIR/../templates}"

DIST="dist"
NAME="QBJS App"
ID=""
VERSION="0.1.0"
OUT="tauri-app"
ICON=""
DO_BUILD=0
TARGET=""     # Rust target triple; empty = native host

die() { echo "qbjs-tauri: $*" >&2; exit 1; }
esc() { printf '%s' "$1" | sed 's/[&/\]/\\&/g'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dist) DIST="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --id) ID="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --icon) ICON="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --build) DO_BUILD=1; shift;;
    *) die "unknown option: $1";;
  esac
done

[ -d "$DIST" ] || die "web bundle not found: $DIST (run qbjs-build.sh first)"
[ -f "$DIST/index.html" ] || die "$DIST/index.html missing -- not a QBJS bundle"
[ -d "$TEMPLATES_DIR/tauri" ] || die "Tauri template not found at $TEMPLATES_DIR/tauri"

# Default app id from a slug of the name.
if [ -z "$ID" ]; then
  SLUG="$(printf '%s' "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-')"
  ID="org.qbjs.${SLUG:-app}"
fi
[ -z "$ICON" ] && ICON="dist/logo-256.png"

echo "==> Scaffolding Tauri project"
echo "    name    : $NAME"
echo "    id      : $ID"
echo "    version : $VERSION"
echo "    out     : $OUT"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$TEMPLATES_DIR/tauri/." "$OUT/"
# Bring the web bundle in as the Tauri frontend (frontendDist = ../dist).
rm -rf "$OUT/dist"
cp -a "$DIST" "$OUT/dist"

# Fill in the config tokens (version MUST be real semver for Tauri to build).
CFG="$OUT/src-tauri/tauri.conf.json"
sed -i.bak \
  -e "s/{{APP_NAME}}/$(esc "$NAME")/g" \
  -e "s/{{APP_ID}}/$(esc "$ID")/g" \
  -e "s/{{APP_VERSION}}/$(esc "$VERSION")/g" \
  "$CFG"
rm -f "$CFG.bak"

# A Windows target from a non-Windows host = cross-compile via cargo-xwin.
RUNNER=""
case "$TARGET" in
  *windows-msvc)
    case "$(uname -s)" in
      Linux|Darwin) RUNNER="--runner cargo-xwin";;
    esac ;;
  *apple-darwin)
    [ "$(uname -s)" = "Darwin" ] || \
      die "macOS cannot be cross-compiled from $(uname -s). Build on macOS or use the CI matrix (reusable-build.yml)."
    ;;
esac

if [ "$DO_BUILD" = "0" ]; then
  echo "==> Scaffolded. To build:"
  echo "    cd $OUT && npm install && npm run tauri icon $ICON && npm run tauri build${TARGET:+ -- $RUNNER --target $TARGET}"
  exit 0
fi

# Native Linux builds: make sure pkg-config can see the system GTK/webkit libs.
# (Homebrew's pkg-config, if first on PATH, ignores the system search paths.)
if [ "$(uname -s)" = "Linux" ] && { [ -z "$TARGET" ] || [ "$TARGET" != "${TARGET%linux-gnu}" ]; }; then
  MA="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
  export PKG_CONFIG_PATH="/usr/lib/${MA}/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

# Set up cross-compile toolchain for a Windows target.
if [ -n "$RUNNER" ]; then
  echo "==> Preparing Windows cross-compile toolchain (cargo-xwin)"
  command -v cargo >/dev/null || die "Rust/cargo required (https://rustup.rs)"
  # cargo-xwin builds against the MSVC CRT but still needs LLVM's clang/lld to
  # compile/link and llvm-rc to compile the Windows resource (icon/version) file.
  for t in clang lld llvm-rc; do
    command -v "$t" >/dev/null || \
      die "Windows cross-compile needs '$t'. Install: sudo apt-get install clang lld llvm nsis  (or: make tauri-win-deps)"
  done
  rustup target add "$TARGET" >/dev/null 2>&1 || true
  command -v cargo-xwin >/dev/null || cargo install --locked cargo-xwin
  command -v makensis >/dev/null || echo "  note: 'makensis' (nsis) not found -- NSIS installer may be skipped (raw .exe still produced)"
fi

echo "==> Installing Tauri CLI"
( cd "$OUT" && npm install )
echo "==> Generating icons from $ICON"
( cd "$OUT" && npm run tauri icon "$ICON" )
echo "==> Building${TARGET:+ for $TARGET} (compiles Rust; first build is slow)"
( cd "$OUT" && npm run tauri build -- $RUNNER ${TARGET:+--target "$TARGET"} )

BUNDLE_DIR="$OUT/src-tauri/target/${TARGET:+$TARGET/}release/bundle"
echo "==> Done. Installers under: $BUNDLE_DIR/"
find "$BUNDLE_DIR" -maxdepth 2 -type f \
  \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' \
     -o -name '*.dmg' -o -name '*.msi' -o -name '*.exe' \) 2>/dev/null || true
