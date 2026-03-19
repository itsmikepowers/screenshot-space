import Cocoa
import SwiftUI
import Combine
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private static let logger = Logger(subsystem: "com.screenshotspace", category: "AppDelegate")

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    let appState = AppState()
    private var eventMonitor: EventMonitor?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var retryMonitoringWorkItem: DispatchWorkItem?
    private var monitoringRetryCount = 0
    private let shortRetryLimit = 3
    private let recoveryRetryDelay: TimeInterval = 15.0
    private var healthCheckTimer: Timer?
    
    private let menuDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("App launched")
        
        setupMainWindow()

        if appState.showInMenuBar {
            setupStatusItem()
        }

        applyDockVisibility(appState.showInDock)
        observeStateChanges()
        _ = appState.refreshSystemAccess()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Self.logger.info("App terminating")
        stopHealthCheck()
        stopMonitoring()
        retryMonitoringWorkItem?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    // MARK: - System Event Handlers
    
    @objc private func handleWakeFromSleep() {
        Self.logger.debug("System woke from sleep")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            _ = self?.appState.refreshSystemAccess()
        }
    }
    
    @objc private func handleScreensChanged() {
        Self.logger.debug("Screen parameters changed")
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

    /// Tag used to identify dynamic screenshot menu items so we can remove them on refresh.
    private let recentScreenshotTag = 999

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

        // Static items — recent screenshots are inserted above these dynamically
        let showItem = NSMenuItem(
            title: "Show Screenshot Space",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

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

    // MARK: - Recent Screenshots in Menu

    private func refreshRecentScreenshots(in menu: NSMenu) {
        // Remove old screenshot items
        menu.items.filter { $0.tag == recentScreenshotTag }.forEach { menu.removeItem($0) }

        let recent = loadRecentScreenshots(count: 5)
        guard !recent.isEmpty else { return }

        // Insert at the very top: screenshots then a separator
        var insertIndex = 0

        // Header
        let header = NSMenuItem()
        header.tag = recentScreenshotTag
        header.attributedTitle = NSAttributedString(
            string: "Recent Screenshots",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        header.isEnabled = false
        menu.insertItem(header, at: insertIndex)
        insertIndex += 1

        for (url, thumbnail, name, dateString) in recent {
            let item = NSMenuItem(
                title: name,
                action: #selector(menuScreenshotClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = recentScreenshotTag
            item.representedObject = url

            // Thumbnail scaled to menu size
            let scaledThumb = resizeImage(thumbnail, to: NSSize(width: 32, height: 32))
            item.image = scaledThumb

            // Styled title: name on top, date below
            let titlePara = NSMutableParagraphStyle()
            titlePara.lineBreakMode = .byTruncatingMiddle

            let attributed = NSMutableAttributedString()
            attributed.append(NSAttributedString(
                string: name + "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .paragraphStyle: titlePara
                ]
            ))
            attributed.append(NSAttributedString(
                string: dateString,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
            item.attributedTitle = attributed

            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }

        let sep = NSMenuItem.separator()
        sep.tag = recentScreenshotTag
        menu.insertItem(sep, at: insertIndex)
    }

    @objc private func menuScreenshotClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func loadRecentScreenshots(count: Int) -> [(URL, NSImage, String, String)] {
        let dir = ScreenshotManager.saveDirectory
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let date = values.creationDate else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .compactMap { [weak self] (url, date) -> (URL, NSImage, String, String)? in
                guard let self = self,
                      let thumb = self.loadMenuThumbnail(from: url) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                let dateStr = self.menuDateFormatter.string(from: date)
                return (url, thumb, name, dateStr)
            }
    }

    private func loadMenuThumbnail(from url: URL, maxSize: CGFloat = 72) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func resizeImage(_ image: NSImage, to targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
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
            .sink { [weak self] _ in
                self?.reconcileMonitoring(reason: "enabled state changed")
            }
            .store(in: &cancellables)

        appState.$systemAccessRefreshID
            .dropFirst()
            .sink { [weak self] _ in
                self?.reconcileMonitoring(reason: "system access refreshed")
            }
            .store(in: &cancellables)

        appState.$showInMenuBar
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] show in
                guard let self = self else { return }
                if show {
                    self.setupStatusItem()
                } else {
                    self.removeStatusItem()
                }
            }
            .store(in: &cancellables)

        appState.$showInDock
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] show in
                guard let self = self else { return }
                self.applyDockVisibility(show)
            }
            .store(in: &cancellables)
    }

    // MARK: - Dock Visibility

    private func applyDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        // If hiding from dock, make sure the window stays visible
        if !show {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Menu Bar Visibility

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Event Monitoring

    private func reconcileMonitoring(reason: String) {
        Self.logger.debug("Reconciling monitoring: \(reason, privacy: .public)")

        guard appState.isEnabled else {
            cancelMonitoringRetry()
            stopMonitoring()
            monitoringRetryCount = 0
            appState.updateMonitorStatus(.inactive)
            return
        }

        guard appState.hasPermission else {
            stopMonitoring()
            appState.updateMonitorStatus(.inactive)
            scheduleMonitoringRetry()
            return
        }

        guard eventMonitor == nil else {
            cancelMonitoringRetry()
            monitoringRetryCount = 0
            appState.updateMonitorStatus(.active)
            return
        }

        startMonitoring()
    }

    private func startMonitoring() {
        guard eventMonitor == nil else {
            Self.logger.debug("Event monitor already running")
            appState.updateMonitorStatus(.active)
            return
        }

        cancelMonitoringRetry()

        let monitor = EventMonitor()
        monitor.holdThreshold = appState.holdThreshold
        monitor.onTap = { [weak self] in
            self?.statusItem?.menu?.cancelTracking()
            ScreenshotManager.captureFullScreen()
        }
        monitor.onHold = { [weak self] in
            self?.statusItem?.menu?.cancelTracking()
            ScreenshotManager.captureSelection()
        }
        monitor.onTapDisabled = {
            Self.logger.warning("Event tap was disabled by system, re-enabling...")
        }

        switch monitor.start() {
        case .started, .alreadyRunning:
            eventMonitor = monitor
            monitoringRetryCount = 0
            appState.updateMonitorStatus(.active)
            startHealthCheck()
            Self.logger.info("Event monitoring started successfully")
        case .permissionDenied:
            Self.logger.warning("Event monitoring blocked by missing Accessibility permission")
            appState.applyAccessibilityTrust(false)
            appState.updateMonitorStatus(.inactive)
            scheduleMonitoringRetry()
        case .failedToCreateTap:
            let message = "macOS could not start the global hotkey listener. Keep the app installed in /Applications, then click Check Again."
            Self.logger.error("Failed to create event tap")
            appState.updateMonitorStatus(.failedToStart(message))
            scheduleMonitoringRetry()
        }
    }

    private func stopMonitoring() {
        stopHealthCheck()
        eventMonitor?.stop()
        eventMonitor = nil
        Self.logger.info("Event monitoring stopped")
    }
    
    // MARK: - Health Check
    
    /// Periodically verify the event tap is still running and re-enable if needed
    private func startHealthCheck() {
        stopHealthCheck()
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let monitor = self.eventMonitor else { return }
            
            if !monitor.isRunning {
                Self.logger.warning("Health check: event tap not running, attempting to reactivate")
                monitor.reactivate()
                
                // If still not running after reactivate, try full restart
                if !monitor.isRunning {
                    Self.logger.warning("Health check: reactivate failed, attempting full restart")
                    self.stopMonitoring()
                    self.reconcileMonitoring(reason: "health check recovery")
                }
            }
        }
    }
    
    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func scheduleMonitoringRetry() {
        guard appState.isEnabled, eventMonitor == nil else {
            return
        }

        cancelMonitoringRetry()
        monitoringRetryCount += 1
        let delay = monitoringRetryCount <= shortRetryLimit
            ? Double(monitoringRetryCount) * 2.0
            : recoveryRetryDelay

        Self.logger.debug("Scheduling monitoring retry \(self.monitoringRetryCount) in \(delay)s")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.appState.isEnabled, self.eventMonitor == nil else { return }
            self.retryMonitoringWorkItem = nil
            _ = self.appState.refreshSystemAccess()
        }
        retryMonitoringWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelMonitoringRetry() {
        retryMonitoringWorkItem?.cancel()
        retryMonitoringWorkItem = nil
    }

    // MARK: - Menu Actions

    @objc private func openScreenshotsFolder() {
        ScreenshotManager.revealInFinder()
    }

    @objc private func quitApp() {
        cancelMonitoringRetry()
        stopMonitoring()
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshRecentScreenshots(in: menu)
    }
}
