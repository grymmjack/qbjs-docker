# Changelog

All notable changes to qbjs-docker are documented here.

## [Unreleased]

### Added
- **`Makefile`** — one-command targets (`make web`/`serve`/`tauri`/`nwjs`/`test`/`clean`).
- **`bin/qbjs-tauri.sh`** — scaffold + build a Tauri app around a `dist/` bundle; used by
  both `make tauri` and CI (single source of truth for config token substitution).
- **Cross-compilation:**
  - `make tauri-win` — Windows `.exe` + NSIS `-setup.exe` cross-compiled from Linux via
    `cargo-xwin` (verified: PE32+ x86-64, 3.0 MB exe / 1.3 MB installer). `.msi` needs a
    Windows host, so it's produced by the CI matrix instead.
  - `make tauri-win-deps` — installs the LLVM cross toolchain (`clang`, `lld`, `llvm-rc`)
    + `nsis` that `cargo-xwin` requires; `qbjs-tauri.sh` preflights these with a clear error.
  - `make tauri-mac` — explains macOS must build on a macOS/CI runner (Apple SDK is macOS-only).
  - `make tauri-all` — everything buildable locally (Linux + Windows).
  - `reusable-build.yml` builds Tauri natively on `ubuntu`/`macos`/`windows` runners.

### Fixed
- **Asset-copy bloat.** `qbjs-build.sh` swept the whole working tree into the bundle,
  so build outputs (`out/`, `tauri-app/`, `target/`, `.git/`) could balloon a bundle to
  hundreds of MB and get embedded in the native binary. Assets are now taken from the
  **source file's directory**, with comprehensive excludes for build/VCS/dependency dirs
  and native artifacts. A trivial app now bundles to ~0.5 MB.
- **Homebrew pkg-config collision.** On hosts where `pkg-config` resolves to
  `/home/linuxbrew/...`, the Tauri build failed with `gdk-3.0 not found` even with the
  `-dev` packages installed. `qbjs-tauri.sh` now adds the system pkg-config dirs to
  `PKG_CONFIG_PATH`, and `make tauri-deps` detects already-installed libs correctly.
- Executable bits set on all `bin/` scripts (stored in git as mode `100755`).

## [1.0.0] - 2026-07-20

Initial release.

### Added
- **Docker image** (`ghcr.io/grymmjack/qbjs-docker`): Node-based toolchain that
  clones QBJS (default `main` = v0.11.1) at build time. No C/C++ toolchain needed.
- **`build` / `serve` / `compile` / `version`** container commands via `entrypoint.sh`.
- **`qbjs-compile.js`** — hardened headless compiler:
  - Patches the missing `func_Abs` so integer division (`\`) compiles (upstream bug).
  - Returns a non-zero exit code on compile errors (`QBJS_STRICT=1` also fails on warnings).
- **`qbjs-build.sh`** — assembles a deployable web bundle matching QBJS's own export
  manifest, plus a PWA layer (`manifest.json` + lean `service-worker.js`), and copies
  project assets honoring `.qbjsignore`.
- **`qbjs-serve.js`** — dependency-free static server with correct MIME types,
  `Service-Worker-Allowed` header, and path-traversal protection.
- **Native desktop packaging:**
  - Tauri v2 template (modern, small native binaries).
  - `qbjs-nwjs.sh` NWJS packager (legacy; builds all platforms from one Linux job).
- **GitHub Actions:**
  - `action.yml` — composite action to build a web bundle.
  - `reusable-build.yml` — web bundle → Pages, Tauri matrix, NWJS, and tagged Releases.
  - `docker-build.yml` — build & publish the image to GHCR.
  - `test.yml` — end-to-end pipeline test.
- **`examples/Dockerfile`** — runnable app container pattern.
