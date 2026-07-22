#!/usr/bin/env bash
#
# Container entrypoint for the QBJS toolchain image.
# Dispatches sub-commands so one image handles every mode.
#
#   build   <source.bas> [opts]   Compile + assemble a deployable web bundle (dist/)
#   serve   [dir] [port]          Serve a built bundle over HTTP (default ./dist :8080)
#   compile <source.bas> <out.js> Transpile BASIC -> JavaScript only
#   version                       Print QBJS + tool versions
#   help                          Show this help
#
# With no recognised sub-command, arguments are passed straight to qbjs-compile.js
# (so the image can be used as a bare compiler too).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QBJS_HOME="${QBJS_HOME:-/opt/qbjs}"

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

cmd="${1:-help}"
case "$cmd" in
  build)
    shift; exec "$SCRIPT_DIR/qbjs-build.sh" "$@" ;;
  serve)
    shift
    dir="${1:-dist}"; port="${2:-${PORT:-8080}}"
    exec node "$SCRIPT_DIR/qbjs-serve.js" "$dir" "$port" ;;
  compile)
    shift; exec node "$QBJS_HOME/qbjs-compile.js" "$@" ;;
  version|--version|-v)
    echo "qbjs-docker toolchain"
    echo "node    : $(node --version)"
    echo "QBJS ref: ${QBJS_REF:-unknown} (${QBJS_HOME})"
    if [ -f "$QBJS_HOME/index.html" ]; then
      ver="$(grep -oE 'releases[^>]*>[0-9]+\.[0-9]+\.[0-9]+' "$QBJS_HOME/index.html" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
      [ -n "$ver" ] && echo "QBJS ver: $ver"
    fi ;;
  help|--help|-h)
    usage ;;
  *)
    exec node "$QBJS_HOME/qbjs-compile.js" "$@" ;;
esac
