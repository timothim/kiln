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
APP_BUNDLE := apps/$(APP_NAME)/build/Release/$(APP_NAME).app

# --- help ---------------------------------------------------------------

.PHONY: help
help:
	@echo "Kiln — available targets:"
	@echo "  setup     Install Python sidecar deps (via uv), verify Xcode is present"
	@echo "  test      Run Swift tests + Python pytest"
	@echo "  build     Release build of the Kiln.app and the sidecar"
	@echo "  run       Launch the built app"
	@echo "  package   Build a distributable .dmg (not signed)"
	@echo "  distill   Shortcut: python scripts/opus-distill/run.py --help"
	@echo "  video     Shortcut: open docs/demo/README.md in the editor"
	@echo "  clean     Remove build artifacts and caches"

# --- setup --------------------------------------------------------------

.PHONY: setup
setup:
	@command -v $(UV) >/dev/null 2>&1 || { \
	  echo "!! uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
	@command -v $(SWIFT) >/dev/null 2>&1 || { \
	  echo "!! swift not found. Install Xcode or Xcode CLT: xcode-select --install"; exit 1; }
	$(UV) venv --python 3.11 packages/kiln_trainer/.venv
	cd packages/kiln_trainer && $(UV) pip sync requirements.txt || \
	  echo "!! requirements.txt not found yet — populated at M1"

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
	@if command -v $(PYTHON) >/dev/null 2>&1 && [ -d packages/kiln_trainer/tests ]; then \
	  cd packages/kiln_trainer && $(PYTHON) -m pytest -q; \
	else \
	  echo "(skipping python tests — kiln_trainer tests not initialized yet)"; \
	fi

# --- build --------------------------------------------------------------

.PHONY: build
build: build-swift
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

# --- video --------------------------------------------------------------

.PHONY: video
video:
	@echo "See .claude/skills/kiln-demo-recording/SKILL.md"
	@echo "Raw takes: docs/demo/raw/   Final cut: docs/demo/final.mp4"

# --- clean --------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf build/ DerivedData/ .build/ \
	       packages/KilnCore/.build packages/KilnCore/.swiftpm \
	       packages/kiln_trainer/.venv packages/kiln_trainer/__pycache__ \
	       .ruff_cache .pytest_cache .mypy_cache \
	       .kiln-last-test-status
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "cleaned"
