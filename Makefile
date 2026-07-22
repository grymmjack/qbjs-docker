.PHONY: help image build web serve compile tauri tauri-deps tauri-win tauri-win-deps tauri-mac tauri-all nwjs demo test clean clean-docker push

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

# Package the compiler next to the QBJS runtime for host-side script runs.
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

WIN_TARGET := x86_64-pc-windows-msvc

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

tauri-win: web tauri-win-deps ## Cross-compile a Windows Tauri .exe/.msi from Linux (cargo-xwin)
	@command -v cargo >/dev/null || { echo "Rust not found. Install: https://rustup.rs"; exit 1; }
	QBJS_TEMPLATES=templates bin/qbjs-tauri.sh \
	  --dist "$(DIST)" --name "$(NAME)" --out tauri-win --target $(WIN_TARGET) --build

tauri-mac: ## macOS build (cannot cross-compile from Linux -- use CI)
	@echo "macOS binaries cannot be built from Linux (Apple SDK + signing are macOS-only)."
	@echo "Use the CI matrix: push a tag and reusable-build.yml builds the .dmg on a macos runner,"
	@echo "exactly like your DRAW build-release.yml does. Or run 'make tauri' on a Mac."

tauri-all: tauri tauri-win ## Build every target buildable locally (Linux + Windows); macOS via CI
	@echo "Built Linux + Windows locally. macOS -> CI (see 'make tauri-mac')."

nwjs: web ## Build native NW.js packages (all platforms) -> ./out
	@for plat in linux osx win; do \
	  QBJS_TEMPLATES=templates bin/qbjs-nwjs.sh \
	    --dist "$(DIST)" --name "$(NAME)" --platform $$plat \
	    --nwjs-version "$(NWJS_VERSION)" --out out; \
	done
	@ls -lh out

demo: web ## Build the sample and serve it (one command to see it run)
	@$(MAKE) serve

test: image ## Run the end-to-end pipeline test
	docker run --rm $(IMAGE):$(TAG) version
	docker run --rm -v "$(PWD)/workspace:/workspace" --user "$(UID):$(GID)" \
	  $(IMAGE):$(TAG) build bubble-universe.bas --name "Test"
	@test -f workspace/dist/index.html && echo "PASS: web bundle built"
	@rm -rf workspace/dist

clean: ## Remove build artifacts (dist, out, tauri-app, program.js)
	rm -rf $(DIST) out tauri-app workspace/dist workspace/*.js program.js
	@echo "Cleaned."

clean-docker: ## Remove the local Docker image
	docker rmi $(IMAGE):$(TAG) || true

push: ## Tag & push image to GHCR (requires docker login)
	docker tag $(IMAGE):$(TAG) ghcr.io/grymmjack/qbjs-docker:$(QBJS_REF)
	docker push ghcr.io/grymmjack/qbjs-docker:$(QBJS_REF)
