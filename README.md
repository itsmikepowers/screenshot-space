# Screenshot Space

A fast macOS screenshot utility that lives in your menu bar. Capture, organize, and search your screenshots with a single key.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## Features

- **Tap modifier** → Full-screen screenshot to clipboard
- **Hold modifier** → Drag to select a region
- **Region recapture** → Define a region once, re-capture it instantly with a hotkey
- **OCR search** → Find text inside your screenshots using on-device Vision
- **Menu bar access** → Recent screenshots at your fingertips
- **Privacy first** → No network requests, no analytics, everything stays local

---

## Installation

### Download DMG

1. Download [ScreenshotSpace-1.0.10.dmg](releases/ScreenshotSpace-1.0.10.dmg)
2. Open the DMG and drag Screenshot Space to Applications
3. Launch from Applications
4. Grant Accessibility permission when prompted

### Build from Source

```bash
git clone https://github.com/itsmikepowers/screenshot-space.git
cd screenshot-space
./build.sh
```

---

## Usage

| Action | Result |
|--------|--------|
| Tap `⌥ Option` | Capture entire screen |
| Hold `⌥ Option` | Drag to select area |
| Tap `🌐 Fn` | Re-capture defined region |
| `⌘A` | Select all screenshots |
| `⌘C` | Copy selected to clipboard |
| `Delete` | Delete selected |
| Double-click | Preview screenshot |

---

## Settings

| Setting | Description |
|---------|-------------|
| Hotkey | Modifier keys for screenshots (default: Option) |
| Recapture Hotkey | Modifier keys for region recapture (default: Fn) |
| Hold Threshold | Time before drag-select activates |
| Screenshot Directory | Where screenshots are saved |
| Launch at Login | Start with macOS |

---

## Troubleshooting

If the hotkey doesn't work after granting Accessibility permission, quit and reopen the app.

To reset permissions:

```bash
tccutil reset Accessibility com.screenshotspace.app
```

---

## Architecture

Swift sources live under `Sources/` (single SwiftPM executable target). Layout:

```
Sources/
├── App/                 # process entry, NSApplication delegate, shared app state
│   ├── main.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
├── UI/                  # SwiftUI main window, tabs, gallery AppKit bridge
│   ├── MainWindowView.swift
│   ├── ScreenshotGalleryView.swift
│   ├── SearchView.swift
│   ├── SettingsView.swift
│   └── OnboardingView.swift
├── Capture/             # global event monitoring, region selection, capture I/O
│   ├── EventMonitor.swift
│   ├── RegionSelector.swift
│   └── ScreenshotManager.swift
├── Media/               # screenshot model, preview window, export / drag helpers
│   ├── ScreenshotItem.swift
│   ├── ScreenshotPreviewWindowPresenter.swift
│   └── FileExportDrag.swift
├── Search/              # on-device OCR (Vision) for search
│   └── OCRProcessor.swift
└── Services/            # cross-cutting non-UI (e.g. updates)
    └── Updater.swift
```

**Assets** (not compiled into the Swift target; copied by build / DMG scripts):

```
Assets/
├── AppIcon/             # app bundle icon + source artwork for regenerating .icns
│   ├── AppIcon.icns     # copied into .app/Contents/Resources (see Info.plist)
│   ├── AppIcon_rounded.png
│   └── AppIcon_transparent.png
└── DMG/                 # used only when running scripts/build-dmg.sh (make dmg)
    ├── dmg-background.png   # Finder window background on the install disk image
    └── FolderIcon.icns      # custom icon for the Applications alias on that DMG
```

---

## License

MIT © [Mike Powers](https://github.com/itsmikepowers)
