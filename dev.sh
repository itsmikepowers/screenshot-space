#!/bin/bash
set -euo pipefail

APP_EXECUTABLE="ScreenshotSpace"
APP_DISPLAY_NAME="Screenshot Space"
BUILD_DIR=".build/debug"
DEV_BUNDLE="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
ICON_SOURCE="Assets/AppIcon.icns"

# Check for fswatch
if ! command -v fswatch &>/dev/null; then
    echo "Error: fswatch is not installed."
    echo "Install it with: brew install fswatch"
    exit 1
fi

build_and_run() {
    echo ""
    echo "=== Building (debug)... ==="

    # Kill the running instance if any
    pkill -x "${APP_EXECUTABLE}" 2>/dev/null || true
    sleep 0.3

    # Build in debug mode (faster than release)
    if ! swift build 2>&1; then
        echo "=== Build failed ==="
        return 1
    fi

    # Create minimal app bundle (no codesigning for dev)
    rm -rf "${DEV_BUNDLE}"
    mkdir -p "${DEV_BUNDLE}/Contents/MacOS"
    mkdir -p "${DEV_BUNDLE}/Contents/Resources"

    cp "${BUILD_DIR}/${APP_EXECUTABLE}" "${DEV_BUNDLE}/Contents/MacOS/${APP_EXECUTABLE}"
    cp "Info.plist" "${DEV_BUNDLE}/Contents/"

    if [ -f "${ICON_SOURCE}" ]; then
        cp "${ICON_SOURCE}" "${DEV_BUNDLE}/Contents/Resources/AppIcon.icns"
    fi

    # Ad-hoc sign (required for Accessibility permissions in dev)
    codesign --force --deep --sign - "${DEV_BUNDLE}"

    echo "=== Launching... ==="
    open "${DEV_BUNDLE}" &

    echo "=== Ready. Watching for changes... ==="
}

# Initial build and run
build_and_run

# Watch Sources/ for changes and rebuild
fswatch -o -l 0.5 --exclude '.*\.build.*' --exclude '.*\.git.*' Sources/ Info.plist | while read -r _; do
    # Debounce: drain any additional events that arrived
    while read -r -t 0.3 _; do :; done
    build_and_run
done
