<#
.SYNOPSIS
  Windows entry point for building qbjs-docker.

.DESCRIPTION
  The Makefile is a Unix-shell + GNU-make build system. On Windows you do NOT run
  it in cmd/PowerShell -- you run it inside a Unix environment. This script checks
  your machine and steers you to the right one (WSL is best), then hands off to
  ./bootstrap.sh in there.

  It deliberately does NOT install a native Windows make. The Makefile's recipes
  use ls / tar / unzip / mktemp / docker / xdg-open and bash syntax that a native
  make.exe (running cmd.exe) cannot execute -- installing GnuWin32 make would find
  the tool and then fail on the first line of every recipe.

  Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Install
  Attempt to install WSL via `wsl --install` (needs Administrator + a reboot).

.PARAMETER Help
  Show usage and exit.

.EXAMPLE
  .\bootstrap.ps1
  .\bootstrap.ps1 -Install
#>
[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

function Have([string]$name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Ok  ([string]$t) { Write-Host "  ok   $t" -ForegroundColor Green }
function Warn([string]$t) { Write-Host "  --   $t" -ForegroundColor Yellow }
function Say ([string]$t) { Write-Host $t -ForegroundColor Cyan }

if ($Help) {
  @"
bootstrap.ps1 -- Windows entry point for qbjs-docker.

Usage:
  .\bootstrap.ps1            check your Windows environment and print how to build
  .\bootstrap.ps1 -Install   install WSL if it's missing (needs admin + reboot)
  .\bootstrap.ps1 -Help      show this help

Why not just install make?
  The Makefile is Unix make: its recipes use ls/tar/unzip/mktemp/docker and bash
  syntax. You build inside WSL (recommended), MSYS2, or Git Bash -- there,
  ./bootstrap.sh takes over. A native make.exe cannot run these recipes.
"@ | Write-Host
  exit 0
}

$repo = $PSScriptRoot
$osv  = [System.Environment]::OSVersion.Version
Write-Host "bootstrap.ps1  host: Windows $osv"
Write-Host ""

# ---- WSL present, and does it have a distro? ------------------------------
$wslReady = $false
$distros  = @()
if (Have 'wsl') {
  # `wsl -l -q` emits UTF-16 with stray NULs on PS 5.1 -- strip them, drop blanks.
  $raw = & wsl.exe -l -q 2>$null
  $distros = $raw | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -ne '' }
  if ($distros.Count -gt 0) { $wslReady = $true }
}

# ---- Docker Desktop (needed for the container targets) --------------------
$dockerReady = Have 'docker'

# ---- Windows package managers (report only; NOT used to install make) -----
$pkg = @()
foreach ($p in 'winget', 'choco', 'scoop') { if (Have $p) { $pkg += $p } }

if ($wslReady) { Ok "WSL installed (distros: $($distros -join ', '))" }
else           { Warn 'WSL not installed' }
if ($dockerReady) { Ok 'docker on PATH (Docker Desktop)' }
else              { Warn 'docker not found -- needed for: make web / image / test / demo' }
if ($pkg.Count -gt 0) { Write-Host "       package managers: $($pkg -join ', ')" }
Write-Host ""

# ---- Path A: WSL is ready -> build there ----------------------------------
if ($wslReady) {
  Say "You're set. Build inside WSL:"
  Write-Host ""
  $wslPath = (& wsl.exe wslpath -a "$repo" 2>$null)
  if ($wslPath) { $wslPath = ($wslPath -replace "`0", '').Trim() }
  Write-Host "  wsl"
  if ($wslPath) { Write-Host "  cd '$wslPath'" }
  Write-Host "  ./bootstrap.sh      # installs GNU make in the distro if needed"
  Write-Host "  make check          # fast self-test"
  Write-Host "  make demo           # build + serve"
  Write-Host ""
  if (-not $dockerReady) {
    Warn 'Install Docker Desktop (enable the WSL2 backend) for the container builds.'
    Write-Host ""
  }
  if ($wslPath) {
    Say "Running ./bootstrap.sh inside WSL now (check-only; installs nothing without -y)..."
    & wsl.exe -e sh -c "cd '$wslPath' && ./bootstrap.sh"
  }
  exit 0
}

# ---- Path B: no WSL -> recommend it, list alternatives --------------------
Say "Recommended: install WSL -- a real Linux environment; the build runs there."
Write-Host ""
Write-Host "  wsl --install        # needs Administrator + a reboot"
Write-Host ""
Say "Alternatives that also work (each gives you a Unix shell + make):"
Write-Host "  - MSYS2   https://www.msys2.org   then:  pacman -S make  &&  ./bootstrap.sh"
Write-Host "  - Git Bash (ships with Git for Windows):  ./bootstrap.sh"
Write-Host ""
Write-Host "Do NOT install a native make.exe (GnuWin32/choco/scoop): the Makefile's recipes" -ForegroundColor Yellow
Write-Host "use ls/tar/unzip/mktemp/docker and bash syntax that only run in a Unix shell." -ForegroundColor Yellow

if ($Install) {
  Write-Host ""
  Say 'Attempting: wsl --install  (a UAC elevation prompt and reboot may be required)...'
  Start-Process -FilePath 'wsl' -ArgumentList '--install' -Verb RunAs
}
exit 1
