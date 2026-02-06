#!/bin/bash
set -e

APP_NAME="ScreenshotSpace"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
SIGN_IDENTITY="ScreenshotSpace Developer"

echo "Building Screenshot Space..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist "$APP_BUNDLE/Contents/"
cp Assets/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"

echo "Signing with identity: ${SIGN_IDENTITY}..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo ""
echo "Build complete: ${APP_BUNDLE}"
echo ""
echo "To run:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "To install (copy to Applications):"
echo "  cp -r ${APP_BUNDLE} /Applications/"
