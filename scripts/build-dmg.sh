#!/bin/bash
set -euo pipefail

# Build a distributable DMG: app + installer + Applications alias

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
INSTALLER_EXECUTABLE="ScreenshotSpaceInstaller"
INSTALLER_DISPLAY_NAME="Install Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
INSTALLER_BUNDLE="${BUILD_DIR}/${INSTALLER_DISPLAY_NAME}.app"
DMG_NAME="ScreenshotSpace"
VERSION="${VERSION:-1.0.0}"
DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}-${VERSION}.dmg"
ICON_SOURCE="Assets/AppIcon/AppIcon.icns"
FOLDER_ICON="Assets/DMG/FolderIcon.icns"

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

echo "[1/7] Compiling release build..."
swift build -c release

if [ ! -x "${BUILD_DIR}/${APP_EXECUTABLE}" ]; then
  echo "error: expected release binary at ${BUILD_DIR}/${APP_EXECUTABLE}"
  exit 1
fi

if [ ! -x "${BUILD_DIR}/${INSTALLER_EXECUTABLE}" ]; then
  echo "error: expected installer binary at ${BUILD_DIR}/${INSTALLER_EXECUTABLE}"
  exit 1
fi

echo "[2/7] Creating main app bundle..."
rm -rf "${STAGING_BUNDLE}"
mkdir -p "${STAGING_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_EXECUTABLE}" "${STAGING_BUNDLE}/Contents/MacOS/${APP_EXECUTABLE}"
cp "Info.plist" "${STAGING_BUNDLE}/Contents/"

if [ -f "${ICON_SOURCE}" ]; then
  cp "${ICON_SOURCE}" "${STAGING_BUNDLE}/Contents/Resources/AppIcon.icns"
  echo "    Bundled app icon"
fi

echo "[3/7] Creating installer app bundle..."
rm -rf "${INSTALLER_BUNDLE}"
mkdir -p "${INSTALLER_BUNDLE}/Contents/MacOS"
mkdir -p "${INSTALLER_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${INSTALLER_EXECUTABLE}" "${INSTALLER_BUNDLE}/Contents/MacOS/${INSTALLER_EXECUTABLE}"
cp "InstallerSources/Info.plist" "${INSTALLER_BUNDLE}/Contents/"

if [ -f "${ICON_SOURCE}" ]; then
  cp "${ICON_SOURCE}" "${INSTALLER_BUNDLE}/Contents/Resources/AppIcon.icns"
  echo "    Bundled installer icon"
fi

echo "[4/7] Ad-hoc signing app bundles..."
codesign --force --deep --sign - "${STAGING_BUNDLE}"
codesign --verify --deep --strict "${STAGING_BUNDLE}" && echo "    Main app signature verified"

codesign --force --deep --sign - "${INSTALLER_BUNDLE}"
codesign --verify --deep --strict "${INSTALLER_BUNDLE}" && echo "    Installer signature verified"

echo "[5/7] Creating DMG..."
rm -f "${DMG_OUTPUT}"
TEMP_DMG="${BUILD_DIR}/temp-${DMG_NAME}.dmg"
rm -f "${TEMP_DMG}"

STAGING_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -R "${STAGING_BUNDLE}" "${STAGING_DIR}/"
cp -R "${INSTALLER_BUNDLE}" "${STAGING_DIR}/"

hdiutil create -volname "${APP_DISPLAY_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDRW "${TEMP_DMG}"

MOUNT_POINT=$(hdiutil attach "${TEMP_DMG}" -readwrite -noverify -noautoopen | grep "/Volumes/" | awk -F'\t' '{print $NF}')
echo "    Mounted at: ${MOUNT_POINT}"

echo "[6/7] Configuring DMG layout..."

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
if [ -f "Assets/DMG/dmg-background.png" ]; then
  cp "Assets/DMG/dmg-background.png" "${MOUNT_POINT}/.background/background.png"
  echo "    Copied background image"
fi

echo "[7/7] Setting window layout..."
osascript <<EOF
tell application "Finder"
    tell disk "${APP_DISPLAY_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 820, 420}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        try
            set background picture of viewOptions to file ".background:background.png"
        end try
        set position of item "${APP_DISPLAY_NAME}.app" to {135, 120}
        set position of item "${INSTALLER_DISPLAY_NAME}.app" to {310, 120}
        set position of item "Applications" to {485, 120}
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
echo "Contents:"
echo "  - ${APP_DISPLAY_NAME}.app (drag to Applications)"
echo "  - ${INSTALLER_DISPLAY_NAME}.app (guided installer)"
echo ""
