#!/usr/bin/env bash
#
# check.sh -- self-test for the qbjs-docker Makefile.
#
# Validates target *hygiene* and recipe *logic* WITHOUT running any heavy
# build (no docker, cargo, electron-builder, wine, sudo, or GUI launches).
# Runs in ~seconds so it's cheap enough for pre-commit / CI.
#
# Four layers:
#   1. lint      -- every documented target is in .PHONY, and vice-versa
#   2. dry-run   -- `make -n` expands every target's recipe (catches bad
#                   variables / make syntax across 100% of targets)
#   3. echo-only -- the informational targets actually run and exit 0
#   4. select    -- fixture tests for the run-*/open-* artifact selection,
#                   the class of bug that made run-electron launch arm64
#                   on an x86_64 host
#
# Exit 0 = all pass; non-zero = at least one failure.

set -uo pipefail

# Run from the repo root (parent of bin/) no matter where we're invoked.
cd "$(dirname "$0")/.." || exit 2
MK=Makefile

# ---- pretty output (honours NO_COLOR) -------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; Z=$'\033[0m'
else
  G=; R=; Y=; B=; Z=
fi
pass=0; fail=0
ok()   { printf '  %sok%s   %s\n'   "$G" "$Z" "$1"; pass=$((pass + 1)); }
bad()  { printf '  %sFAIL%s %s\n'   "$R" "$Z" "$1"; fail=$((fail + 1)); }
info() { printf '  %s--%s   %s\n'   "$Y" "$Z" "$1"; }
sect() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }

# Assert a command's exit status. Usage: expect <0|nonzero> <label> -- cmd...
expect() {
  local want="$1" label="$2"; shift 3   # drop want, label, and the "--"
  "$@" >/dev/null 2>&1; local got=$?
  if { [ "$want" = 0 ] && [ "$got" -eq 0 ]; } ||
     { [ "$want" = nonzero ] && [ "$got" -ne 0 ]; }; then
    ok "$label"
  else
    bad "$label (exit $got, wanted $want)"
  fi
}

# ---- discover targets straight from the Makefile --------------------------
# Documented targets are the source of truth: `name: ... ## description`.
# Kept as a newline-separated list (not a bash array) so this runs on macOS's
# bash 3.2 too -- target names are single words, so `for t in $DOCUMENTED` is safe.
DOCUMENTED=$(grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*## ' "$MK" | sed 's/:.*//' | sort -u)
DOC_COUNT=$(printf '%s\n' "$DOCUMENTED" | grep -c .)
# The .PHONY declaration (single line here) lists intended phony targets.
PHONY=$(grep -E '^\.PHONY:' "$MK" | sed 's/^\.PHONY://')

printf '%sqbjs-docker Makefile self-test%s  (%d documented targets)\n' \
  "$B" "$Z" "$DOC_COUNT"

# ===========================================================================
# 0. host tools -- answers "is my environment able to build?" (informational)
# ===========================================================================
sect "host tools"
printf '  host: %s / %s\n' "$(uname -s)" "$(uname -m)"
for t in make docker node cargo wine unzip tar; do
  if command -v "$t" >/dev/null 2>&1; then
    ok "$t present"
  else
    info "$t missing (only needed by some targets)"
  fi
done

# ===========================================================================
# 1. lint -- .PHONY completeness (catches "added a target, forgot .PHONY")
# ===========================================================================
sect "lint: .PHONY completeness"
for t in $DOCUMENTED; do
  case " $PHONY " in
    *" $t "*) : ;;
    *) bad ".PHONY is missing '$t'" ;;
  esac
done
[ "$fail" -eq 0 ] && ok "all $DOC_COUNT documented targets are in .PHONY"
# Reverse: a .PHONY entry with no rule is a typo waiting to bite.
for p in $PHONY; do
  found=
  for t in $DOCUMENTED; do [ "$p" = "$t" ] && { found=1; break; }; done
  [ -n "$found" ] || info ".PHONY lists '$p' but it has no documented rule"
done

# ===========================================================================
# 2. dry-run -- `make -n` must expand every target without error.
#    Safe even for all/clean/push: -n prints, never executes.
# ===========================================================================
sect "dry-run: recipe/variable expansion"
for t in $DOCUMENTED; do
  if make -n "$t" >/dev/null 2>&1; then :; else bad "make -n $t failed"; fi
done
[ "$fail" -eq 0 ] && ok "all $DOC_COUNT targets expand under make -n"

# ===========================================================================
# 3. echo-only -- informational targets run for real and exit 0
# ===========================================================================
sect "echo-only targets run clean"
expect 0 "make help"         -- make -s help
expect 0 "make tauri-mac"    -- make -s tauri-mac
expect 0 "make electron-mac" -- make -s electron-mac

# ===========================================================================
# 4. select -- fixture tests for artifact selection (the real bug class).
#    RUN_PICK_ONLY makes the run-* recipes resolve-and-print instead of
#    launching, so we test the REAL recipe, not a copy that could drift.
# ===========================================================================
sect "select: run-* pick the host-arch artifact"

# Electron (electron-builder) names AppImages x86_64 / arm64.
case "$(uname -m)" in
  x86_64|amd64)  WANT=x86_64; OTHER=arm64  ;;
  aarch64|arm64) WANT=arm64;  OTHER=x86_64 ;;
  *)             WANT=$(uname -m); OTHER=x86_64 ;;
esac
# NW.js names its archives x64 / arm64 (different token from electron).
case "$(uname -m)" in
  x86_64|amd64)  NW_WANT=x64   ;;
  aarch64|arm64) NW_WANT=arm64 ;;
  *)             NW_WANT=$(uname -m) ;;
esac

# --- run-electron: both arches present -> must choose the host's ---
fix=$(mktemp -d)
: > "$fix/App_0.1.0_arm64.AppImage"
: > "$fix/App_0.1.0_x86_64.AppImage"
got=$(make -s run-electron ELECTRON_OUT="$fix" RUN_PICK_ONLY=1 2>/dev/null)
case "$got" in
  *"$WANT"*) ok "run-electron picks $WANT among {arm64,x86_64}" ;;
  *) bad "run-electron picked '$(basename "${got:-<none>}")', wanted *$WANT*" ;;
esac
rm -rf "$fix"

# --- run-electron: only the WRONG arch present -> guard must fire (exit 1) ---
fix=$(mktemp -d)
: > "$fix/App_0.1.0_${OTHER}.AppImage"
expect nonzero "run-electron errors when no $WANT AppImage exists" \
  -- make -s run-electron ELECTRON_OUT="$fix" RUN_PICK_ONLY=1
rm -rf "$fix"

# --- run-electron: nothing built -> guard must fire ---
fix=$(mktemp -d)
expect nonzero "run-electron errors on empty output dir" \
  -- make -s run-electron ELECTRON_OUT="$fix" RUN_PICK_ONLY=1
rm -rf "$fix"

# --- run-nwjs-linux: both arches present -> picks the host's linux-$NW_WANT ---
fix=$(mktemp -d)
: > "$fix/App-0.1.0-linux-x64.tar.gz"
: > "$fix/App-0.1.0-linux-arm64.tar.gz"
got=$(make -s run-nwjs-linux NWJS_OUT="$fix" RUN_PICK_ONLY=1 2>/dev/null)
case "$got" in
  *"linux-$NW_WANT"*) ok "run-nwjs-linux picks linux-$NW_WANT among {x64,arm64}" ;;
  *) bad "run-nwjs-linux picked '$(basename "${got:-<none>}")', wanted *linux-$NW_WANT*" ;;
esac
rm -rf "$fix"

# --- run-nwjs-win: both arches present -> picks the host's win-$NW_WANT ---
# (pick mode short-circuits before the wine check, so no wine needed here)
fix=$(mktemp -d)
: > "$fix/App-0.1.0-win-x64.zip"
: > "$fix/App-0.1.0-win-arm64.zip"
got=$(make -s run-nwjs-win NWJS_OUT="$fix" RUN_PICK_ONLY=1 2>/dev/null)
case "$got" in
  *"win-$NW_WANT"*) ok "run-nwjs-win picks win-$NW_WANT among {x64,arm64}" ;;
  *) bad "run-nwjs-win picked '$(basename "${got:-<none>}")', wanted *win-$NW_WANT*" ;;
esac
rm -rf "$fix"

# ===========================================================================
# 5. open-* -- guard fires on missing dir; resolves the right dir when present.
#    OPEN=echo swaps xdg-open for echo, so nothing launches a file manager.
# ===========================================================================
sect "open-*: reveal the right dir, guard when absent"

fix=$(mktemp -d)
got=$(make -s open-dist DIST="$fix" OPEN=echo 2>/dev/null)
[ "$got" = "$fix" ] && ok "open-dist targets its DIST dir" \
                    || bad "open-dist echoed '$got', wanted '$fix'"
rm -rf "$fix"

expect nonzero "open-dist errors on a missing dir" \
  -- make -s open-dist DIST="/nonexistent-$$-qbjs" OPEN=echo

fix=$(mktemp -d)
got=$(make -s open-electron ELECTRON_OUT="$fix" OPEN=echo 2>/dev/null)
[ "$got" = "$fix" ] && ok "open-electron targets its output dir" \
                    || bad "open-electron echoed '$got', wanted '$fix'"
rm -rf "$fix"

# ---- summary --------------------------------------------------------------
printf '\n'
if [ "$fail" -eq 0 ]; then
  printf '%sALL PASS%s  %d checks, 0 failures\n' "$G" "$Z" "$pass"
  exit 0
else
  printf '%s%d FAILED%s, %d passed\n' "$R" "$fail" "$Z" "$pass"
  exit 1
fi
