# Screenshot Space

A lightning-fast macOS screenshot utility that lives in your menu bar. Capture, organize, and search your screenshots with a single key.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## Features

### Instant Capture
- **Tap Option** → Full-screen screenshot to clipboard
- **Hold Option** → Drag to select a region

### Smart Organization
- All screenshots saved to `~/Pictures/ScreenshotSpace/`
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

### Build from Source

```bash
git clone https://github.com/itsmikepowers/screenshot-space.git
cd screenshot-space
./build.sh
```

This is the supported local workflow:

- Build, sign, verify, and install the app to `/Applications/Screenshot Space.app`
- Grant Accessibility access to that installed app bundle
- Launch the installed bundle from `/Applications`

Run the installed app:

```bash
open "/Applications/Screenshot Space.app"
```

Do not use `.build/release/ScreenshotSpace` as the normal run target for local development. Accessibility permission is much more reliable when macOS sees one stable installed app identity.

### Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for global hotkey)
- A valid code-signing identity visible to `security find-identity -v -p codesigning`

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
| Show in Menu Bar | Toggle menu bar icon |
| Show in Dock | Toggle dock icon |
| Launch at Login | Start with macOS |

---

## Troubleshooting

If you grant Accessibility access while the app is already open, return to the app and use `Check Again` in Settings if the listener does not reconnect immediately.

If permissions still seem tied to an older build:

```bash
tccutil reset Accessibility com.screenshotspace.app
```

Then rebuild with `./build.sh`, re-open `/Applications/Screenshot Space.app`, and grant Accessibility access to that installed bundle again.

For signing setup details, verification commands, and local certificate guidance, see `docs/SIGNING.md`.

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
