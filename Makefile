.PHONY: help image build web serve compile tauri tauri-deps tauri-win tauri-win-deps tauri-win-arm tauri-mac tauri-all all run run-tauri run-tauri-linux run-tauri-win run-nwjs run-nwjs-linux run-nwjs-win run-electron webview2-wine open open-tauri open-tauri-win open-nwjs open-dist open-electron nwjs nwjs-arm electron electron-win electron-mac demo test clean clean-docker push

# ---- Config (override on the command line, e.g. `make tauri SRC=my.bas NAME="My App"`) ----
IMAGE       := qbjs-docker
TAG         := test
QBJS_REF    := main
SRC         := workspace/bubble-universe.bas
NAME        := Bubble Universe
MODE        := auto
PORT        := 8080
NWJS_VERSION := 0.95.0
DIST        := dist
WIN_TARGET  := x86_64-pc-windows-msvc

# Build-output locations (what run-*/open-* point at)
LINUX_BIN    := tauri-app/src-tauri/target/release/qbjs-app
LINUX_BUNDLE := tauri-app/src-tauri/target/release/bundle
WIN_BIN      := tauri-win/src-tauri/target/$(WIN_TARGET)/release/qbjs-app.exe
WIN_BUNDLE   := tauri-win/src-tauri/target/$(WIN_TARGET)/release/bundle
NWJS_OUT     := out
ELECTRON_OUT := electron-app/release

# File-manager opener (xdg-open on Linux, open on macOS; falls back to echo)
OPEN := $(shell command -v xdg-open 2>/dev/null || command -v open 2>/dev/null || echo echo)

UID := $(shell id -u)
GID := $(shell id -g)

help: ## Show this help
	@echo 'QBJS Docker -- build QBJS apps for web, desktop, and containers.'
	@echo ''
	@echo 'Usage: make [target] [SRC=file.bas] [NAME="App Name"]'
	@echo ''
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

image: ## Build the Docker toolchain image
	docker build --build-arg QBJS_REF=$(QBJS_REF) -t $(IMAGE):$(TAG) .

build: image ## Alias for `image`

web: image ## Compile SRC into a web bundle (PWA) -> ./$(DIST)
	docker run --rm -v "$(PWD):/workspace" --user "$(UID):$(GID)" \
	  $(IMAGE):$(TAG) build "$(SRC)" --name "$(NAME)" --mode "$(MODE)" --out "$(DIST)"
	@echo "Web bundle ready: ./$(DIST)  (try: make serve)"

serve: ## Serve the ./$(DIST) bundle at http://localhost:$(PORT)
	@echo "Serving ./$(DIST) at http://localhost:$(PORT)  (Ctrl+C to stop)"
	docker run --rm -p $(PORT):8080 -v "$(PWD)/$(DIST):/app" $(IMAGE):$(TAG) serve /app 8080

compile: image ## Transpile SRC to JS only (make compile SRC=x.bas OUT=x.js)
	docker run --rm -v "$(PWD):/workspace" $(IMAGE):$(TAG) compile "$(SRC)" "$(or $(OUT),program.js)"

tauri-deps: ## Install Linux system deps Tauri needs (uses sudo; idempotent)
	@if PKG_CONFIG_PATH="/usr/lib/$$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" pkg-config --exists webkit2gtk-4.1 2>/dev/null && command -v patchelf >/dev/null; then \
	  echo "Tauri system deps already present."; \
	elif [ "$$(uname)" != "Linux" ]; then \
	  echo "Non-Linux host: Tauri needs only Rust + the platform SDK (already handled)."; \
	else \
	  echo "Installing Tauri system deps (sudo)..."; \
	  sudo apt-get update && sudo apt-get install -y \
	    libwebkit2gtk-4.1-dev libgtk-3-dev libappindicator3-dev librsvg2-dev patchelf; \
	fi

tauri: web tauri-deps ## Build a native Tauri app for THIS OS (Linux here) -> ./tauri-app
	@command -v cargo >/dev/null || { echo "Rust not found. Install: https://rustup.rs"; exit 1; }
	QBJS_TEMPLATES=templates bin/qbjs-tauri.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out tauri-app --build

tauri-win-deps: ## Install the LLVM cross toolchain for Windows builds (sudo; idempotent)
	@if command -v clang >/dev/null && command -v llvm-rc >/dev/null && command -v lld >/dev/null; then \
	  echo "Windows cross toolchain present."; \
	elif [ "$$(uname)" != "Linux" ]; then \
	  echo "Non-Linux host: install LLVM + NSIS via your package manager if needed."; \
	else \
	  echo "Installing clang + lld + llvm (llvm-rc) + nsis (sudo)..."; \
	  sudo apt-get update && sudo apt-get install -y clang lld llvm nsis; \
	fi

tauri-win: web tauri-win-deps ## Cross-compile a Windows x64 Tauri app from Linux (cargo-xwin)
	@command -v cargo >/dev/null || { echo "Rust not found. Install: https://rustup.rs"; exit 1; }
	QBJS_TEMPLATES=templates bin/qbjs-tauri.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out tauri-win --target $(WIN_TARGET) --build

WIN_ARM_TARGET := aarch64-pc-windows-msvc

tauri-win-arm: web tauri-win-deps ## Cross-compile a Windows ARM64 Tauri app from Linux (cargo-xwin)
	@command -v cargo >/dev/null || { echo "Rust not found. Install: https://rustup.rs"; exit 1; }
	rustup target add $(WIN_ARM_TARGET) 2>/dev/null || true
	QBJS_TEMPLATES=templates bin/qbjs-tauri.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out tauri-win-arm --target $(WIN_ARM_TARGET) --build

tauri-mac: ## macOS build (cannot cross-compile from Linux -- use CI)
	@echo "macOS binaries cannot be built from Linux (Apple SDK + signing are macOS-only)."
	@echo "Use the CI matrix: push a tag and reusable-build.yml builds the .dmg on a macos runner,"
	@echo "exactly like your DRAW build-release.yml does. Or run 'make tauri' on a Mac."

tauri-all: tauri tauri-win ## Build both native Tauri targets locally (Linux + Windows)
	@echo "Built Linux + Windows Tauri locally. macOS -> CI (see 'make tauri-mac')."

all: tauri tauri-win tauri-win-arm nwjs nwjs-arm electron electron-win ## Build EVERYTHING buildable on this x86 Linux host; macOS via CI
	@echo ""
	@echo "== Built locally (x86 Linux): =="
	@echo "  web bundle            -> ./$(DIST)"
	@echo "  Linux x64 Tauri       -> $(LINUX_BUNDLE)/"
	@echo "  Windows x64 Tauri     -> $(WIN_BUNDLE)/"
	@echo "  Windows ARM64 Tauri   -> tauri-win-arm/src-tauri/target/$(WIN_ARM_TARGET)/release/bundle/"
	@echo "  Electron (Linux x64+arm64) -> $(ELECTRON_OUT)/"
	@echo "  Electron (Windows)    -> electron-win/release/"
	@echo "  NW.js x64 + arm64 (Lin/Mac/Win) -> ./$(NWJS_OUT)/"
	@echo "  CI only: macOS Tauri + Electron, Linux ARM64 Tauri"

# ---- run: launch a built binary ------------------------------------------
run-tauri: ## Run the Linux Tauri app
	@[ -x "$(LINUX_BIN)" ] || { echo "Not built yet. Run: make tauri"; exit 1; }
	"./$(LINUX_BIN)"

run-tauri-linux: run-tauri ## Alias for run-tauri
run: run-tauri ## Alias for run-tauri

run-tauri-win: ## Run the Windows Tauri .exe (wine; needs WebView2 - see note)
	@[ -f "$(WIN_BIN)" ] || { echo "Not built yet. Run: make tauri-win"; exit 1; }
	@if command -v wine >/dev/null 2>&1; then \
	  echo "Note: Tauri Windows apps use the WebView2 runtime."; \
	  echo "  Real Windows 11 / updated Win10 have it preinstalled (works out of the box)."; \
	  echo "  Under wine it's usually missing -> 'make webview2-wine' (experimental), or"; \
	  echo "  test the self-contained NW.js build instead: make run-nwjs-win"; \
	  wine "$(WIN_BIN)"; \
	elif [ "$$(uname)" = "Linux" ]; then \
	  echo "Install 'wine' to run the .exe here, or: make open-tauri-win"; exit 1; \
	else "./$(WIN_BIN)"; fi

run-nwjs-linux: ## Extract + run the Linux NW.js package
	@a=$$(ls $(NWJS_OUT)/*-linux-x64.tar.gz 2>/dev/null | head -1); \
	[ -n "$$a" ] || { echo "Not built yet. Run: make nwjs"; exit 1; }; \
	d=$$(mktemp -d); tar -xzf "$$a" -C "$$d"; \
	nw=$$(find "$$d" -maxdepth 2 -name nw -type f | head -1); \
	echo "Running $$(basename "$$a") ..."; (cd "$$(dirname "$$nw")" && ./nw)

run-nwjs: run-nwjs-linux ## Alias for run-nwjs-linux

run-nwjs-win: ## Extract + run the Windows NW.js package (wine; self-contained, no WebView2)
	@a=$$(ls $(NWJS_OUT)/*-win-x64.zip 2>/dev/null | head -1); \
	[ -n "$$a" ] || { echo "Not built yet. Run: make nwjs"; exit 1; }; \
	command -v wine >/dev/null 2>&1 || { echo "Install 'wine' to run the Windows package here."; exit 1; }; \
	d=$$(mktemp -d); unzip -q "$$a" -d "$$d"; \
	exe=$$(find "$$d" -maxdepth 2 -name nw.exe | head -1); \
	echo "Running $$(basename "$$a") with wine (NW.js bundles Chromium - no WebView2 needed)..."; \
	(cd "$$(dirname "$$exe")" && wine nw.exe)

webview2-wine: ## (experimental) Install WebView2 into your wine prefix for run-tauri-win
	@command -v wine >/dev/null 2>&1 || { echo "wine not installed."; exit 1; }
	@echo "Downloading the Evergreen WebView2 bootstrapper..."
	curl -fL "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -o /tmp/MicrosoftEdgeWebview2Setup.exe
	@echo "Installing under wine (best-effort; WebView2-on-wine is unreliable)..."
	-wine /tmp/MicrosoftEdgeWebview2Setup.exe /silent /install
	@echo "Done. If run-tauri-win still fails, test on real Windows/VM, or use: make run-nwjs-win"

# ---- open: reveal build outputs in the file manager ----------------------
open-tauri: ## Open the Linux Tauri installers folder
	@[ -d "$(LINUX_BUNDLE)" ] || { echo "Not built yet. Run: make tauri"; exit 1; }
	$(OPEN) "$(LINUX_BUNDLE)"

open-tauri-win: ## Open the Windows Tauri installers folder
	@[ -d "$(WIN_BUNDLE)" ] || { echo "Not built yet. Run: make tauri-win"; exit 1; }
	$(OPEN) "$(WIN_BUNDLE)"

open-nwjs: ## Open the NW.js packages folder
	@[ -d "$(NWJS_OUT)" ] || { echo "Not built yet. Run: make nwjs"; exit 1; }
	$(OPEN) "$(NWJS_OUT)"

open-dist: ## Open the web bundle folder
	@[ -d "$(DIST)" ] || { echo "Not built yet. Run: make web"; exit 1; }
	$(OPEN) "$(DIST)"

open: open-tauri ## Alias for open-tauri

nwjs: web ## Build native NW.js x64 packages (Linux/macOS/Windows) -> ./out
	@for plat in linux osx win; do \
	  QBJS_TEMPLATES=templates bin/qbjs-nwjs.sh \
	    --dist "$(DIST)" --name "$(NAME)" --platform $$plat --arch x64 \
	    --nwjs-version "$(NWJS_VERSION)" --out out; \
	done
	@ls -lh out

nwjs-arm: web ## Build native NW.js ARM64 packages (Linux/macOS/Windows) -> ./out
	@for plat in linux osx win; do \
	  QBJS_TEMPLATES=templates bin/qbjs-nwjs.sh \
	    --dist "$(DIST)" --name "$(NAME)" --platform $$plat --arch arm64 \
	    --nwjs-version "$(NWJS_VERSION)" --out out; \
	done
	@ls -lh out

# ---- Electron (bundled Chromium; best installers via electron-builder) ----
electron: web ## Build a native Electron app for Linux (x64+arm64) -> ./electron-app/release
	@command -v node >/dev/null || { echo "Node not found."; exit 1; }
	QBJS_TEMPLATES=templates bin/qbjs-electron.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out electron-app --platform linux --build

electron-win: web ## Cross-build a Windows Electron installer from Linux (needs wine)
	@command -v wine >/dev/null 2>&1 || echo "Tip: install 'wine' to build the Windows installer from Linux."
	QBJS_TEMPLATES=templates bin/qbjs-electron.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out electron-win --platform win --build

electron-mac: ## macOS Electron .dmg (needs a macOS host -> use CI)
	@echo "macOS Electron .dmg must be built on macOS (electron-builder --mac)."
	@echo "Use the CI matrix (reusable-build.yml) or run 'make electron' on a Mac."

run-electron: ## Run the built Linux Electron app (AppImage)
	@a=$$(ls $(ELECTRON_OUT)/*.AppImage 2>/dev/null | head -1); \
	[ -n "$$a" ] || { echo "Not built yet. Run: make electron"; exit 1; }; \
	chmod +x "$$a"; "$$a"

open-electron: ## Open the Electron installers folder
	@[ -d "$(ELECTRON_OUT)" ] || { echo "Not built yet. Run: make electron"; exit 1; }
	$(OPEN) "$(ELECTRON_OUT)"

demo: web ## Build the sample and serve it (one command to see it run)
	@$(MAKE) serve

test: image ## Run the end-to-end pipeline test
	docker run --rm $(IMAGE):$(TAG) version
	docker run --rm -v "$(PWD)/workspace:/workspace" --user "$(UID):$(GID)" \
	  $(IMAGE):$(TAG) build bubble-universe.bas --name "Test"
	@test -f workspace/dist/index.html && echo "PASS: web bundle built"
	@rm -rf workspace/dist

clean: ## Remove build artifacts (dist, out, tauri-*, electron-*, program.js)
	rm -rf $(DIST) out tauri-app tauri-win tauri-win-arm electron-app electron-win \
	  workspace/dist workspace/*.js program.js
	@echo "Cleaned."

clean-docker: ## Remove the local Docker image
	docker rmi $(IMAGE):$(TAG) || true

push: ## Tag & push image to GHCR (requires docker login)
	docker tag $(IMAGE):$(TAG) ghcr.io/grymmjack/qbjs-docker:$(QBJS_REF)
	docker push ghcr.io/grymmjack/qbjs-docker:$(QBJS_REF)
