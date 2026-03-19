#!/bin/bash
set -euo pipefail

# Build a distributable DMG for Screenshot Space
# Creates a styled installer with drag-to-Applications layout

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg-staging"
DMG_NAME="ScreenshotSpace"
VERSION="${VERSION:-1.0.0}"
DMG_TEMP="${BUILD_DIR}/${DMG_NAME}-${VERSION}-temp.dmg"
DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}-${VERSION}.dmg"
ICON_SOURCE="Assets/AppIcon.icns"
VOL_NAME="${APP_DISPLAY_NAME}"

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
fi

echo "[3/5] Ad-hoc signing app bundle..."
codesign --force --deep --sign - "${STAGING_BUNDLE}"
codesign --verify --deep --strict "${STAGING_BUNDLE}" && echo "    Signature verified"

echo "[4/5] Preparing DMG contents..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${STAGING_BUNDLE}" "${DMG_DIR}/"
# Don't create symlink here - we'll create an alias via AppleScript

echo "[5/5] Creating DMG..."
rm -f "${DMG_TEMP}" "${DMG_OUTPUT}"

# Create a read-write DMG first (needs to be big enough)
hdiutil create -srcfolder "${DMG_DIR}" -volname "${VOL_NAME}" -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" -format UDRW -size 10m "${DMG_TEMP}"

# Mount it
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_TEMP}" | egrep '^/dev/' | sed 1q | awk '{print $1}')
echo "    Mounted device: ${DEVICE}"

sleep 2

# Use AppleScript to set up the Finder window and create Applications alias
echo "    Configuring Finder view..."
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 600, 400}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background color of theViewOptions to {8738, 8738, 8738}
        
        -- Create alias to Applications folder (this shows the proper icon)
        make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
        
        set position of item "${APP_DISPLAY_NAME}.app" of container window to {125, 150}
        set position of item "Applications" of container window to {375, 150}
        
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

# Set permissions and sync
chmod -Rf go-w "/Volumes/${VOL_NAME}"
sync
sync

# Unmount
hdiutil detach "${DEVICE}"

# Convert to compressed read-only DMG
hdiutil convert "${DMG_TEMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_OUTPUT}"
rm -f "${DMG_TEMP}"
rm -rf "${DMG_DIR}"

echo ""
echo "=== Build Complete ==="
echo ""
echo "DMG created: ${DMG_OUTPUT}"
echo "Size: $(du -h "${DMG_OUTPUT}" | cut -f1)"
echo ""
