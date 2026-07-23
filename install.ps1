# install.ps1 -- one-line installer for qbjs-docker (Windows).
#
#   irm https://raw.githubusercontent.com/grymmjack/qbjs-docker/main/install.ps1 | iex
#
# It clones (or updates) the repo, then runs bootstrap.ps1 to steer you into a
# Unix environment (WSL recommended). Override the defaults with env vars:
#   $env:QBJS_DIR = 'C:\path\to\dir'   where to clone   (default: ~\qbjs-docker)
#   $env:QBJS_REF = 'branch-or-tag'    what to check out (default: main)
#
# Note: this runs inside your current PowerShell session (that's how `iex` works),
# so it uses `return` (never `exit`) for early-outs, and launches bootstrap.ps1 in
# a child process -- otherwise their `exit` would close your window.

$ErrorActionPreference = 'Stop'

$repo   = 'https://github.com/grymmjack/qbjs-docker.git'
$dest   = if ($env:QBJS_DIR) { $env:QBJS_DIR } else { Join-Path $HOME 'qbjs-docker' }
$branch = if ($env:QBJS_REF) { $env:QBJS_REF } else { 'main' }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host "qbjs-docker install: 'git' is required -- install Git for Windows (https://git-scm.com) and re-run." -ForegroundColor Red
  return
}

if (Test-Path (Join-Path $dest '.git')) {
  Write-Host "==> Updating existing checkout: $dest"
  git -C $dest pull --ff-only
} else {
  Write-Host "==> Cloning qbjs-docker -> $dest"
  git clone --branch $branch $repo $dest
}
if ($LASTEXITCODE -ne 0) {
  Write-Host "qbjs-docker install: git failed (exit $LASTEXITCODE)." -ForegroundColor Red
  return
}

# Steer into a Unix environment. Run in a child process so bootstrap.ps1's `exit`
# stays in that process and can't close this session.
$ps = Join-Path $dest 'bootstrap.ps1'
if (Test-Path $ps) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $ps
}

Write-Host ""
Write-Host "==> qbjs-docker ready at: $dest"
Write-Host "    Build inside WSL / MSYS2 / Git Bash:"
Write-Host "      cd `"$dest`""
Write-Host "      ./bootstrap.sh      # ensure GNU make"
Write-Host "      make check ; make demo"
