import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var enableMenuItem: NSMenuItem!
    let appState = AppState()
    private var eventMonitor: EventMonitor?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainWindow()
        setupStatusItem()
        observeStateChanges()

        if appState.checkPermission() && appState.isEnabled {
            startMonitoring()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingComplete),
            name: .onboardingComplete,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Main Window

    private func setupMainWindow() {
        let view = MainWindowView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Space"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        mainWindow = window
    }

    @objc func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Screenshot Space"
            )
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(
            title: "Show Screenshot Space",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        enableMenuItem = NSMenuItem(
            title: appState.isEnabled ? "Disable" : "Enable",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        let folderItem = NSMenuItem(
            title: "Open Screenshots Folder",
            action: #selector(openScreenshotsFolder),
            keyEquivalent: ""
        )
        folderItem.target = self
        menu.addItem(folderItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Screenshot Space",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - State Observation

    private func observeStateChanges() {
        appState.$holdThreshold
            .sink { [weak self] threshold in
                self?.eventMonitor?.holdThreshold = threshold
            }
            .store(in: &cancellables)

        appState.$isEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Event Monitoring

    func startMonitoring() {
        guard eventMonitor == nil else { return }

        let monitor = EventMonitor()
        monitor.holdThreshold = appState.holdThreshold
        monitor.onTap = { ScreenshotManager.captureFullScreen() }
        monitor.onHold = { ScreenshotManager.captureSelection() }

        if monitor.start() {
            eventMonitor = monitor
        } else {
            appState.checkPermission()
        }
    }

    func stopMonitoring() {
        eventMonitor?.stop()
        eventMonitor = nil
    }

    // MARK: - Notifications

    @objc private func onboardingComplete() {
        if appState.isEnabled {
            startMonitoring()
        }
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled() {
        appState.isEnabled.toggle()
    }

    @objc private func openScreenshotsFolder() {
        ScreenshotManager.revealInFinder()
    }

    @objc private func quitApp() {
        stopMonitoring()
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        enableMenuItem.title = appState.isEnabled ? "Disable" : "Enable"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let onboardingComplete = Notification.Name("screenshotspace.onboardingComplete")
}
