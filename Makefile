# Kiln Makefile
# All targets degrade gracefully: missing tools produce a clear message with install hints,
# not a stack trace. Target list: setup, test, build, run, package, distill, video, clean.

SHELL := /usr/bin/env bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

PYTHON ?= python3
UV     ?= uv
SWIFT  ?= swift

APP_NAME := Kiln
APP_BUNDLE := apps/$(APP_NAME)/build/Build/Products/Release/$(APP_NAME).app

# --- help ---------------------------------------------------------------

.PHONY: help
help:
	@echo "Kiln — available targets:"
	@echo "  setup          Install Python sidecar deps (via uv), verify Xcode is present"
	@echo "  test           Run Swift tests + Python pytest"
	@echo "  build          Release build of the Kiln.app and the sidecar"
	@echo "  run            Launch the built app"
	@echo "  design-lint    Validate /DESIGN.md via @google/design.md"
	@echo "  design-export  Regenerate docs/design/tokens.dtcg.json"
	@echo "  package        Build a distributable .dmg (not signed)"
	@echo "  distill        Shortcut: python scripts/opus-distill/run.py --help"
	@echo "  demo-check     End-to-end North-Star Demo sanity (<5 min, skips unimplemented)"
	@echo "  video          Shortcut: open docs/demo/README.md in the editor"
	@echo "  clean          Remove build artifacts and caches"

# --- setup --------------------------------------------------------------

.PHONY: setup
setup:
	@command -v $(UV) >/dev/null 2>&1 || { \
	  echo "!! uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
	@command -v $(SWIFT) >/dev/null 2>&1 || { \
	  echo "!! swift not found. Install Xcode or Xcode CLT: xcode-select --install"; exit 1; }
	cd packages/kiln_trainer && $(UV) sync --group dev
	@if command -v xcodegen >/dev/null 2>&1; then \
	  (cd apps/Kiln && xcodegen generate); \
	else \
	  echo "!! xcodegen not found. Install: brew install xcodegen"; \
	fi

# --- test ---------------------------------------------------------------

.PHONY: test
test: test-swift test-python
	@echo "ok" > .kiln-last-test-status

.PHONY: test-swift
test-swift:
	@if command -v $(SWIFT) >/dev/null 2>&1 && [ -d packages/KilnCore ] && [ -f packages/KilnCore/Package.swift ]; then \
	  cd packages/KilnCore && $(SWIFT) test; \
	else \
	  echo "(skipping swift tests — KilnCore package not initialized yet)"; \
	fi

.PHONY: test-python
test-python:
	@if [ -d packages/kiln_trainer/tests ] && command -v $(UV) >/dev/null 2>&1; then \
	  cd packages/kiln_trainer && $(UV) run --group dev pytest -q; \
	else \
	  echo "(skipping python tests — kiln_trainer tests not initialized yet)"; \
	fi

# --- build --------------------------------------------------------------

.PHONY: build
build: build-swift build-app
	@echo "build complete"

.PHONY: build-swift
build-swift:
	@if command -v $(SWIFT) >/dev/null 2>&1; then \
	  if [ -d packages/KilnCore ] && [ -f packages/KilnCore/Package.swift ]; then \
	    cd packages/KilnCore && $(SWIFT) build -c release; \
	  else \
	    echo "(skipping swift build — KilnCore package not initialized yet)"; \
	  fi; \
	else \
	  echo "!! swift not found. See: xcode-select --install"; exit 1; \
	fi

.PHONY: build-app
build-app:
	@if [ ! -f apps/Kiln/project.yml ]; then \
	  echo "(skipping Kiln.app build — apps/Kiln/project.yml not present)"; \
	elif ! command -v xcodegen >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then \
	  echo "(skipping Kiln.app build — xcodegen or xcodebuild not on PATH)"; \
	else \
	  (cd apps/Kiln && xcodegen generate >/dev/null); \
	  xcodebuild -project apps/Kiln/Kiln.xcodeproj -scheme Kiln \
	             -configuration Release -destination 'platform=macOS' \
	             -derivedDataPath apps/Kiln/build \
	             CODE_SIGNING_ALLOWED=NO build \
	             -quiet; \
	fi

# --- design (DESIGN.md) -------------------------------------------------

.PHONY: design-lint
design-lint:
	@if ! command -v npx >/dev/null 2>&1; then \
	  echo "(skipping design-lint — npx not on PATH. Install Node.js to enable.)"; \
	  exit 0; \
	fi
	@if [ ! -d node_modules/@google/design.md ]; then \
	  echo "(installing @google/design.md — run 'npm install' to make this quiet)"; \
	  npm install --silent >/dev/null 2>&1; \
	fi
	@npx design.md lint DESIGN.md

.PHONY: design-export
design-export:
	@if ! command -v npx >/dev/null 2>&1; then \
	  echo "!! npx not on PATH. Install Node.js first."; exit 1; \
	fi
	@if [ ! -d node_modules/@google/design.md ]; then \
	  npm install --silent >/dev/null 2>&1; \
	fi
	@npx design.md export --format dtcg DESIGN.md > docs/design/tokens.dtcg.json
	@echo "wrote docs/design/tokens.dtcg.json"

# --- run ----------------------------------------------------------------

.PHONY: run
run:
	@if [ -d "$(APP_BUNDLE)" ]; then \
	  open "$(APP_BUNDLE)"; \
	else \
	  echo "!! $(APP_BUNDLE) missing. Run 'make build' first."; exit 1; \
	fi

# --- package ------------------------------------------------------------

.PHONY: package
package: build
	@echo "(package target not yet implemented — see M10 in SPEC.md)"

# --- distill ------------------------------------------------------------

.PHONY: distill
distill:
	@$(PYTHON) scripts/opus-distill/run.py --help || \
	  echo "!! scripts/opus-distill/run.py not executable yet"

# --- demo-check ---------------------------------------------------------

.PHONY: demo-check
demo-check:
	@$(PYTHON) scripts/demo-check.py \
	  --budget-seconds 300 \
	  --out .kiln-demo-check.json

# --- video --------------------------------------------------------------

.PHONY: video
video:
	@echo "See .claude/skills/kiln-demo-recording/SKILL.md"
	@echo "Raw takes: docs/demo/raw/   Final cut: docs/demo/final.mp4"

# --- clean --------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf build/ DerivedData/ .build/ \
	       apps/Kiln/build apps/Kiln/Kiln.xcodeproj \
	       packages/KilnCore/.build packages/KilnCore/.swiftpm \
	       packages/kiln_trainer/.venv packages/kiln_trainer/__pycache__ \
	       .ruff_cache .pytest_cache .mypy_cache \
	       .kiln-last-test-status .kiln-demo-check.json
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "cleaned"
