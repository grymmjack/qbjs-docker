@echo off
rem ---------------------------------------------------------------------------
rem bootstrap.cmd -- Windows convenience wrapper for bootstrap.ps1.
rem
rem Runs the PowerShell bootstrap without needing to change ExecutionPolicy, so
rem users can just double-click this file or run `bootstrap.cmd` from cmd.exe.
rem Any arguments (e.g. -Install, -Help) are passed straight through.
rem ---------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
