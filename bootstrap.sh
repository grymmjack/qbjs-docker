#!/bin/sh
#
# bootstrap.sh -- make sure GNU make is installed before you use the Makefile.
#
# The Makefile itself cannot check for make: by the time any recipe runs, make
# is already running. So this standalone POSIX-sh script bootstraps it. Run it
# FIRST on a fresh machine, then use `make` as normal.
#
#   ./bootstrap.sh              check for GNU make; print the install command if missing
#   ./bootstrap.sh --install    check, and actually install make if missing (uses sudo)
#   ./bootstrap.sh --print-cmd  just print this platform's install command, then exit
#   ./bootstrap.sh --help
#
# Written in portable /bin/sh (no bashisms) because a first-run box may only
# have a minimal shell. Exit 0 = GNU make is ready; non-zero = missing/wrong.

set -u

PROG=${0##*/}
DO_INSTALL=0
PRINT_ONLY=0

for arg in "$@"; do
  case "$arg" in
    -y|--install|--yes) DO_INSTALL=1 ;;
    --print-cmd)        PRINT_ONLY=1 ;;
    -h|--help)
      cat <<EOF
$PROG -- ensure GNU make is installed (bootstrap before using the Makefile).

Usage:
  ./$PROG                check for GNU make; print the install command if missing
  ./$PROG --install      install make if missing (uses sudo where needed)
  ./$PROG --print-cmd    print this platform's install command and exit
  ./$PROG --help         show this help

Exit status: 0 = GNU make ready, 1 = missing/not-GNU, 2 = bad usage.
EOF
      exit 0 ;;
    *) printf 'Unknown option: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

# ---- colours (skip when not a tty, or when NO_COLOR is set) ----------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$(printf '\033[32m'); R=$(printf '\033[31m'); Y=$(printf '\033[33m')
  B=$(printf '\033[1m');  Z=$(printf '\033[0m')
else
  G=; R=; Y=; B=; Z=
fi

# ---- sudo only when we're not root and sudo exists ------------------------
if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
  SUDO=
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo "
else
  SUDO=
fi

# ---- detect platform + the command that installs GNU make -----------------
OS=$(uname -s 2>/dev/null || echo unknown)
INSTALL_CMD=
PLATFORM=$OS

case "$OS" in
  Linux)
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
      PLATFORM="Linux (WSL)"
    fi
    if   command -v apt-get >/dev/null 2>&1; then INSTALL_CMD="${SUDO}apt-get update && ${SUDO}apt-get install -y make"
    elif command -v dnf     >/dev/null 2>&1; then INSTALL_CMD="${SUDO}dnf install -y make"
    elif command -v yum     >/dev/null 2>&1; then INSTALL_CMD="${SUDO}yum install -y make"
    elif command -v pacman  >/dev/null 2>&1; then INSTALL_CMD="${SUDO}pacman -S --noconfirm make"
    elif command -v zypper  >/dev/null 2>&1; then INSTALL_CMD="${SUDO}zypper install -y make"
    elif command -v apk     >/dev/null 2>&1; then INSTALL_CMD="${SUDO}apk add make"
    fi
    ;;
  Darwin)
    PLATFORM="macOS"
    # Xcode Command Line Tools ship GNU make 3.81 (old but enough for this repo);
    # Homebrew provides a newer GNU make installed as 'gmake'.
    if command -v brew >/dev/null 2>&1; then
      INSTALL_CMD="xcode-select --install   # or newer: brew install make (runs as 'gmake')"
    else
      INSTALL_CMD="xcode-select --install"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    PLATFORM="Windows ($OS)"
    if command -v pacman >/dev/null 2>&1; then
      INSTALL_CMD="pacman -S make   # MSYS2"
    else
      INSTALL_CMD="# WSL (recommended):  wsl --install  then run this inside Ubuntu
# MSYS2:               https://www.msys2.org  then: pacman -S make
# winget (old 3.81):   winget install GnuWin32.Make"
    fi
    ;;
esac

# ---- --print-cmd short-circuit --------------------------------------------
if [ "$PRINT_ONLY" = 1 ]; then
  if [ -n "$INSTALL_CMD" ]; then
    printf '%s\n' "$INSTALL_CMD"; exit 0
  fi
  printf 'No known install command for %s.\n' "$PLATFORM" >&2; exit 1
fi

printf '%s%s%s  host: %s\n' "$B" "$PROG" "$Z" "$PLATFORM"

# ---- is (GNU) make present? -----------------------------------------------
READY=0
if command -v make >/dev/null 2>&1; then
  VER=$(make --version 2>/dev/null | head -1)
  if make --version 2>/dev/null | grep -qi 'GNU Make'; then
    printf '  %sok%s   %s\n' "$G" "$Z" "$VER"
    READY=1
  else
    printf '  %swarn%s make present but not GNU make: %s\n' "$Y" "$Z" "${VER:-unknown}"
    printf '       This Makefile uses GNU-only features ( $(MAKEFILE_LIST), := ).\n'
    case "$OS" in
      Darwin) printf '       Get GNU make:  brew install make   (then invoke as gmake)\n' ;;
      *) [ -n "$INSTALL_CMD" ] && printf '       Get GNU make:  %s\n' "$INSTALL_CMD" ;;
    esac
  fi
else
  printf '  %sFAIL%s make is not installed.\n' "$R" "$Z"
fi

# ---- act when make is missing ---------------------------------------------
if [ "$READY" != 1 ]; then
  if [ -z "$INSTALL_CMD" ]; then
    printf '\nNo known install command for %s -- install GNU make manually.\n' "$PLATFORM" >&2
    exit 1
  fi
  # Only auto-run for a genuinely-missing make, and only with explicit --install.
  if [ "$DO_INSTALL" = 1 ] && ! command -v make >/dev/null 2>&1; then
    printf '\nInstalling make:\n  %s\n\n' "$INSTALL_CMD"
    if sh -c "$INSTALL_CMD" && make --version 2>/dev/null | grep -qi 'GNU Make'; then
      printf '%sok%s   installed: %s\n' "$G" "$Z" "$(make --version 2>/dev/null | head -1)"
      READY=1
    else
      printf '%sInstall failed or make still not GNU.%s\n' "$R" "$Z" >&2
      exit 1
    fi
  else
    printf '\nInstall it with:\n  %s\n' "$INSTALL_CMD"
    printf 'Or let this script do it:  ./%s --install\n' "$PROG"
    exit 1
  fi
fi

# ---- bonus preflight: report the other build tools (informational only) ----
printf '\n%sother build tools%s (each target installs/uses what it needs):\n' "$B" "$Z"
for t in docker node cargo wine unzip tar git; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  %sok%s   %s\n' "$G" "$Z" "$t"
  else
    printf '  %s--%s   %s (optional)\n' "$Y" "$Z" "$t"
  fi
done

printf '\n%sReady.%s  Next:  make check   (fast self-test)   |   make demo   (build + serve)\n' "$G" "$Z"
exit 0
