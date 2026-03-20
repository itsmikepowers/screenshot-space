#!/bin/bash
set -euo pipefail

# Build a distributable ZIP for Screenshot Space
# Simpler alternative to DMG - just the app bundle in a zip

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
VERSION="${VERSION:-1.0.0}"
ZIP_OUTPUT="${BUILD_DIR}/ScreenshotSpace-${VERSION}.zip"
ICON_SOURCE="Assets/AppIcon/AppIcon.icns"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1"
    exit 1
  fi
}

require_command swift
require_command codesign
require_command zip

echo "=== Building Screenshot Space ${VERSION} (ZIP) ==="
echo ""

echo "[1/4] Compiling release build..."
swift build -c release

if [ ! -x "${BUILD_DIR}/${APP_EXECUTABLE}" ]; then
  echo "error: expected release binary at ${BUILD_DIR}/${APP_EXECUTABLE}"
  exit 1
fi

echo "[2/4] Creating app bundle..."
rm -rf "${STAGING_BUNDLE}"
mkdir -p "${STAGING_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_EXECUTABLE}" "${STAGING_BUNDLE}/Contents/MacOS/${APP_EXECUTABLE}"
cp "Info.plist" "${STAGING_BUNDLE}/Contents/"

if [ -f "${ICON_SOURCE}" ]; then
  cp "${ICON_SOURCE}" "${STAGING_BUNDLE}/Contents/Resources/AppIcon.icns"
  echo "    Bundled app icon"
else
  echo "    warning: ${ICON_SOURCE} not found; continuing without icon"
fi

echo "[3/4] Ad-hoc signing app bundle..."
codesign --force --deep --sign - "${STAGING_BUNDLE}"
codesign --verify --deep --strict "${STAGING_BUNDLE}" && echo "    Signature verified"

echo "[4/4] Creating ZIP archive..."
rm -f "${ZIP_OUTPUT}"

# Create zip from the build directory to preserve the .app structure
cd "${BUILD_DIR}"
zip -r -q "$(basename "${ZIP_OUTPUT}")" "${APP_DISPLAY_NAME}.app"
cd - > /dev/null

echo ""
echo "=== Build Complete ==="
echo ""
echo "ZIP created: ${ZIP_OUTPUT}"
echo "Size: $(du -h "${ZIP_OUTPUT}" | cut -f1)"
echo ""
echo "Installation:"
echo "  1. Unzip the archive"
echo "  2. Move 'Screenshot Space.app' to /Applications"
echo "  3. Right-click > Open on first launch"
echo ""
