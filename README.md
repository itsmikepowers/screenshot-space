# Screenshot Space

A lightning-fast macOS screenshot utility that lives in your menu bar. Capture, organize, and search your screenshots with a single key.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## Features

### Instant Capture
- **Tap modifier** → Full-screen screenshot to clipboard
- **Hold modifier** → Drag to select a region
- Configurable hotkey — use Option (default), Command, Shift, Control, or any combination

### Smart Organization
- Screenshots saved to `~/Pictures/ScreenshotSpace/` by default (configurable)
- Automatic thumbnails and metadata
- Grid or list view with multi-select support

### OCR Search
- On-device text extraction using Apple Vision
- Search inside your screenshots instantly
- Find that error message, code snippet, or receipt

### Menu Bar Quick Access
- Recent screenshots at your fingertips
- One-click copy to clipboard
- Minimal footprint, maximum utility

---

## Installation

### Quick Install (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/itsmikepowers/screenshot-space/main/scripts/install.sh | bash
```

### Download DMG

1. Download [ScreenshotSpace-1.0.6.dmg](releases/ScreenshotSpace-1.0.6.dmg)
2. Open the DMG, then **drag Screenshot Space onto the Applications icon**
3. Eject the disk image, open **Screenshot Space** from Applications (use **Right-click → Open** the first time if macOS warns you)
4. Grant Accessibility permission when prompted

### Build from Source

```bash
git clone https://github.com/itsmikepowers/screenshot-space.git
cd screenshot-space
./build.sh
```

This builds, signs, and installs to `/Applications/Screenshot Space.app`.

### Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for global hotkey)

### First Launch Security

Since this app isn't notarized with Apple, macOS will block it on first launch:

1. **Right-click** the app and select **Open**
2. Click **Open** in the dialog
3. Or go to **System Settings → Privacy & Security** and click **Open Anyway**

This only needs to be done once.

---

## Usage

| Action | Result |
|--------|--------|
| Tap `⌥ Option` | Capture entire screen |
| Hold `⌥ Option` | Drag to select area |
| `⌘A` | Select all screenshots |
| `⌘C` | Copy selected to clipboard |
| `Delete` | Delete selected |
| `Esc` | Clear selection |
| Double-click | Preview screenshot |

---

## Architecture

```
Sources/
├── main.swift              # Entry point
├── AppDelegate.swift       # App lifecycle & menu bar
├── AppState.swift          # Settings & permissions
├── EventMonitor.swift      # Global hotkey listener
├── ScreenshotManager.swift # Capture & save logic
├── ScreenshotStore.swift   # Data model & file watching
├── OCRProcessor.swift      # Vision text extraction
├── MainWindowView.swift    # Tab container
├── ScreenshotGalleryView.swift  # Grid/list gallery
├── SearchView.swift        # OCR search interface
├── SettingsView.swift      # Preferences
└── OnboardingView.swift    # First-run setup
```

---

## Configuration

| Setting | Description |
|---------|-------------|
| Hold Threshold | Time before drag-select activates (0.1–1.0s) |
| Hotkey | Choose which modifier keys trigger screenshots (default: Option) |
| Screenshot Directory | Choose where screenshots are saved (default: `~/Pictures/ScreenshotSpace/`) |
| Show in Menu Bar | Toggle menu bar icon |
| Show in Dock | Toggle dock icon |
| Launch at Login | Start with macOS |

---

## Troubleshooting

The app automatically detects when you grant Accessibility permission — no need to click "Check Again". If the hotkey still doesn't work after granting access, try quitting and reopening the app.

If permissions still seem tied to an older build:

```bash
tccutil reset Accessibility com.screenshotspace.app
```

Then rebuild with `./build.sh`, re-open `/Applications/Screenshot Space.app`, and grant Accessibility access to that installed bundle again.

For signing setup details, verification commands, and local certificate guidance, see `docs/SIGNING.md`.

---

## Distribution (For Maintainers)

Create distributable packages for sharing:

```bash
# Create a DMG installer
make dmg

# Create a ZIP archive
make zip

# Create both with a version number
make release VERSION=1.2.0
```

Output files are created in `.build/release/`:
- `ScreenshotSpace-1.2.0.dmg` - Drag the app to Applications (standard macOS layout)
- `ScreenshotSpace-1.2.0.zip` - Simple archive

These are ad-hoc signed, meaning:
- No Apple Developer account required
- Users must right-click → Open on first launch
- Works for direct sharing, not Mac App Store

---

## Privacy

- **No network requests** — everything stays on your device
- **No analytics** — zero telemetry
- **Local OCR** — text extraction uses Apple's on-device Vision framework
- Screenshots are yours, stored in your Pictures folder

---

## Tech Stack

- **SwiftUI** — Native macOS UI
- **Vision** — On-device OCR
- **CGEvent** — Global hotkey monitoring
- **Swift Package Manager** — Zero dependencies

---

## License

MIT © [Mike Powers](https://github.com/itsmikepowers)

---

<p align="center">
  <sub>Built with ☕ and questionable amounts of Option key pressing</sub>
</p>
