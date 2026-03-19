#!/bin/bash
set -euo pipefail

# Build a distributable DMG: app + Applications alias (drag to install)

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
DMG_NAME="ScreenshotSpace"
VERSION="${VERSION:-1.0.0}"
DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}-${VERSION}.dmg"
ICON_SOURCE="Assets/AppIcon.icns"
FOLDER_ICON="Assets/FolderIcon.icns"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1"
    echo "Install with: $2"
    exit 1
  fi
}

require_command swift "xcode-select --install"
require_command codesign "xcode-select --install"
require_command fileicon "brew install fileicon"

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

echo "[4/5] Creating DMG..."
rm -f "${DMG_OUTPUT}"
TEMP_DMG="${BUILD_DIR}/temp-${DMG_NAME}.dmg"
rm -f "${TEMP_DMG}"

STAGING_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -R "${STAGING_BUNDLE}" "${STAGING_DIR}/"

hdiutil create -volname "${APP_DISPLAY_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDRW "${TEMP_DMG}"

MOUNT_POINT=$(hdiutil attach "${TEMP_DMG}" -readwrite -noverify -noautoopen | grep "/Volumes/" | awk -F'\t' '{print $NF}')
echo "    Mounted at: ${MOUNT_POINT}"

echo "[5/5] Configuring DMG layout..."

osascript <<EOF
tell application "Finder"
    set targetFolder to POSIX file "/Applications" as alias
    set dmgVolume to POSIX file "${MOUNT_POINT}" as alias
    make new alias file at dmgVolume to targetFolder with properties {name:"Applications"}
end tell
EOF
echo "    Created Applications alias"

if [ -f "${FOLDER_ICON}" ]; then
  fileicon set "${MOUNT_POINT}/Applications" "${FOLDER_ICON}" && echo "    Set folder icon"
fi

mkdir -p "${MOUNT_POINT}/.background"
if [ -f "Assets/dmg-background.png" ]; then
  cp "Assets/dmg-background.png" "${MOUNT_POINT}/.background/background.png"
  echo "    Copied background image"
fi

osascript <<EOF
tell application "Finder"
    tell disk "${APP_DISPLAY_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 740, 400}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        try
            set background picture of viewOptions to file ".background:background.png"
        end try
        set position of item "${APP_DISPLAY_NAME}.app" to {135, 100}
        set position of item "Applications" to {405, 100}
        close
        open
        close
    end tell
end tell
EOF
echo "    Configured window layout"

sync
sleep 2
hdiutil detach "${MOUNT_POINT}" -quiet

hdiutil convert "${TEMP_DMG}" -format UDBZ -o "${DMG_OUTPUT}"
rm -f "${TEMP_DMG}"
rm -rf "${STAGING_DIR}"

echo ""
echo "=== Build Complete ==="
echo ""
echo "DMG created: ${DMG_OUTPUT}"
echo "Size: $(du -h "${DMG_OUTPUT}" | cut -f1)"
echo ""
