import Foundation
import SwiftUI
import AppKit

/// Production-grade OTA Update Manager for Frames on macOS Apple Silicon.
/// Provides non-intrusive background checking, manual updates, downloading with progress,
/// integrity validation, and self-update with atomic bundle swap & restart.
@MainActor
@Observable
public final class UpdateManager: NSObject {
    public static let shared = UpdateManager()

    // MARK: - Configuration
    public let repositoryOwner = "whoavidwivedi"
    public let repositoryName = "frames"

    public var releasesApiEndpoint: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases?per_page=15")!
    }

    public var latestReleaseApiEndpoint: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
    }

    public var apiEndpoint: URL {
        if updateChannel == .beta {
            return releasesApiEndpoint
        } else {
            return latestReleaseApiEndpoint
        }
    }

    public var updateChannel: UpdateChannel {
        get {
            SettingsManager.shared.updateChannel
        }
        set {
            SettingsManager.shared.updateChannel = newValue
        }
    }

    public func setChannel(_ channel: UpdateChannel, checkImmediately: Bool = false) {
        updateChannel = channel
        availableUpdate = nil
        status = .idle
        if checkImmediately {
            checkForUpdates(manual: true)
        }
    }

    // MARK: - Published State
    public private(set) var status: UpdateStatus = .idle
    public private(set) var availableUpdate: AppUpdateInfo? = nil
    public var isUpdatePromptPresented: Bool = false
    public var manualCheckNotice: ManualCheckNotice? = nil

    public private(set) var downloadProgress: Double = 0.0
    public private(set) var downloadedBytes: Int64 = 0
    public private(set) var totalBytes: Int64 = 0
    public private(set) var lastCheckedDate: Date? = nil

    private var activeDownloadTask: Task<Void, Never>? = nil

    // User preferences
    private let skippedVersionsKey = "FramesSkippedUpdateVersions"

    public var skippedVersions: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: skippedVersionsKey) ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: skippedVersionsKey)
        }
    }

    public var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.7"
    }

    public var currentVersion: SemanticVersion {
        SemanticVersion(string: currentVersionString) ?? SemanticVersion(major: 1, minor: 5, patch: 7)
    }

    public var hasUpdate: Bool {
        availableUpdate != nil && (status != .idle)
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Update Checking

    /// Checks for updates against GitHub Releases API.
    /// - Parameter manual: If true, user explicitly clicked "Check for Updates" and should receive feedback even if up-to-date.
    public func checkForUpdates(manual: Bool = false) {
        // Prevent concurrent checks
        if case .checking = status { return }
        if case .downloading = status { return }
        if case .extracting = status { return }

        status = .checking
        if manual {
            manualCheckNotice = nil
        }

        Task {
            do {
                let release = try await self.fetchRelease(for: self.updateChannel)
                self.lastCheckedDate = Date()
                self.processRelease(release, manual: manual)
            } catch {
                self.status = .error(message: error.localizedDescription)
                if manual {
                    self.manualCheckNotice = ManualCheckNotice(
                        title: "Check Failed",
                        message: "Unable to check for updates: \(error.localizedDescription)",
                        isError: true
                    )
                }
            }
        }
    }

    /// Fetches release according to target channel (Stable vs Beta).
    public func fetchRelease(for channel: UpdateChannel) async throws -> GitHubRelease {
        if channel == .beta {
            let releases = try await fetchAllReleases()
            guard let release = releases.first(where: { !($0.draft ?? false) }) else {
                // If no specific beta release, fallback to latest stable
                return try await fetchLatestRelease()
            }
            return release
        } else {
            return try await fetchLatestRelease()
        }
    }

    /// Fetches recent releases from GitHub API.
    public func fetchAllReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: releasesApiEndpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Frames-macOS/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FramesUpdate", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        if httpResponse.statusCode == 404 {
            throw NSError(domain: "FramesUpdate", code: 404, userInfo: [NSLocalizedDescriptionKey: "No published releases found."])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "FramesUpdate", code: 403, userInfo: [NSLocalizedDescriptionKey: "GitHub API rate limit exceeded. Please try again later."])
        } else if httpResponse.statusCode != 200 {
            throw NSError(domain: "FramesUpdate", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error code \(httpResponse.statusCode)."])
        }

        let decoder = JSONDecoder()
        return try decoder.decode([GitHubRelease].self, from: data)
    }

    /// Fetches latest release payload from GitHub API.
    public func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseApiEndpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Frames-macOS/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FramesUpdate", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        if httpResponse.statusCode == 404 {
            throw NSError(domain: "FramesUpdate", code: 404, userInfo: [NSLocalizedDescriptionKey: "No published releases found."])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "FramesUpdate", code: 403, userInfo: [NSLocalizedDescriptionKey: "GitHub API rate limit exceeded. Please try again later."])
        } else if httpResponse.statusCode != 200 {
            throw NSError(domain: "FramesUpdate", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error code \(httpResponse.statusCode)."])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Evaluates a fetched release against the local version.
    public func processRelease(_ release: GitHubRelease, manual: Bool) {
        guard let releaseVersion = SemanticVersion(string: release.tagName) else {
            self.status = .idle
            if manual {
                self.manualCheckNotice = ManualCheckNotice(
                    title: "Invalid Release Tag",
                    message: "Release tag '\(release.tagName)' is not a valid semantic version.",
                    isError: true
                )
            }
            return
        }

        // Compare semantic version
        if releaseVersion > currentVersion {
            // Find appropriate payload asset: prefer .zip containing macOS bundle, then .dmg
            let asset = release.assets.first(where: { $0.isZipPayload }) ?? release.assets.first(where: { $0.isDmgPayload })

            guard let matchedAsset = asset else {
                self.status = .idle
                if manual {
                    self.manualCheckNotice = ManualCheckNotice(
                        title: "Update Available",
                        message: "Frames \(release.tagName) is available on GitHub, but no macOS installation package was found."
                    )
                }
                return
            }

            var publishedDate: Date? = nil
            if let pubStr = release.publishedAt {
                let isoFormatter = ISO8601DateFormatter()
                publishedDate = isoFormatter.date(from: pubStr)
            }

            let releasePageURL = release.htmlUrl != nil ? URL(string: release.htmlUrl!) : nil

            let update = AppUpdateInfo(
                tagName: release.tagName,
                version: releaseVersion,
                title: release.name ?? "Frames \(release.tagName)",
                releaseNotes: release.body ?? "General improvements and optimizations.",
                releasePageURL: releasePageURL,
                publishedDate: publishedDate,
                asset: matchedAsset,
                isPrerelease: release.prerelease ?? false
            )

            self.availableUpdate = update
            self.status = .available(info: update)

            // Show prompt if manual, or if not skipped
            if manual || !isVersionSkipped(release.tagName) {
                self.isUpdatePromptPresented = true
            }
        } else {
            self.availableUpdate = nil
            self.status = .upToDate(checkedVersion: currentVersion.displayString)
            if manual {
                self.manualCheckNotice = ManualCheckNotice(
                    title: "Up to Date",
                    message: "Frames v\(currentVersion.displayString) (\(self.updateChannel.displayName) channel) is currently the newest version available."
                )
            }
        }
    }

    // MARK: - User Actions

    public func presentUpdatePrompt() {
        if availableUpdate != nil {
            isUpdatePromptPresented = true
        }
    }

    public func dismissPrompt() {
        isUpdatePromptPresented = false
    }

    public func dismissNotice() {
        manualCheckNotice = nil
    }

    public func skipVersion(_ tagName: String) {
        var skipped = skippedVersions
        skipped.insert(tagName)
        skippedVersions = skipped
        isUpdatePromptPresented = false
    }

    public func isVersionSkipped(_ tagName: String) -> Bool {
        skippedVersions.contains(tagName)
    }

    public func openReleasePage() {
        if let url = availableUpdate?.releasePageURL ?? URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        if let update = availableUpdate {
            status = .available(info: update)
        } else {
            status = .idle
        }
        downloadProgress = 0.0
        downloadedBytes = 0
        totalBytes = 0
    }

    // MARK: - Download & Self-Update Pipeline

    /// Initiates downloading, verification, bundle replacement, and relaunch.
    public func startUpdateAndRestart() {
        guard let update = availableUpdate, let assetDownloadURL = URL(string: update.asset.browserDownloadUrl) else {
            status = .error(message: "Download URL is invalid.")
            return
        }

        downloadProgress = 0.0
        downloadedBytes = 0
        totalBytes = update.asset.size
        status = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: totalBytes)

        activeDownloadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let downloader = OTAAssetDownloader()
                downloader.onProgress = { [weak self] progress, written, total in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.downloadProgress = progress
                        self.downloadedBytes = written
                        self.totalBytes = total
                        self.status = .downloading(progress: progress, bytesWritten: written, totalBytes: total)
                    }
                }

                let downloadedZipURL = try await downloader.download(from: assetDownloadURL)

                try Task.checkCancellation()

                // Extraction phase
                self.status = .extracting

                let extractDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FramesUpdate_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // Native extraction via /usr/bin/ditto (preserves macOS bundle metadata & permissions)
                try await Self.extractArchive(at: downloadedZipURL, to: extractDir)

                // Clean up zip archive
                try? FileManager.default.removeItem(at: downloadedZipURL)

                // Locate application bundle in extracted directory
                guard let newAppBundleURL = Self.findAppBundle(in: extractDir) else {
                    throw NSError(
                        domain: "FramesUpdate",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Application bundle could not be found in downloaded update."]
                    )
                }

                // Verify integrity & executable
                try Self.verifyAppBundle(at: newAppBundleURL)

                self.status = .readyToRestart

                // Determine target app destination
                let targetAppURL = Self.resolveTargetAppURL()

                // Execute relaunch helper script and terminate
                try Self.executeRelaunchHelper(
                    newAppURL: newAppBundleURL,
                    targetAppURL: targetAppURL,
                    currentPID: ProcessInfo.processInfo.processIdentifier
                )

                // Terminate current instance cleanly
                NSApp.terminate(nil)
            } catch is CancellationError {
                // Cancelled by user
            } catch {
                self.status = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Archive & Bundle Helper Routines

    public static func extractArchive(at zipURL: URL, to destDir: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown extraction error"
            throw NSError(domain: "FramesUpdate", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to extract update package: \(errorString)"])
        }
    }

    public static func findAppBundle(in directory: URL) -> URL? {
        let fileManager = FileManager.default

        // Check directly inside directory
        if let directApp = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "app" }) {
            return directApp
        }

        // Check one level deeper if nested
        if let subdirs = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for sub in subdirs {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                    if let nested = try? fileManager.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension.lowercased() == "app" }) {
                        return nested
                    }
                }
            }
        }

        return nil
    }

    public static func verifyAppBundle(at bundleURL: URL) throws {
        let fileManager = FileManager.default
        let infoPlist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlist.path) else {
            throw NSError(domain: "FramesUpdate", code: -3, userInfo: [NSLocalizedDescriptionKey: "Downloaded bundle is missing Info.plist."])
        }

        let macosDir = bundleURL.appendingPathComponent("Contents/MacOS")
        guard fileManager.fileExists(atPath: macosDir.path) else {
            throw NSError(domain: "FramesUpdate", code: -4, userInfo: [NSLocalizedDescriptionKey: "Downloaded bundle is missing MacOS binary directory."])
        }

        let binaries = (try? fileManager.contentsOfDirectory(at: macosDir, includingPropertiesForKeys: nil)) ?? []
        guard !binaries.isEmpty else {
            throw NSError(domain: "FramesUpdate", code: -5, userInfo: [NSLocalizedDescriptionKey: "Downloaded bundle does not contain any executable binary."])
        }
    }

    public static func resolveTargetAppURL() -> URL {
        let currentBundle = Bundle.main.bundleURL

        // If running from standard /Applications or user Applications, replace current bundle
        if currentBundle.path.hasPrefix("/Applications") || currentBundle.path.hasPrefix(NSHomeDirectory() + "/Applications") {
            return currentBundle
        }

        // If running from Xcode / DerivedData or temporary build directory during development,
        // and /Applications/frames.app exists, prioritize updating /Applications/frames.app
        let standardAppURL = URL(fileURLWithPath: "/Applications/frames.app")
        if FileManager.default.fileExists(atPath: standardAppURL.path) {
            return standardAppURL
        }

        return currentBundle
    }

    public static func executeRelaunchHelper(newAppURL: URL, targetAppURL: URL, currentPID: Int32) throws {
        let scriptContent = """
        #!/bin/bash
        set -e
        PID="\(currentPID)"
        NEW_APP="\(newAppURL.path)"
        DEST_APP="\(targetAppURL.path)"

        # Wait for old instance to exit cleanly
        for i in {1..150}; do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done

        # Atomic swap
        rm -rf "$DEST_APP"
        cp -R "$NEW_APP" "$DEST_APP"
        xattr -cr "$DEST_APP" 2>/dev/null || true

        # Clean staging directory
        STAGING_DIR="$(dirname "$NEW_APP")"
        rm -rf "$STAGING_DIR" 2>/dev/null || true

        # Relaunch updated application
        open -n "$DEST_APP"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("frames_updater_\(UUID().uuidString).sh")

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Spawn detached process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        try process.run()
    }
}

// MARK: - OTA Asset Downloader (Streaming Progress)

final class OTAAssetDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Double, Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadedFileURL: URL?

    func download(from url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (downloadTask.response?.expectedContentLength ?? -1)
        let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0.0
        onProgress?(progress, totalBytesWritten, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent("FramesAsset_\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: location, to: targetURL)
            self.downloadedFileURL = targetURL
            continuation?.resume(returning: targetURL)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
