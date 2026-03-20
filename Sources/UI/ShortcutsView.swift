import SwiftUI

struct ShortcutsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // Master toggle
            Section {
                Toggle("Enable Screenshot Shortcuts", isOn: $appState.isEnabled)
            }
            
            // Full Screen Screenshot
            ScreenshotModeSection(
                title: "Full Screen Screenshot",
                description: "Captures your entire screen instantly.",
                config: $appState.fullScreenMode,
                showFnKey: false
            )
            
            // Drag Screenshot
            ScreenshotModeSection(
                title: "Drag Screenshot",
                description: "Hold the hotkey and drag to select an area to capture.",
                config: $appState.dragMode,
                showFnKey: false
            )
            
            // Region Screenshot
            Section {
                Toggle("Enabled", isOn: $appState.regionMode.isEnabled)
                
                if appState.regionMode.isEnabled {
                    // Region definition
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved Region")
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
                    
                    Divider()
                    
                    // Hotkey configuration
                    HotkeyPicker(modifiers: $appState.regionMode.modifiers, showFnKey: true)
                    
                    TriggerTypePicker(config: $appState.regionMode)
                }
                
                Text("Re-captures a previously defined screen region. Define a region first, then use the hotkey to capture it again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Region Screenshot")
            }
            
            // Conflict warnings
            let conflicts = appState.detectConflicts()
            if !conflicts.isEmpty {
                Section {
                    ForEach(conflicts, id: \.reason) { conflict in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(conflict.reason)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Conflicts")
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Region Helpers
    
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

// MARK: - Reusable Components

struct ScreenshotModeSection: View {
    let title: String
    let description: String
    @Binding var config: ScreenshotModeConfig
    let showFnKey: Bool
    
    var body: some View {
        Section {
            Toggle("Enabled", isOn: $config.isEnabled)
            
            if config.isEnabled {
                HotkeyPicker(modifiers: $config.modifiers, showFnKey: showFnKey)
                TriggerTypePicker(config: $config)
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(title)
        }
    }
}

struct HotkeyPicker: View {
    @Binding var modifiers: UInt64
    let showFnKey: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkey: \(displayString)")
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                if showFnKey {
                    modifierToggle("🌐 Fn", flag: .maskSecondaryFn)
                }
                modifierToggle("⌃ Control", flag: .maskControl)
                modifierToggle("⇧ Shift", flag: .maskShift)
                modifierToggle("⌥ Option", flag: .maskAlternate)
                modifierToggle("⌘ Command", flag: .maskCommand)
            }
        }
    }
    
    private var displayString: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.maskSecondaryFn) { parts.append("🌐 Fn") }
        if flags.contains(.maskControl) { parts.append("⌃ Control") }
        if flags.contains(.maskShift) { parts.append("⇧ Shift") }
        if flags.contains(.maskAlternate) { parts.append("⌥ Option") }
        if flags.contains(.maskCommand) { parts.append("⌘ Command") }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }
    
    @ViewBuilder
    private func modifierToggle(_ label: String, flag: CGEventFlags) -> some View {
        Toggle(label, isOn: modifierBinding(flag))
            .toggleStyle(.checkbox)
    }
    
    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                CGEventFlags(rawValue: modifiers).contains(flag)
            },
            set: { enabled in
                var flags = CGEventFlags(rawValue: modifiers)
                if enabled {
                    flags.insert(flag)
                } else {
                    flags.remove(flag)
                }
                let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
                guard !flags.intersection(relevant).isEmpty else { return }
                modifiers = flags.rawValue
            }
        )
    }
}

struct TriggerTypePicker: View {
    @Binding var config: ScreenshotModeConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Trigger", selection: $config.triggerType) {
                ForEach(TriggerType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            if config.triggerType == .tapAndHold {
                HStack {
                    Text("Hold Threshold")
                    Spacer()
                    Text(String(format: "%.2fs", config.holdThreshold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $config.holdThreshold, in: 0.10...1.0, step: 0.05)
            }
        }
    }
}
