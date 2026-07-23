#!/bin/sh
#
# install.sh -- one-line installer for qbjs-docker (Linux & macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/grymmjack/qbjs-docker/main/install.sh | sh
#
# It clones (or updates) the repo, then runs ./bootstrap.sh to make sure GNU make
# is present. Override the defaults with env vars:
#   QBJS_DIR=/path/to/dir   where to clone   (default: ~/qbjs-docker)
#   QBJS_REF=branch-or-tag  what to check out (default: main)
#
# The whole script is wrapped in main() and only invoked on the last line, so a
# truncated download (dropped connection mid-pipe) can never execute a partial
# command.

main() {
  set -eu

  REPO_URL="https://github.com/grymmjack/qbjs-docker.git"
  DEST="${QBJS_DIR:-$HOME/qbjs-docker}"
  BRANCH="${QBJS_REF:-main}"

  if ! command -v git >/dev/null 2>&1; then
    echo "qbjs-docker install: 'git' is required -- install it and re-run." >&2
    exit 1
  fi

  if [ -d "$DEST/.git" ]; then
    echo "==> Updating existing checkout: $DEST"
    git -C "$DEST" pull --ff-only
  else
    echo "==> Cloning qbjs-docker -> $DEST"
    git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
  fi

  cd "$DEST"

  # Ensure GNU make. bootstrap.sh is non-fatal: if make is missing it prints the
  # exact install command and exits non-zero -- we carry on and tailor the hint.
  make_ready=0
  if [ -x ./bootstrap.sh ]; then
    if ./bootstrap.sh; then make_ready=1; fi
  fi

  echo ""
  echo "==> qbjs-docker ready at: $DEST"
  if [ "$make_ready" = 1 ]; then
    echo "    Next:  cd \"$DEST\"  &&  make check  &&  make demo"
  else
    echo "    Install GNU make (see the note above), then:  cd \"$DEST\"  &&  make check"
  fi
}

main "$@"
