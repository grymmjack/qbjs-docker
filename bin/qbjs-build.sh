#!/usr/bin/env bash
#
# qbjs-build.sh  --  compile a QBJS .bas program and assemble a deployable,
#                    installable (PWA) static web bundle.
#
# Usage:
#   qbjs-build.sh <source.bas> [options]
#
# Options (also settable via env):
#   -o, --out <dir>       Output directory            (QBJS_OUT,   default: dist)
#   -n, --name <name>     App name (title/manifest)   (QBJS_NAME,  default: source basename)
#   -m, --mode <auto|play> Loader style               (QBJS_MODE,  default: auto)
#                           auto = run on load; play = "click to start" screen
#                           (use play for apps that need audio / a user gesture)
#       --no-pwa          Skip manifest + service worker
#       --no-assets       Skip copying project asset files into the bundle
#   -h, --help            Show this help
#
# Env (paths, normally preset by the Docker image):
#   QBJS_HOME    QBJS runtime + compiler location   (default: /opt/qbjs)
#
# Asset copying: every file in the current directory is copied into the bundle
# except source (*.bas/*.bi/*.bm), VCS/build/editor cruft, and any patterns in a
# .qbjsignore file (one glob per line, '#' comments). Runtime files always win.
set -euo pipefail

QBJS_HOME="${QBJS_HOME:-/opt/qbjs}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${QBJS_TEMPLATES:-$SCRIPT_DIR/../templates}"

OUT="${QBJS_OUT:-dist}"
NAME="${QBJS_NAME:-}"
MODE="${QBJS_MODE:-auto}"
PWA=1
COPY_ASSETS=1
SRC=""

die() { echo "qbjs-build: $*" >&2; exit 1; }

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)  OUT="$2"; shift 2;;
    -n|--name) NAME="$2"; shift 2;;
    -m|--mode) MODE="$2"; shift 2;;
    --no-pwa)  PWA=0; shift;;
    --no-assets) COPY_ASSETS=0; shift;;
    -h|--help) usage;;
    -*) die "unknown option: $1";;
    *) [ -z "$SRC" ] && SRC="$1" || die "unexpected argument: $1"; shift;;
  esac
done

[ -n "$SRC" ] || die "no source .bas file given (see --help)"
[ -f "$SRC" ] || die "source file not found: $SRC"
[ "$MODE" = "auto" ] || [ "$MODE" = "play" ] || die "mode must be 'auto' or 'play'"
[ -f "$QBJS_HOME/qbjs-compile.js" ] || die "QBJS not found at QBJS_HOME=$QBJS_HOME"

# Derive app name from source basename if not supplied.
if [ -z "$NAME" ]; then
  NAME="$(basename "$SRC")"; NAME="${NAME%.*}"
fi

echo "==> QBJS build"
echo "    source : $SRC"
echo "    name   : $NAME"
echo "    mode   : $MODE"
echo "    out    : $OUT"

rm -rf "$OUT"
mkdir -p "$OUT/gx" "$OUT/fonts"
OUT_ABS="$(cd "$OUT" && pwd)"

# --- 1. Compile BASIC -> program.js (hardened compiler; fails on errors) -----
echo "==> Compiling $SRC"
node "$QBJS_HOME/qbjs-compile.js" "$SRC" "$OUT_ABS/program.js"

# --- 2. Copy project assets (before runtime, so runtime files win) -----------
# Assets are taken from the SOURCE FILE's directory (i.e. your project root),
# NOT the current working directory -- so building workspace/game.bas copies
# workspace/ assets, never the whole tree you happen to be standing in.
ASSET_ROOT="$(dirname "$SRC")"
if [ "$COPY_ASSETS" = "1" ]; then
  echo "==> Copying project assets from $ASSET_ROOT/"
  EXCLUDES=(
    # never bundle the output dir, VCS, deps, or build artifacts
    --exclude="$OUT/"
    --exclude=".git/" --exclude=".hg/" --exclude=".svn/"
    --exclude=".github/" --exclude=".vscode/" --exclude=".idea/"
    --exclude="node_modules/" --exclude="target/" --exclude="src-tauri/"
    --exclude="dist/" --exclude="out/" --exclude="build/" --exclude="publish/"
    --exclude="tauri-app/" --exclude="tauri-win/" --exclude="tauri-mac/"
    # source + compiler internals (source is already compiled into program.js)
    --exclude="*.bas" --exclude="*.BAS" --exclude="*.bi" --exclude="*.BI"
    --exclude="*.bm" --exclude="*.BM"
    --exclude="qb2js.js" --exclude="qb-console.js"
    --exclude="qbjs-compile.js" --exclude="qbc.js"
    # ignore files + packaged artifacts
    --exclude=".qbjsignore" --exclude=".gitignore" --exclude=".dockerignore"
    --exclude="*.zip" --exclude="*.tar.gz" --exclude="*.tgz"
    --exclude="*.deb" --exclude="*.rpm" --exclude="*.AppImage"
    --exclude="*.msi" --exclude="*.exe" --exclude="*.dmg" --exclude="*.nw"
  )
  if [ -f "$ASSET_ROOT/.qbjsignore" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      case "$line" in ""|\#*) continue;; esac
      EXCLUDES+=(--exclude="$line")
      echo "    ignoring: $line"
    done < "$ASSET_ROOT/.qbjsignore"
  fi
  rsync -a "${EXCLUDES[@]}" "$ASSET_ROOT/" "$OUT/" 2>/dev/null || true
fi

# --- 3. Copy the QBJS runtime dependency set (the IDE's export manifest) ------
echo "==> Copying QBJS runtime"
cp "$QBJS_HOME/qb.js"                          "$OUT/qb.js"
cp "$QBJS_HOME/vfs.js"                          "$OUT/vfs.js"
cp "$QBJS_HOME/gx/gx.js"                        "$OUT/gx/gx.js"
cp "$QBJS_HOME/gx/__gx_font_default.png"        "$OUT/gx/__gx_font_default.png"
cp "$QBJS_HOME/gx/__gx_font_default_black.png"  "$OUT/gx/__gx_font_default_black.png"
cp "$QBJS_HOME/util/pako.2.1.0.min.js"          "$OUT/pako.2.1.0.min.js"
cp "$QBJS_HOME/export/qbjs.css"                 "$OUT/qbjs.css"
cp "$QBJS_HOME/export/fullscreen.svg"           "$OUT/fullscreen.svg"
cp "$QBJS_HOME/export/fullscreen-hover.svg"     "$OUT/fullscreen-hover.svg"
cp "$QBJS_HOME/export/logo.png"                 "$OUT/logo.png"
cp "$QBJS_HOME/export/3rd-party-licenses.txt"   "$OUT/3rd-party-licenses.txt"
cp "$QBJS_HOME/qbjs.woff2"                       "$OUT/qbjs.woff2"
cp "$QBJS_HOME/play.png"                         "$OUT/play.png"
cp "$QBJS_HOME/favicon.ico"                      "$OUT/favicon.ico"
cp "$QBJS_HOME/logo-256.png"                     "$OUT/logo-256.png"
cp "$QBJS_HOME/fonts/WebPlus_IBM_EGA_8x8.woff"   "$OUT/fonts/WebPlus_IBM_EGA_8x8.woff"
cp "$QBJS_HOME/fonts/README.TXT"                 "$OUT/fonts/README.TXT"

# --- 4. index.html (loader template with {{APP_NAME}} substituted) -----------
echo "==> Writing index.html ($MODE loader)"
sed "s/{{APP_NAME}}/$(printf '%s' "$NAME" | sed 's/[&/\\]/\\&/g')/g" \
  "$TEMPLATES_DIR/index.$MODE.html" > "$OUT/index.html"

# --- 5. PWA layer (installable / offline) ------------------------------------
if [ "$PWA" = "1" ]; then
  echo "==> Adding PWA (manifest + service worker)"
  sed "s/{{APP_NAME}}/$(printf '%s' "$NAME" | sed 's/[&/\\]/\\&/g')/g" \
    "$TEMPLATES_DIR/manifest.json" > "$OUT/manifest.json"
  cp "$TEMPLATES_DIR/service-worker.js" "$OUT/service-worker.js"
fi

echo "==> Done. Web bundle in: $OUT"
echo "    Try it:  node \"$SCRIPT_DIR/qbjs-serve.js\" \"$OUT\" 8080   (http://localhost:8080)"
