#!/usr/bin/env bash
#
# qbjs-nwjs.sh -- package a built QBJS web bundle (dist/) as a native NW.js app.
#
# NW.js auto-loads a "package.nw" (a zip of the app + its NW manifest) placed
# next to the nw executable. We build that, drop it into the downloaded NW.js
# runtime, and archive the result per platform.
#
# Usage:
#   qbjs-nwjs.sh --dist dist --name "My App" --platform linux|osx|win \
#                [--arch x64] [--nwjs-version 0.95.0] [--out out]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${QBJS_TEMPLATES:-$SCRIPT_DIR/../templates}"

DIST="dist"
NAME="QBJS App"
PLATFORM=""
ARCH="x64"
NWJS_VERSION="${NWJS_VERSION:-0.95.0}"
OUT="out"

die() { echo "qbjs-nwjs: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dist) DIST="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    --nwjs-version) NWJS_VERSION="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) die "unknown option: $1";;
  esac
done

[ -d "$DIST" ] || die "dist directory not found: $DIST"
[ -f "$DIST/index.html" ] || die "$DIST/index.html missing -- run qbjs-build.sh first"
case "$PLATFORM" in linux|osx|win) ;; *) die "platform must be linux|osx|win";; esac

# NW.js download naming, e.g. nwjs-v0.95.0-linux-x64.tar.gz
case "$PLATFORM" in
  linux) NW_PKG="nwjs-v${NWJS_VERSION}-linux-${ARCH}"; EXT="tar.gz";;
  osx)   NW_PKG="nwjs-v${NWJS_VERSION}-osx-${ARCH}";   EXT="zip";;
  win)   NW_PKG="nwjs-v${NWJS_VERSION}-win-${ARCH}";   EXT="zip";;
esac
NW_URL="https://dl.nwjs.io/v${NWJS_VERSION}/${NW_PKG}.${EXT}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

echo "==> NW.js package: $NAME ($PLATFORM/$ARCH, nwjs v$NWJS_VERSION)"

# 1) Build package.nw = zip of (dist contents + NW manifest with app name).
echo "==> Assembling package.nw"
APPSTAGE="$WORK/app"
mkdir -p "$APPSTAGE"
cp -a "$DIST/." "$APPSTAGE/"
sed "s/{{APP_NAME}}/$(printf '%s' "$NAME" | sed 's/[&/\\]/\\&/g')/g" \
  "$TEMPLATES_DIR/nwjs/package.json" > "$APPSTAGE/package.json"
( cd "$APPSTAGE" && zip -qr "$WORK/package.nw" . )

# 2) Download + extract the NW.js runtime.
# NW.js doesn't publish every arch for every OS (e.g. it ships osx-arm64 but no
# linux-arm64 / win-arm64). Skip gracefully rather than fail the whole build.
echo "==> Downloading $NW_URL"
if ! curl -fL "$NW_URL" -o "$WORK/nw.$EXT"; then
  echo "qbjs-nwjs: NW.js has no ${PLATFORM}/${ARCH} runtime at v${NWJS_VERSION} -- skipping." >&2
  exit 0
fi
if [ "$EXT" = "tar.gz" ]; then tar -xzf "$WORK/nw.$EXT" -C "$WORK";
else unzip -q "$WORK/nw.$EXT" -d "$WORK"; fi
NWDIR="$WORK/$NW_PKG"
[ -d "$NWDIR" ] || die "unexpected NW.js archive layout: $NWDIR not found"

# 3) Install the app so NW.js auto-loads it. This differs by platform:
#    - Linux/Windows: a "package.nw" next to the nw executable is auto-loaded.
#    - macOS: NW.js loads the app from INSIDE the bundle, at
#      nwjs.app/Contents/Resources/app.nw -- a top-level package.nw is ignored
#      (which is why a mis-placed one launches NW.js's default welcome app).
if [ "$PLATFORM" = "osx" ]; then
  APP_RES="$NWDIR/nwjs.app/Contents/Resources"
  [ -d "$APP_RES" ] || die "unexpected macOS NW.js layout: $APP_RES not found"
  cp "$WORK/package.nw" "$APP_RES/app.nw"
else
  cp "$WORK/package.nw" "$NWDIR/package.nw"
fi

# 4) Archive the runnable app directory.
SAFE_NAME="$(printf '%s' "$NAME" | tr ' ' '-' | tr -cd '[:alnum:]._-')"
STAGE="$WORK/${SAFE_NAME}-${PLATFORM}-${ARCH}"
mv "$NWDIR" "$STAGE"
case "$PLATFORM" in
  win) ARCHIVE="$OUT/${SAFE_NAME}-win-${ARCH}.zip"
       ( cd "$WORK" && zip -qr "$(basename "$ARCHIVE")" "$(basename "$STAGE")" )
       mv "$WORK/$(basename "$ARCHIVE")" "$ARCHIVE";;
  *)   ARCHIVE="$OUT/${SAFE_NAME}-${PLATFORM}-${ARCH}.tar.gz"
       tar -czf "$ARCHIVE" -C "$WORK" "$(basename "$STAGE")";;
esac

echo "==> Done. NW.js app: $ARCHIVE"
echo "    Launch: extract, then run 'nw' (nw.exe on Windows)."
