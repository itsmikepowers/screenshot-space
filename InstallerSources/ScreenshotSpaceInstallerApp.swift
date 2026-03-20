import SwiftUI
import AppKit

@main
struct ScreenshotSpaceInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerWizardView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

enum InstallerStep: Int, CaseIterable {
    case welcome
    case installing
    case complete
    case error
}

struct InstallerWizardView: View {
    @State private var currentStep: InstallerStep = .welcome
    @State private var errorMessage: String = ""
    @State private var installProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            footerView
        }
        .frame(width: 480, height: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack(spacing: 16) {
            if let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Screenshot Space")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Installer")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch currentStep {
        case .welcome:
            welcomeContent
        case .installing:
            installingContent
        case .complete:
            completeContent
        case .error:
            errorContent
        }
    }
    
    private var welcomeContent: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("Welcome to Screenshot Space")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("This will install Screenshot Space to your Applications folder.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "camera.viewfinder", text: "Tap Option for instant screenshots")
                featureRow(icon: "rectangle.dashed", text: "Hold Option to select a region")
                featureRow(icon: "text.viewfinder", text: "Search screenshots with OCR")
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.callout)
        }
    }
    
    private var installingContent: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView(value: installProgress)
                .progressViewStyle(.linear)
                .frame(width: 200)
            
            Text("Installing...")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    private var completeContent: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Installation Complete!")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Screenshot Space has been installed to your Applications folder.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var errorContent: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Installation Failed")
                .font(.title3)
                .fontWeight(.medium)
            
            Text(errorMessage)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var footerView: some View {
        HStack {
            if currentStep == .welcome {
                Button("Cancel") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
            
            Spacer()
            
            switch currentStep {
            case .welcome:
                Button("Install") {
                    startInstallation()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                
            case .installing:
                EmptyView()
                
            case .complete:
                Button("Launch Screenshot Space") {
                    launchApp()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Close") {
                    NSApp.terminate(nil)
                }
                
            case .error:
                Button("Try Again") {
                    currentStep = .welcome
                }
                .buttonStyle(.borderedProminent)
                
                Button("Close") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(20)
    }
    
    private func startInstallation() {
        currentStep = .installing
        installProgress = 0
        
        Task {
            do {
                try await performInstallation()
                await MainActor.run {
                    currentStep = .complete
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    currentStep = .error
                }
            }
        }
    }
    
    private func performInstallation() async throws {
        let fileManager = FileManager.default
        let appName = "Screenshot Space.app"
        let destinationPath = "/Applications/\(appName)"
        
        guard let bundlePath = Bundle.main.bundlePath as String?,
              let volumePath = findVolumePath(from: bundlePath) else {
            throw InstallerError.cannotFindSource
        }
        
        let sourcePath = "\(volumePath)/\(appName)"
        
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw InstallerError.sourceNotFound(sourcePath)
        }
        
        await MainActor.run { installProgress = 0.2 }
        
        if fileManager.fileExists(atPath: destinationPath) {
            do {
                try fileManager.removeItem(atPath: destinationPath)
            } catch {
                throw InstallerError.cannotRemoveExisting(error.localizedDescription)
            }
        }
        
        await MainActor.run { installProgress = 0.5 }
        
        do {
            try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
        } catch {
            throw InstallerError.copyFailed(error.localizedDescription)
        }
        
        await MainActor.run { installProgress = 1.0 }
        
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    private func findVolumePath(from path: String) -> String? {
        let components = path.split(separator: "/")
        if components.count >= 2 && components[0] == "Volumes" {
            return "/Volumes/\(components[1])"
        }
        if path.hasPrefix("/Volumes/") {
            let volumeComponents = path.dropFirst("/Volumes/".count).split(separator: "/")
            if let volumeName = volumeComponents.first {
                return "/Volumes/\(volumeName)"
            }
        }
        return (path as NSString).deletingLastPathComponent
    }
    
    private func launchApp() {
        let appPath = "/Applications/Screenshot Space.app"
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: appPath),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if error != nil {
                NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}

enum InstallerError: LocalizedError {
    case cannotFindSource
    case sourceNotFound(String)
    case cannotRemoveExisting(String)
    case copyFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotFindSource:
            return "Could not locate the application bundle. Please run the installer from the disk image."
        case .sourceNotFound(let path):
            return "Screenshot Space.app was not found at: \(path)"
        case .cannotRemoveExisting(let detail):
            return "Could not remove existing installation: \(detail)"
        case .copyFailed(let detail):
            return "Failed to copy application: \(detail)"
        }
    }
}
