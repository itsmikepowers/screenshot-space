import Foundation
import AppKit

enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String)
    case downloading
    case installing
    case upToDate
    case error(String)
    
    var isLoading: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }
}

@MainActor
class Updater: ObservableObject {
    static let shared = Updater()
    
    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var currentVersion: String
    @Published private(set) var latestVersion: String?
    
    private let repoOwner = "itsmikepowers"
    private let repoName = "screenshot-space"
    private let dmgName = "ScreenshotSpace"
    
    private init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    func checkForUpdates() async {
        status = .checking
        
        do {
            let version = try await fetchLatestVersion()
            latestVersion = version
            
            if isNewerVersion(version, than: currentVersion) {
                status = .available(version: version)
            } else {
                status = .upToDate
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }
    
    func downloadAndInstall() async {
        guard let version = latestVersion else {
            status = .error("No version to install")
            return
        }
        
        status = .downloading
        
        do {
            let dmgURL = try await downloadDMG(version: version)
            status = .installing
            try await installFromDMG(dmgURL)
            
            try? FileManager.default.removeItem(at: dmgURL)
            
            relaunchApp()
        } catch {
            status = .error(error.localizedDescription)
        }
    }
    
    private func fetchLatestVersion() async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/releases") else {
            throw UpdateError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }
        
        guard let files = try? JSONDecoder().decode([GitHubFile].self, from: data) else {
            throw UpdateError.parseError
        }
        
        let dmgFiles = files.filter { $0.name.hasPrefix(dmgName) && $0.name.hasSuffix(".dmg") }
        
        let versions = dmgFiles.compactMap { file -> String? in
            let name = file.name
            guard let start = name.range(of: "-"),
                  let end = name.range(of: ".dmg") else { return nil }
            return String(name[start.upperBound..<end.lowerBound])
        }
        
        guard let latest = versions.sorted(by: { compareVersions($0, $1) }).last else {
            throw UpdateError.noReleasesFound
        }
        
        return latest
    }
    
    private func downloadDMG(version: String) async throws -> URL {
        let dmgFileName = "\(dmgName)-\(version).dmg"
        let downloadURL = "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/releases/\(dmgFileName)"
        
        guard let url = URL(string: downloadURL) else {
            throw UpdateError.invalidURL
        }
        
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }
        
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(dmgFileName)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        
        return destURL
    }
    
    private func installFromDMG(_ dmgURL: URL) async throws {
        let mountPoint = "/Volumes/Screenshot Space"
        
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["attach", dmgURL.path, "-nobrowse", "-quiet"]
        try mountProcess.run()
        mountProcess.waitUntilExit()
        
        guard mountProcess.terminationStatus == 0 else {
            throw UpdateError.mountFailed
        }
        
        defer {
            let unmountProcess = Process()
            unmountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            unmountProcess.arguments = ["detach", mountPoint, "-quiet"]
            try? unmountProcess.run()
            unmountProcess.waitUntilExit()
        }
        
        let sourceApp = URL(fileURLWithPath: "\(mountPoint)/Screenshot Space.app")
        let destApp = URL(fileURLWithPath: "/Applications/Screenshot Space.app")
        
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw UpdateError.appNotFoundInDMG
        }
        
        try? FileManager.default.removeItem(at: destApp)
        try FileManager.default.copyItem(at: sourceApp, to: destApp)
    }
    
    private func relaunchApp() {
        let appPath = "/Applications/Screenshot Space.app"
        
        let script = """
        sleep 1
        open "\(appPath)"
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
    
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        return compareVersions(current, new)
    }
    
    private func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxLen = max(parts1.count, parts2.count)
        let padded1 = parts1 + Array(repeating: 0, count: maxLen - parts1.count)
        let padded2 = parts2 + Array(repeating: 0, count: maxLen - parts2.count)
        
        for (p1, p2) in zip(padded1, padded2) {
            if p1 < p2 { return true }
            if p1 > p2 { return false }
        }
        return false
    }
}

private struct GitHubFile: Decodable {
    let name: String
}

enum UpdateError: LocalizedError {
    case invalidURL
    case networkError
    case parseError
    case noReleasesFound
    case downloadFailed
    case mountFailed
    case appNotFoundInDMG
    case installFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError: return "Network error"
        case .parseError: return "Failed to parse response"
        case .noReleasesFound: return "No releases found"
        case .downloadFailed: return "Download failed"
        case .mountFailed: return "Failed to mount DMG"
        case .appNotFoundInDMG: return "App not found in DMG"
        case .installFailed: return "Installation failed"
        }
    }
}
