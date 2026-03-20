---
name: reinstall
description: Clean uninstall and reinstall of Screenshot Space to /Applications. Use this skill whenever the user says "reinstall", "rebuild and install", "update the app", "fresh install", "put the new version in Applications", or anything about removing and re-adding the app. Also use when the user says "uninstall" (just run the removal steps) or "install" (just run the install steps).
---

# Reinstall Screenshot Space

Build the current source, package it as a proper .app bundle, ad-hoc sign it, and install to `/Applications/Screenshot Space.app`. No signing certificate is needed — this uses ad-hoc signing (`--sign -`).

## Steps

Run these steps in order. Each step is a single shell command or small block.

### 1. Quit the running app (if any)

```bash
osascript -e 'quit app "Screenshot Space"' 2>/dev/null || true
sleep 1
```

Wait a moment so the process fully exits before removing files.

### 2. Remove the old installation

```bash
rm -rf "/Applications/Screenshot Space.app"
```

### 3. Build release binary

From the repo root:

```bash
swift build -c release
```

Confirm it succeeds before continuing.

### 4. Bundle, sign, and install

```bash
APP_BUNDLE="/tmp/Screenshot Space.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/ScreenshotSpace "$APP_BUNDLE/Contents/MacOS/ScreenshotSpace"
cp Info.plist "$APP_BUNDLE/Contents/"

if [ -f "Assets/AppIcon/AppIcon.icns" ]; then
  cp "Assets/AppIcon/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_BUNDLE"
cp -R "$APP_BUNDLE" "/Applications/Screenshot Space.app"
rm -rf "$APP_BUNDLE"
```

### 5. Confirm

Print a short confirmation that the app was installed. Do NOT auto-launch the app — let the user open it when ready.

Remind the user:
- First launch: right-click → Open if macOS blocks it
- They may need to re-grant Accessibility permission in System Settings → Privacy & Security → Accessibility

## What NOT to do

- Do not use `build.sh` — it requires a signing certificate we don't have
- Do not use `scripts/install.sh` — it downloads from GitHub instead of building local source
- Do not auto-launch the app after install
- Do not touch `~/Pictures/ScreenshotSpace/` or UserDefaults — user data is separate from the app binary
