#!/bin/bash
set -euo pipefail

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/release"
STAGING_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
INSTALL_PATH="/Applications/${APP_DISPLAY_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Michael Powers (83955LP5FK)}"
ICON_SOURCE="Assets/AppIcon.icns"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1"
    exit 1
  fi
}

require_command swift
require_command security
require_command codesign
require_command spctl
require_command rg

echo "Checking signing identity: ${SIGN_IDENTITY}"
if ! security find-identity -v -p codesigning | rg -F "${SIGN_IDENTITY}" >/dev/null; then
  echo "error: signing identity '${SIGN_IDENTITY}' was not found."
  echo "Create or install it first, then re-run this script."
  echo "See docs/SIGNING.md for the supported local signing workflow."
  exit 1
fi

echo "Building Screenshot Space..."
swift build -c release

if [ ! -x "${BUILD_DIR}/${APP_EXECUTABLE}" ]; then
  echo "error: expected release binary at ${BUILD_DIR}/${APP_EXECUTABLE}"
  exit 1
fi

echo "Creating app bundle at ${STAGING_BUNDLE}..."
rm -rf "${STAGING_BUNDLE}"
mkdir -p "${STAGING_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_EXECUTABLE}" "${STAGING_BUNDLE}/Contents/MacOS/${APP_EXECUTABLE}"
cp "Info.plist" "${STAGING_BUNDLE}/Contents/"

if [ -f "${ICON_SOURCE}" ]; then
  cp "${ICON_SOURCE}" "${STAGING_BUNDLE}/Contents/Resources/AppIcon.icns"
else
  echo "warning: ${ICON_SOURCE} not found; continuing without a bundled app icon."
fi

echo "Signing app bundle..."
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" "${STAGING_BUNDLE}"

echo "Verifying staged bundle signature..."
codesign --verify --deep --strict --verbose=2 "${STAGING_BUNDLE}"
codesign -dv --verbose=4 "${STAGING_BUNDLE}"

echo "Assessing staged bundle with Gatekeeper..."
if ! spctl --assess --type execute --verbose=4 "${STAGING_BUNDLE}"; then
  echo "warning: spctl rejected the staged app bundle."
  echo "The signature is still printed above, but you should fix trust/notarization before distributing beyond local development."
fi

if [ ! -w "/Applications" ]; then
  echo "error: this script needs write access to /Applications."
  echo "Run it from an admin account or adjust permissions before installing."
  exit 1
fi

echo "Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${STAGING_BUNDLE}" "${INSTALL_PATH}"

echo "Verifying installed bundle..."
codesign --verify --deep --strict --verbose=2 "${INSTALL_PATH}"
codesign -dv --verbose=4 "${INSTALL_PATH}"

echo "Assessing installed bundle with Gatekeeper..."
if ! spctl --assess --type execute --verbose=4 "${INSTALL_PATH}"; then
  echo "warning: spctl rejected the installed app bundle."
  echo "The app still has a stable signed identity for local TCC testing, but Gatekeeper trust needs more work."
fi

echo ""
echo "Installed successfully: ${INSTALL_PATH}"
echo "Grant Accessibility access to that installed app bundle, then launch it with:"
echo "  open \"${INSTALL_PATH}\""
