import SwiftUI

struct ShortcutsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // ── General ──
            Section {
                Toggle("Enable Screenshot Shortcuts", isOn: $appState.isEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hold Threshold")
                        Spacer()
                        Text(String(format: "%.2fs", appState.holdThreshold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appState.holdThreshold, in: 0.10...1.0, step: 0.05)
                }

                Text("Tap \(appState.hotkeyDisplayString) → full-screen screenshot to clipboard\nHold \(appState.hotkeyDisplayString) → drag to select area to clipboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("General")
            }

            // ── Screenshot Hotkey ──
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(appState.hotkeyDisplayStringLong)")
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        modifierToggle("⌃ Control", flag: .maskControl)
                        modifierToggle("⇧ Shift", flag: .maskShift)
                        modifierToggle("⌥ Option", flag: .maskAlternate)
                        modifierToggle("⌘ Command", flag: .maskCommand)
                    }
                }

                Text("Select one or more modifier keys. The screenshot triggers when exactly these keys are pressed together.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Screenshot Hotkey")
            }

            // ── Recapture Region ──
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Region")
                        Text(appState.lastCapturedRegionDisplay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Define Region…") {
                        openRegionSelector()
                    }
                    if appState.lastCapturedRegion != nil {
                        Button("Clear") {
                            appState.lastCapturedRegion = nil
                        }
                    }
                }

                if appState.lastCapturedRegion != nil {
                    regionCoordinateFields
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recapture Hotkey: \(appState.recaptureHotkeyDisplayStringLong)")
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        recaptureModifierToggle("🌐 Fn", flag: .maskSecondaryFn)
                        recaptureModifierToggle("⌃ Control", flag: .maskControl)
                        recaptureModifierToggle("⇧ Shift", flag: .maskShift)
                        recaptureModifierToggle("⌥ Option", flag: .maskAlternate)
                        recaptureModifierToggle("⌘ Command", flag: .maskCommand)
                    }
                }

                Text("Tap \(appState.recaptureHotkeyDisplayString) to re-capture the defined region.\nIf Fn opens the emoji picker, change it in System Settings → Keyboard → \"Press 🌐 key to\" → Do Nothing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Recapture Region")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkey Helpers

    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                CGEventFlags(rawValue: appState.hotkeyModifiers).contains(flag)
            },
            set: { enabled in
                var flags = CGEventFlags(rawValue: appState.hotkeyModifiers)
                if enabled {
                    flags.insert(flag)
                } else {
                    flags.remove(flag)
                }
                let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
                guard !flags.intersection(relevant).isEmpty else { return }
                appState.hotkeyModifiers = flags.rawValue
            }
        )
    }

    @ViewBuilder
    private func modifierToggle(_ label: String, flag: CGEventFlags) -> some View {
        Toggle(label, isOn: modifierBinding(flag))
            .toggleStyle(.checkbox)
    }

    // MARK: - Recapture Helpers

    private func recaptureModifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                CGEventFlags(rawValue: appState.recaptureHotkeyModifiers).contains(flag)
            },
            set: { enabled in
                var flags = CGEventFlags(rawValue: appState.recaptureHotkeyModifiers)
                if enabled {
                    flags.insert(flag)
                } else {
                    flags.remove(flag)
                }
                let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
                guard !flags.intersection(relevant).isEmpty else { return }
                guard flags.rawValue != CGEventFlags(rawValue: appState.hotkeyModifiers).rawValue else { return }
                appState.recaptureHotkeyModifiers = flags.rawValue
            }
        )
    }

    @ViewBuilder
    private func recaptureModifierToggle(_ label: String, flag: CGEventFlags) -> some View {
        Toggle(label, isOn: recaptureModifierBinding(flag))
            .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private var regionCoordinateFields: some View {
        let region = appState.lastCapturedRegion ?? .zero
        HStack(spacing: 12) {
            coordinateField("X", value: region.origin.x) { newVal in
                appState.lastCapturedRegion = CGRect(x: newVal, y: region.origin.y, width: region.width, height: region.height)
            }
            coordinateField("Y", value: region.origin.y) { newVal in
                appState.lastCapturedRegion = CGRect(x: region.origin.x, y: newVal, width: region.width, height: region.height)
            }
            coordinateField("W", value: region.width) { newVal in
                guard newVal > 0 else { return }
                appState.lastCapturedRegion = CGRect(x: region.origin.x, y: region.origin.y, width: newVal, height: region.height)
            }
            coordinateField("H", value: region.height) { newVal in
                guard newVal > 0 else { return }
                appState.lastCapturedRegion = CGRect(x: region.origin.x, y: region.origin.y, width: region.width, height: newVal)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func coordinateField(_ label: String, value: CGFloat, onChange: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .trailing)
            TextField("", value: Binding(
                get: { Int(value) },
                set: { onChange(CGFloat($0)) }
            ), format: .number)
            .frame(width: 60)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func openRegionSelector() {
        let selector = RegionSelector()
        selector.selectRegion { rect in
            DispatchQueue.main.async {
                if let rect = rect {
                    appState.lastCapturedRegion = rect
                }
            }
        }
    }
}
