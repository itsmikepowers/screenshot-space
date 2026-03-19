#!/bin/bash
set -euo pipefail

# Build a distributable DMG for Screenshot Space
# This creates an unsigned (ad-hoc signed) app bundle that can be shared directly

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_NAME="ScreenshotSpace"
VERSION="${VERSION:-1.0.0}"
DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}-${VERSION}.dmg"
ICON_SOURCE="Assets/AppIcon.icns"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1"
    exit 1
  fi
}

require_command swift
require_command codesign
require_command hdiutil

echo "=== Building Screenshot Space ${VERSION} ==="
echo ""

echo "[1/5] Compiling release build..."
swift build -c release

if [ ! -x "${BUILD_DIR}/${APP_EXECUTABLE}" ]; then
  echo "error: expected release binary at ${BUILD_DIR}/${APP_EXECUTABLE}"
  exit 1
fi

echo "[2/5] Creating app bundle..."
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

echo "[3/5] Ad-hoc signing app bundle..."
# Ad-hoc signing (-) works without a developer certificate
# Users will need to right-click > Open on first launch to bypass Gatekeeper
codesign --force --deep --sign - "${STAGING_BUNDLE}"
codesign --verify --deep --strict "${STAGING_BUNDLE}" && echo "    Signature verified"

echo "[4/5] Preparing DMG contents..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${STAGING_BUNDLE}" "${DMG_DIR}/"

# Create a symbolic link to /Applications for drag-and-drop install
ln -s /Applications "${DMG_DIR}/Applications"

# Create a simple README for the DMG
cat > "${DMG_DIR}/README.txt" << 'EOF'
Screenshot Space - Installation

1. Drag "Screenshot Space" to the Applications folder
2. Open the app from Applications
3. On first launch, you may need to:
   - Right-click the app and select "Open"
   - Click "Open" in the security dialog
4. Grant Accessibility permission when prompted
   (Required for the global hotkey to work)

Usage:
- Tap Option key: Full-screen screenshot
- Hold Option key: Drag to select region

Troubleshooting:
If the hotkey doesn't work, go to:
System Settings > Privacy & Security > Accessibility
and ensure Screenshot Space is enabled.

More info: https://github.com/itsmikepowers/screenshot-space
EOF

echo "[5/5] Creating DMG..."
rm -f "${DMG_OUTPUT}"

# Create DMG with hdiutil
hdiutil create \
  -volname "${APP_DISPLAY_NAME}" \
  -srcfolder "${DMG_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_OUTPUT}"

# Clean up staging
rm -rf "${DMG_DIR}"

echo ""
echo "=== Build Complete ==="
echo ""
echo "DMG created: ${DMG_OUTPUT}"
echo "Size: $(du -h "${DMG_OUTPUT}" | cut -f1)"
echo ""
echo "Distribution notes:"
echo "  - This is ad-hoc signed (no Apple Developer certificate)"
echo "  - Users will need to right-click > Open on first launch"
echo "  - Or: System Settings > Privacy & Security > Open Anyway"
echo ""
