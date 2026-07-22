#!/usr/bin/env bash
#
# qbjs-electron.sh -- scaffold (and optionally build) an Electron desktop app
#                     around a built QBJS web bundle (dist/).
#
# Electron bundles its own Chromium + Node (like NW.js) but with far better
# tooling: electron-builder produces installers for every OS/arch and, unlike
# Tauri, cross-*arch* is free (it just repackages prebuilt Electron runtimes --
# no compilation). macOS still needs a macOS host for the .dmg.
#
# Usage:
#   qbjs-electron.sh --dist dist --name "My App" [options]
#
#   --dist <dir>        Built web bundle to wrap            (default: dist)
#   --name <name>       Product name / window title         (default: "QBJS App")
#   --id <id>           Reverse-domain app id               (default: org.qbjs.<slug>)
#   --version <semver>  App version                         (default: 0.1.0)
#   --out <dir>         Where to scaffold the project       (default: electron-app)
#   --platform <p>      linux | win | mac                   (default: host)
#   --build             Also run: npm install + electron-builder
#
# For --build: Node is required. Building the Windows target from Linux needs
# wine; the macOS .dmg must be built on macOS. Set CSC_LINK/CSC_KEY_PASSWORD to
# sign macOS with a real Developer ID (else an ad-hoc signature is used).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${QBJS_TEMPLATES:-$SCRIPT_DIR/../templates}"

DIST="dist"
NAME="QBJS App"
ID=""
VERSION="0.1.0"
OUT="electron-app"
PLATFORM=""
DO_BUILD=0

die() { echo "qbjs-electron: $*" >&2; exit 1; }
esc() { printf '%s' "$1" | sed 's/[&/\]/\\&/g'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dist) DIST="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --id) ID="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    --build) DO_BUILD=1; shift;;
    *) die "unknown option: $1";;
  esac
done

[ -d "$DIST" ] || die "web bundle not found: $DIST (run qbjs-build.sh first)"
[ -f "$DIST/index.html" ] || die "$DIST/index.html missing -- not a QBJS bundle"
[ -d "$TEMPLATES_DIR/electron" ] || die "Electron template not found at $TEMPLATES_DIR/electron"

if [ -z "$ID" ]; then
  SLUG="$(printf '%s' "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-')"
  ID="org.qbjs.${SLUG:-app}"
fi

# Default platform to the host OS.
if [ -z "$PLATFORM" ]; then
  case "$(uname -s)" in
    Linux)  PLATFORM=linux;;
    Darwin) PLATFORM=mac;;
    *)      PLATFORM=win;;
  esac
fi
case "$PLATFORM" in linux|win|mac) ;; *) die "platform must be linux|win|mac";; esac

echo "==> Scaffolding Electron project"
echo "    name     : $NAME"
echo "    id       : $ID"
echo "    version  : $VERSION"
echo "    platform : $PLATFORM"
echo "    out      : $OUT"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$TEMPLATES_DIR/electron/." "$OUT/"
rm -rf "$OUT/dist"
cp -a "$DIST" "$OUT/dist"

# Fill in tokens: name -> main.js + electron-builder.yml, version -> package.json.
sed -i.bak "s/{{APP_NAME}}/$(esc "$NAME")/g" "$OUT/main.js" && rm -f "$OUT/main.js.bak"
sed -i.bak -e "s/{{APP_NAME}}/$(esc "$NAME")/g" -e "s/{{APP_ID}}/$(esc "$ID")/g" \
  "$OUT/electron-builder.yml" && rm -f "$OUT/electron-builder.yml.bak"
sed -i.bak "s/{{APP_VERSION}}/$(esc "$VERSION")/g" "$OUT/package.json" && rm -f "$OUT/package.json.bak"

if [ "$DO_BUILD" = "0" ]; then
  echo "==> Scaffolded. To build:"
  echo "    cd $OUT && npm install && npx electron-builder --$PLATFORM"
  exit 0
fi

command -v node >/dev/null || die "Node.js required (https://nodejs.org)"

echo "==> Installing dependencies"
( cd "$OUT" && npm install )

# macOS with no real certificate -> ad-hoc sign so the build succeeds.
EXTRA=""
if [ "$PLATFORM" = "mac" ] && [ -z "${CSC_LINK:-}" ]; then
  EXTRA="-c.mac.identity=-"
  echo "    (no CSC_LINK -> ad-hoc signing; set CSC_LINK for a Developer ID build)"
fi
if [ "$PLATFORM" = "win" ] && [ "$(uname -s)" = "Linux" ] && ! command -v wine >/dev/null 2>&1; then
  echo "    note: building the Windows installer from Linux usually needs 'wine'."
fi

echo "==> Building Electron app ($PLATFORM)"
( cd "$OUT" && npx electron-builder "--$PLATFORM" $EXTRA --publish never )

echo "==> Done. Installers under: $OUT/release/"
find "$OUT/release" -maxdepth 1 -type f \
  \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' \
     -o -name '*.dmg' -o -name '*.exe' -o -name '*.msi' \) 2>/dev/null || true
