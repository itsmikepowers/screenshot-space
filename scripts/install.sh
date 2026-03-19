#!/bin/bash
set -euo pipefail

# One-line installer for Screenshot Space
# Usage: curl -fsSL https://raw.githubusercontent.com/itsmikepowers/screenshot-space/main/scripts/install.sh | bash

APP_NAME="Screenshot Space"
INSTALL_PATH="/Applications/${APP_NAME}.app"
REPO="itsmikepowers/screenshot-space"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo ""
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     Screenshot Space Installer        ║"
echo "  ╚═══════════════════════════════════════╝"
echo ""

# Check macOS version
macos_version=$(sw_vers -productVersion)
major_version=$(echo "${macos_version}" | cut -d. -f1)
if [ "${major_version}" -lt 13 ]; then
  echo "error: Screenshot Space requires macOS 13.0 or later"
  echo "       You have macOS ${macos_version}"
  exit 1
fi
echo "✓ macOS ${macos_version} detected"

# Check for existing installation
if [ -d "${INSTALL_PATH}" ]; then
  echo ""
  echo "Existing installation found at ${INSTALL_PATH}"
  read -p "Replace it? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
fi

# Determine latest release or use main branch
echo ""
echo "Fetching latest version..."

# Try to get latest release, fall back to main branch
DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/heads/main.zip"
echo "Downloading from: ${DOWNLOAD_URL}"

cd "${TMP_DIR}"
curl -fsSL -o repo.zip "${DOWNLOAD_URL}"
unzip -q repo.zip
cd screenshot-space-main

echo ""
echo "Building Screenshot Space..."
echo "(This may take a minute on first run)"
echo ""

# Build the app
swift build -c release 2>&1 | while read -r line; do
  # Show progress without overwhelming output
  if [[ "$line" == *"Compiling"* ]] || [[ "$line" == *"Linking"* ]] || [[ "$line" == *"Build complete"* ]]; then
    echo "  $line"
  fi
done

# Create app bundle
APP_BUNDLE="${TMP_DIR}/Screenshot Space.app"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/ScreenshotSpace" "${APP_BUNDLE}/Contents/MacOS/ScreenshotSpace"
cp "Info.plist" "${APP_BUNDLE}/Contents/"

if [ -f "Assets/AppIcon.icns" ]; then
  cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign
echo ""
echo "Signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# Install
echo ""
echo "Installing to ${INSTALL_PATH}..."
if [ -d "${INSTALL_PATH}" ]; then
  rm -rf "${INSTALL_PATH}"
fi
cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"

echo ""
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     Installation Complete! 🎉         ║"
echo "  ╚═══════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "  1. Open the app:"
echo "     open \"/Applications/Screenshot Space.app\""
echo ""
echo "  2. On first launch, you may see a security warning."
echo "     Go to System Settings > Privacy & Security"
echo "     and click 'Open Anyway'"
echo ""
echo "  3. Grant Accessibility permission when prompted"
echo "     (Required for the Option key hotkey)"
echo ""
echo "Usage:"
echo "  • Tap Option key  → Full-screen screenshot"
echo "  • Hold Option key → Drag to select region"
echo ""
