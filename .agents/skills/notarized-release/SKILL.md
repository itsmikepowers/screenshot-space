---
name: notarized-release
description: Build, sign, notarize, and ship a new version. Use when the user says "release X.Y.Z", "notarized build", "ship version", "push new release", or similar. Requires a version number.
---

# Notarized Release

Build a fully signed and Apple-notarized release, then commit and push to GitHub.

## Prerequisites

- **Developer ID Application** certificate in Keychain (verify: `security find-identity -v -p codesigning`)
- **Notarytool keychain profile** named `notary-screenshot-space` (created via `xcrun notarytool store-credentials`)
- Current signing identity: `Developer ID Application: Michael Powers (83955LP5FK)`

## Input

The user provides a **version number** (e.g. `1.0.12`). If not provided, ask for it.

## Steps

Run these steps in order. Stop and report if any step fails.

### 1. Bump version in all files

Update these files, replacing the old version with the new one:

- `Info.plist`: both `CFBundleVersion` and `CFBundleShortVersionString`
- `Makefile`: the `VERSION ?=` line
- `README.md`: the DMG download link `ScreenshotSpace-X.Y.Z.dmg`

### 2. Build release binary

```bash
swift build -c release
```

### 3. Create app bundle

```bash
APP_BUNDLE=".build/release/Screenshot Space.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp .build/release/ScreenshotSpace "$APP_BUNDLE/Contents/MacOS/ScreenshotSpace"
cp Info.plist "$APP_BUNDLE/Contents/"
if [ -f "Assets/AppIcon/AppIcon.icns" ]; then
  cp "Assets/AppIcon/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
```

### 4. Sign with Developer ID + hardened runtime

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Michael Powers (83955LP5FK)" \
  "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
```

### 5. Create ZIP and submit for notarization

```bash
rm -f /tmp/ScreenshotSpace-notarize.zip
ditto -c -k --keepParent "$APP_BUNDLE" /tmp/ScreenshotSpace-notarize.zip

xcrun notarytool submit /tmp/ScreenshotSpace-notarize.zip \
  --keychain-profile "notary-screenshot-space" \
  --wait
```

This typically takes 1-5 minutes. Wait for `status: Accepted`.

### 6. Staple the notarization ticket

```bash
xcrun stapler staple "$APP_BUNDLE"
```

### 7. Verify with Gatekeeper

```bash
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
```

Should show `source=Notarized Developer ID`.

### 8. Build DMG from notarized app

```bash
VERSION="X.Y.Z"  # use the version from input
DMG_OUTPUT=".build/release/ScreenshotSpace-${VERSION}.dmg"
STAGING_DIR=".build/release/dmg-staging"

rm -rf "$STAGING_DIR" "$DMG_OUTPUT" /tmp/temp-notarized.dmg
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

hdiutil create -volname "Screenshot Space" -srcfolder "$STAGING_DIR" -ov -format UDRW /tmp/temp-notarized.dmg

MOUNT_POINT=$(hdiutil attach /tmp/temp-notarized.dmg -readwrite -noverify -noautoopen | grep "/Volumes/" | awk -F'\t' '{print $NF}')
ln -s /Applications "$MOUNT_POINT/Applications"

if [ -f "Assets/DMG/FolderIcon.icns" ]; then
  fileicon set "$MOUNT_POINT/Applications" "Assets/DMG/FolderIcon.icns" 2>/dev/null || true
fi

mkdir -p "$MOUNT_POINT/.background"
if [ -f "Assets/DMG/dmg-background.png" ]; then
  cp "Assets/DMG/dmg-background.png" "$MOUNT_POINT/.background/background.png"
fi

sleep 1
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert /tmp/temp-notarized.dmg -format UDBZ -o "$DMG_OUTPUT"
rm -f /tmp/temp-notarized.dmg
rm -rf "$STAGING_DIR"
```

### 9. Update releases folder

```bash
# Remove old DMG(s) and copy new one
git rm -f releases/ScreenshotSpace-*.dmg 2>/dev/null || true
cp "$DMG_OUTPUT" releases/ScreenshotSpace-${VERSION}.dmg
```

### 10. Commit and push

Stage all changed files and commit:

```bash
git add Info.plist Makefile README.md releases/ScreenshotSpace-${VERSION}.dmg
git commit -m "chore(release): v${VERSION} notarized build

Signed with Developer ID + hardened runtime, notarized by Apple, stapled.
"
git push origin main
```

### 11. Create and push git tag

```bash
git tag -a "v${VERSION}" -m "v${VERSION}"
git push origin "v${VERSION}"
```

## Troubleshooting

### Notarization returns "Invalid"

Run `xcrun notarytool log <SUBMISSION_ID> --keychain-profile "notary-screenshot-space"` to see the specific issues.

### DMG mount fails with "already an item with that name"

Stale volumes are mounted. Eject them first:

```bash
hdiutil detach "/Volumes/Screenshot Space" -force 2>/dev/null || true
hdiutil detach "/Volumes/Screenshot Space 1" -force 2>/dev/null || true
```

### Keychain profile not found

Re-create it (requires app-specific password from appleid.apple.com):

```bash
xcrun notarytool store-credentials "notary-screenshot-space" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "83955LP5FK"
```

## What NOT to do

- Do not commit Apple ID or app-specific passwords to the repo
- Do not skip the notarization step for public releases
- Do not ship the ad-hoc signed DMG from `make dmg` as a public release
