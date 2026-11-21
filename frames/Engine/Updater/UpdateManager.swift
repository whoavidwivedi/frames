import Foundation
import SwiftUI
import AppKit
import CryptoKit
import Security

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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6.8"
    }

    public var currentVersion: SemanticVersion {
        SemanticVersion(string: currentVersionString) ?? SemanticVersion(major: 1, minor: 6, patch: 8)
    }

    public var hasUpdate: Bool {
        availableUpdate != nil && (status != .idle)
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        Self.cleanupStaleUpdateDirectories()
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
                // Keep the checking state visible long enough for the spinner to render.
                if manual {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
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
            let checksumAsset = release.assets.first(where: { $0.isChecksumManifest })

            let update = AppUpdateInfo(
                tagName: release.tagName,
                version: releaseVersion,
                title: release.name ?? "Frames \(release.tagName)",
                releaseNotes: release.body ?? "General improvements and optimizations.",
                releasePageURL: releasePageURL,
                publishedDate: publishedDate,
                asset: matchedAsset,
                checksumManifestAsset: checksumAsset,
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
        guard let update = availableUpdate,
              let assetDownloadURL = URL(string: update.asset.browserDownloadUrl),
              let manifestAsset = update.checksumManifestAsset,
              let manifestURL = URL(string: manifestAsset.browserDownloadUrl),
              Self.isSecureHTTPS(assetDownloadURL),
              Self.isSecureHTTPS(manifestURL) else {
            status = .error(message: "The update package is missing a verifiable HTTPS download URL or SHA-256 manifest. Refusing to install.")
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

                let downloadedArchiveURL = try await downloader.download(from: assetDownloadURL)

                try Task.checkCancellation()

                // Authenticate the archive before it is opened by any extractor.
                self.status = .extracting
                try await Self.verifyArchive(downloadedArchiveURL, against: update.asset.name, manifestURL: manifestURL)

                try Task.checkCancellation()

                let extractDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FramesUpdate_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // Native extraction via /usr/bin/ditto (preserves macOS bundle metadata & permissions)
                try await Self.extractArchive(at: downloadedArchiveURL, to: extractDir)
                try? FileManager.default.removeItem(at: downloadedArchiveURL)

                // Locate application bundle in extracted directory
                guard let newAppBundleURL = Self.findAppBundle(in: extractDir) else {
                    throw NSError(
                        domain: "FramesUpdate",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Application bundle could not be found in downloaded update."]
                    )
                }

                // Structural integrity plus a valid Developer ID signature are both required.
                try Self.verifyAppBundle(at: newAppBundleURL)
                try Self.verifyDeveloperIDSignature(at: newAppBundleURL)

                self.status = .readyToRestart

                // Determine target app destination
                let targetAppURL = Self.resolveTargetAppURL()

                // Swap the bundle and launch the new instance without generating shell code.
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

        // Only the expected bundle name is accepted. Archive-derived names are
        // untrusted and must never influence a path used for installation.
        func expectedApp(in dir: URL) -> URL? {
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                return nil
            }
            return contents.first { candidate in
                candidate.pathExtension.lowercased() == "app"
                    && candidate.deletingPathExtension().lastPathComponent.lowercased() == "frames"
            }
        }

        if let direct = expectedApp(in: directory) { return direct }

        if let subdirs = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for sub in subdirs {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue,
                   let nested = expectedApp(in: sub) {
                    return nested
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
        let standardized = currentBundle.standardizedFileURL.path
        let applicationsRoot = "/Applications/"
        let userApplicationsRoot = NSHomeDirectory() + "/Applications/"

        if standardized.hasPrefix(applicationsRoot) || standardized.hasPrefix(userApplicationsRoot) {
            return currentBundle
        }

        // Development builds update themselves. They must never implicitly
        // replace an application in /Applications.
        return currentBundle
    }

    /// Replaces the installed bundle and relaunches it without constructing a
    /// shell script from external input. All paths are validated and FileManager
    /// APIs are used, so archive-derived names cannot become shell commands.
    public static func executeRelaunchHelper(newAppURL: URL, targetAppURL: URL, currentPID: Int32) throws {
        let fileManager = FileManager.default

        guard newAppURL.pathExtension.lowercased() == "app",
              targetAppURL.pathExtension.lowercased() == "app",
              newAppURL.lastPathComponent.lowercased() == "frames.app",
              targetAppURL.lastPathComponent.lowercased() == "frames.app" else {
            throw updateError(code: -6, message: "Update paths failed validation.")
        }

        let targetPath = targetAppURL.standardizedFileURL.path
        let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
        let isInstalledLocation = targetPath.hasPrefix("/Applications/")
            || targetPath.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard isInstalledLocation || targetPath == currentPath else {
            throw updateError(code: -7, message: "Update target is outside the allowed application directories.")
        }

        guard fileManager.fileExists(atPath: newAppURL.path) else {
            throw updateError(code: -8, message: "Staged update bundle is missing.")
        }

        let backupURL = fileManager.temporaryDirectory
            .appendingPathComponent("FramesUpdateBackup_\(UUID().uuidString).app")

        if fileManager.fileExists(atPath: targetPath) {
            try fileManager.moveItem(atPath: targetPath, toPath: backupURL.path)
        }

        do {
            try fileManager.copyItem(at: newAppURL, to: targetAppURL)
        } catch {
            // Restore the previous installation if the new bundle could not be copied.
            if fileManager.fileExists(atPath: backupURL.path) && !fileManager.fileExists(atPath: targetPath) {
                try? fileManager.moveItem(atPath: backupURL.path, toPath: targetPath)
            }
            throw error
        }

        // Launch the replacement via an explicit argv array; no shell is involved.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", targetAppURL.path]
        try process.run()

        // The staging and backup directories are removed on the next launch by
        // `cleanupStaleUpdateDirectories()` so the old bundle can finish exiting.
    }

    /// Removes update staging directories left by a previous relaunch.
    public static func cleanupStaleUpdateDirectories() {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory
        guard let contents = try? fileManager.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) else {
            return
        }
        for item in contents where item.lastPathComponent.hasPrefix("FramesUpdate_")
            || item.lastPathComponent.hasPrefix("FramesUpdateBackup_") {
            try? fileManager.removeItem(at: item)
        }
    }

    // MARK: - Update Verification

    private static func updateError(code: Int, message: String) -> NSError {
        NSError(domain: "FramesUpdate", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func isSecureHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// Fetches the published SHA-256 manifest and verifies the downloaded archive
    /// before any extraction occurs.
    public static func verifyArchive(_ archiveURL: URL, against assetName: String, manifestURL: URL) async throws {
        guard isSecureHTTPS(manifestURL) else {
            throw updateError(code: -9, message: "Checksum manifest URL is not HTTPS.")
        }

        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw updateError(code: -10, message: "Unable to fetch the release checksum manifest.")
        }
        guard let manifest = String(data: data, encoding: .utf8) else {
            throw updateError(code: -11, message: "Checksum manifest is not valid UTF-8.")
        }
        guard let expected = expectedChecksum(from: manifest, for: assetName) else {
            throw updateError(code: -12, message: "No SHA-256 entry found for the selected update asset.")
        }

        let actual = try sha256Hex(of: archiveURL)
        guard actual == expected else {
            throw updateError(
                code: -13,
                message: "Update checksum mismatch. Expected \(expected), got \(actual). The package was not installed."
            )
        }
    }

    /// Parses a `shasum` compatible manifest. Only the file name and a 64-character
    /// hex digest are consumed; no path from the manifest is used for file access.
    public static func expectedChecksum(from manifest: String, for fileName: String) -> String? {
        let target = (fileName as NSString).lastPathComponent
        for line in manifest.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let digest = String(fields[0]).lowercased()
            let name = (String(fields[1]) as NSString).lastPathComponent
            guard name == target,
                  digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit }) else { continue }
            return digest
        }
        return nil
    }

    /// Streams the file through SHA-256 so large archives are not loaded into memory.
    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    /// Requires a valid Developer ID Application signature with all nested code
    /// and all architectures validated. Ad-hoc and unsigned bundles are rejected.
    public static func verifyDeveloperIDSignature(at bundleURL: URL) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(rawValue: 0), &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw updateError(code: -14, message: "Unable to read the update bundle's code signature.")
        }

        // Developer ID Application certificates are issued by a WWDR intermediate
        // (1.2.840.113635.100.6.2.6) and carry the Developer ID Application OID
        // (1.2.840.113635.100.6.1.13). The .1.9 OID identifies Mac App Store
        // signing, so it must not be used here. Pin the bundle identifier and the
        // expected team as well, so an unrelated Developer ID-signed app cannot be
        // installed as an update even if an attacker replaces the archive and checksum.
        let teamID = (Bundle.main.object(forInfoDictionaryKey: "FramesDeveloperTeamID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard teamID.count == 10, teamID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw updateError(code: -17, message: "Developer ID team ID is not configured for this build.")
        }
        let requirementText = "anchor apple generic and identifier \"whoavidwivedi.frames\" "
            + "and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
            + "and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(rawValue: 0),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let req = requirement else {
            throw updateError(code: -15, message: "Unable to construct the code signing requirement.")
        }

        var verificationError: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let validity = SecStaticCodeCheckValidityWithErrors(code, flags, req, &verificationError)
        guard validity == errSecSuccess else {
            var detail = "unknown signing error"
            if let cfError = verificationError, let description = CFErrorCopyDescription(cfError.takeUnretainedValue()) {
                detail = description as String
            }
            throw updateError(code: -16, message: "Update bundle signature is invalid: \(detail)")
        }
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
