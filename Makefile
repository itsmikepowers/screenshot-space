# Screenshot Space - Build & Distribution
# 
# Usage:
#   make build      - Build and install locally (requires signing identity)
#   make dmg        - Create distributable DMG (ad-hoc signed)
#   make zip        - Create distributable ZIP (ad-hoc signed)
#   make release    - Create both DMG and ZIP
#   make clean      - Remove build artifacts

VERSION ?= 1.0.13
SHELL := /bin/bash

.PHONY: build dev dmg zip release clean help

help:
	@echo "Screenshot Space Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make dev        Start dev mode (auto-rebuild on save)"
	@echo "  make build      Build and install to /Applications (signed)"
	@echo "  make dmg        Create distributable DMG"
	@echo "  make zip        Create distributable ZIP"
	@echo "  make release    Create both DMG and ZIP"
	@echo "  make clean      Remove build artifacts"
	@echo ""
	@echo "Options:"
	@echo "  VERSION=x.y.z   Set version number (default: $(VERSION))"
	@echo ""
	@echo "Examples:"
	@echo "  make dmg VERSION=1.2.0"
	@echo "  make release VERSION=2.0.0"

dev:
	@./dev.sh

build:
	@./build.sh

dmg:
	@chmod +x scripts/build-dmg.sh
	@VERSION=$(VERSION) ./scripts/build-dmg.sh

zip:
	@chmod +x scripts/build-zip.sh
	@VERSION=$(VERSION) ./scripts/build-zip.sh

release: dmg zip
	@echo ""
	@echo "=== Release $(VERSION) Ready ==="
	@echo ""
	@ls -lh .build/release/ScreenshotSpace-$(VERSION).*
	@echo ""
	@echo "Upload these files to your GitHub release or share directly."

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build
	@echo "Done."
