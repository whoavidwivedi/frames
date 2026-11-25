import Foundation
import Darwin
import SwiftUI
import AppKit
import CryptoKit
import Security

/// The code-signing posture of an app bundle.
///
/// `.developerID` bundles are Apple-anchored and can be verified against the
/// publisher's Developer ID identity. `.unsignedAdhoc` bundles are locally
/// signed only; they are accepted by OTA only after explicit user consent.
/// `.invalid` means the bundle has no usable signature and is never accepted.
public enum UpdateSignaturePolicy: Sendable, Equatable {
    case developerID
    case unsignedAdhoc
    case invalid
}

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
        if case .readyToRestart = status { return }
        cancelDownload()
        activeCheckTask?.cancel()
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

    private var activeCheckTask: Task<Void, Never>?
    private var downloadID: UUID?
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }

    public var currentVersion: SemanticVersion {
        SemanticVersion(string: currentVersionString) ?? SemanticVersion(major: 2)
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
        if case .readyToRestart = status { return }

        status = .checking
        if manual {
            manualCheckNotice = nil
        }

        let channel = updateChannel
        activeCheckTask = Task {
            do {
                let release = try await self.fetchRelease(for: channel)
                try Task.checkCancellation()
                self.lastCheckedDate = Date()
                self.processRelease(release, manual: manual)
            } catch {
                guard !Task.isCancelled else { return }
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
            let nonDraftReleases = releases.filter { !($0.draft ?? false) }
            // Prefer the newest prerelease when one is published; otherwise
            // fall back to the latest stable release.
            guard let release = nonDraftReleases.first(where: { $0.prerelease ?? false }) ?? nonDraftReleases.first else {
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
        availableUpdate = nil
        isUpdatePromptPresented = false
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
            let archiveName = "Frames-\(release.tagName)-macOS.zip"
            guard let matchedAsset = release.assets.first(where: { $0.name == archiveName }),
                  let checksumAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
                self.status = .idle
                if manual {
                    self.manualCheckNotice = ManualCheckNotice(
                        title: "Update Available",
                        message: "Frames \(release.tagName) is on GitHub. Its verified macOS ZIP is unavailable."
                    )
                }
                return
            }

            var publishedDate: Date? = nil
            if let pubStr = release.publishedAt {
                let isoFormatter = ISO8601DateFormatter()
                publishedDate = isoFormatter.date(from: pubStr)
            }

            let releasePageURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/tag/\(release.tagName)")

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
        if case .readyToRestart = status { return }
        downloadID = nil
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
        guard activeDownloadTask == nil else { return }
        guard let update = availableUpdate,
              let assetDownloadURL = URL(string: update.asset.browserDownloadUrl),
              let manifestAsset = update.checksumManifestAsset,
              let manifestURL = URL(string: manifestAsset.browserDownloadUrl),
              assetDownloadURL.absoluteString == "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/download/\(update.tagName)/\(update.asset.name)",
              manifestURL.absoluteString == "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/download/\(update.tagName)/SHA256SUMS.txt" else {
            status = .error(message: "The update package is missing a verifiable HTTPS download URL or SHA-256 manifest. Refusing to install.")
            return
        }

        downloadProgress = 0.0
        downloadedBytes = 0
        totalBytes = update.asset.size
        status = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: totalBytes)

        let id = UUID()
        downloadID = id
        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if downloadID == id {
                    activeDownloadTask = nil
                    downloadID = nil
                }
            }
            do {
                let downloader = OTAAssetDownloader { [weak self] progress, written, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadID == id, case .downloading = self.status else { return }
                        self.downloadProgress = progress
                        self.downloadedBytes = written
                        self.totalBytes = total
                        self.status = .downloading(progress: progress, bytesWritten: written, totalBytes: total)
                    }
                }
                let (downloadedArchiveURL, response) = try await URLSession.shared.download(from: assetDownloadURL, delegate: downloader)
                defer { try? FileManager.default.removeItem(at: downloadedArchiveURL) }
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw Self.updateError(code: -1, message: "The release archive download failed.")
                }

                self.status = .extracting
                try await Self.verifyArchive(downloadedArchiveURL, against: update.asset.name, manifestURL: manifestURL)

                try Task.checkCancellation()

                let extractDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FramesUpdate_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                defer { try? FileManager.default.removeItem(at: extractDir) }

                // Native extraction via /usr/bin/ditto (preserves macOS bundle metadata & permissions)
                try await Self.extractArchive(at: downloadedArchiveURL, to: extractDir)
                try Task.checkCancellation()

                // Locate application bundle in extracted directory
                guard let newAppBundleURL = Self.findAppBundle(in: extractDir) else {
                    throw NSError(
                        domain: "FramesUpdate",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Application bundle could not be found in downloaded update."]
                    )
                }

                // Structural integrity is always required. Signed releases use the
                // strict Developer ID policy; ad-hoc releases require explicit
                // consent and remain unsigned after installation.
                try Self.verifyAppBundle(at: newAppBundleURL, expectedVersion: update.version)
                let downloadedPolicy = Self.signaturePolicy(for: newAppBundleURL)
                let installedPolicy = Self.signaturePolicy(for: Bundle.main.bundleURL)

                switch downloadedPolicy {
                case .developerID:
                    try Self.verifyDeveloperIDSignature(at: newAppBundleURL)
                case .unsignedAdhoc:
                    // Older unsigned release jobs built with CODE_SIGNING_ALLOWED=NO,
                    // so those installs classify as `.invalid` rather than `.unsignedAdhoc`.
                    // They carry no certificate chain, so allow that one-time migration to
                    // an ad-hoc signed build. A Developer ID install must never be
                    // downgraded to an unsigned update.
                    guard installedPolicy != .developerID else {
                        throw Self.updateError(
                            code: -18,
                            message: "A Developer ID signed installation cannot be downgraded to an unsigned update."
                        )
                    }
                    try Self.verifyAdHocSignature(at: newAppBundleURL)
                    guard Self.confirmUnsignedUpdate() else {
                        self.status = .available(info: update)
                        self.isUpdatePromptPresented = false
                        self.downloadProgress = 0.0
                        self.downloadedBytes = 0
                        self.totalBytes = 0
                        return
                    }
                case .invalid:
                    throw Self.updateError(
                        code: -19,
                        message: "The update bundle is neither Developer ID signed nor ad-hoc signed. Refusing to install."
                    )
                }

                self.status = .readyToRestart

                // Determine target app destination
                let targetAppURL = Self.resolveTargetAppURL()

                // Swap the bundle and launch the new instance without generating shell code.
                try await Self.replaceAndLaunch(newAppURL: newAppBundleURL, targetAppURL: targetAppURL)

                // Terminate current instance cleanly
                NSApp.terminate(nil)
            } catch {
                guard !Task.isCancelled, downloadID == id else { return }
                self.status = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Archive & Bundle Helper Routines

    nonisolated public static func extractArchive(at zipURL: URL, to destDir: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipURL.path, destDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw updateError(code: -2, message: "The downloaded ZIP could not be extracted.")
            }
        }.value
    }

    public static func findAppBundle(in directory: URL) -> URL? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        return contents?.first { item in
            let values = try? item.resourceValues(forKeys: keys)
            return item.lastPathComponent.lowercased() == "frames.app" && values?.isDirectory == true && values?.isSymbolicLink == false
        }
    }

    public static func verifyAppBundle(at bundleURL: URL, expectedVersion: SemanticVersion? = nil) throws {
        guard let bundle = Bundle(url: bundleURL), bundle.bundleIdentifier == "whoavidwivedi.frames",
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw updateError(code: -3, message: "The release does not contain a valid Frames application.")
        }
        if let expectedVersion {
            guard let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  SemanticVersion(string: raw) == expectedVersion else {
                throw updateError(code: -4, message: "The downloaded application version differs from its release tag.")
            }
        }
    }

    public static func resolveTargetAppURL() -> URL { Bundle.main.bundleURL }

    /// Stage the entire replacement on the installation volume. APFS exchanges
    /// both directory entries atomically, including during rollback.
    private static func replaceAndLaunch(newAppURL: URL, targetAppURL: URL) async throws {
        let fm = FileManager.default
        let parent = targetAppURL.deletingLastPathComponent()
        guard targetAppURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL,
              targetAppURL.pathExtension.lowercased() == "app" else {
            throw updateError(code: -7, message: "The current application could not be located.")
        }
        let stage = parent.appendingPathComponent(".FramesUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            throw updateError(code: -8, message: "Move Frames to a writable Applications folder and try again.")
        }
        let backup = stage.appendingPathComponent("Frames.app")
        var retainBackup = false
        defer { if !retainBackup { try? fm.removeItem(at: stage) } }
        try fm.copyItem(at: newAppURL, to: backup)
        try exchangeBundles(at: backup, and: targetAppURL)
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            _ = try await NSWorkspace.shared.openApplication(at: targetAppURL, configuration: config)
        } catch {
            do {
                try exchangeBundles(at: backup, and: targetAppURL)
            } catch {
                retainBackup = true
                throw updateError(code: -26, message: "The new version could not launch. Your previous installation is at \(backup.path).")
            }
            throw updateError(code: -25, message: "macOS could not launch the update. Your previous installation was restored. You can also install this release from GitHub.")
        }
    }

    nonisolated static func exchangeBundles(at first: URL, and second: URL) throws {
        guard renamex_np(first.path, second.path, UInt32(RENAME_SWAP)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: - Update Verification

    /// Classifies a bundle by its actual code signature rather than trusting the
    /// bundle name or release metadata. Certificate-bearing bundles are treated as
    /// signed; certificate-free bundles must also pass full signature validation
    /// before they are considered ad-hoc signed.
    public static func signaturePolicy(for bundleURL: URL) -> UpdateSignaturePolicy {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return .invalid
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signingInfo = info as? [String: Any] else {
            return .invalid
        }

        if let certificates = signingInfo[kSecCodeInfoCertificates as String] as? [Any],
           !certificates.isEmpty {
            return .developerID
        }

        var verificationError: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let validity = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &verificationError)
        return validity == errSecSuccess ? .unsignedAdhoc : .invalid
    }

    /// Verifies the weaker policy used only for unsigned releases. This never
    /// accepts a certificate-bearing bundle, so a mismatched Developer ID cannot
    /// silently fall back to the ad-hoc path.
    public static func verifyAdHocSignature(at bundleURL: URL) throws {
        switch signaturePolicy(for: bundleURL) {
        case .unsignedAdhoc:
            guard codeSigningIdentifier(for: bundleURL) == "whoavidwivedi.frames" else {
                throw updateError(
                    code: -24,
                    message: "The unsigned update has an unexpected code-signing identifier. Refusing to install."
                )
            }
        case .developerID:
            throw updateError(
                code: -20,
                message: "This update is Developer ID signed and must use the signed verification path."
            )
        case .invalid:
            throw updateError(
                code: -21,
                message: "The update bundle has no valid ad-hoc code signature. Refusing to install."
            )
        }
    }

    private static func codeSigningIdentifier(for bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return nil
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signingInfo = info as? [String: Any] else {
            return nil
        }
        return signingInfo[kSecCodeInfoIdentifier as String] as? String
    }

    /// Explicit consent for builds that cannot prove Apple-issued publisher identity.
    @MainActor
    private static func confirmUnsignedUpdate() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Install unsigned Frames update?"
        alert.informativeText = """
        This update has a valid checksum and bundle identity, but it is not signed with an Apple Developer ID and has not been notarized. macOS cannot verify the publisher.

        Only continue if you trust the Frames GitHub release.
        """
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Install Update")
        return alert.runModal() == .alertSecondButtonReturn
    }

    nonisolated private static func updateError(code: Int, message: String) -> NSError {
        NSError(domain: "FramesUpdate", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    nonisolated private static func isSecureHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// Fetches the published SHA-256 manifest and verifies the downloaded archive
    /// before any extraction occurs.
    nonisolated public static func verifyArchive(_ archiveURL: URL, against assetName: String, manifestURL: URL) async throws {
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
    nonisolated public static func expectedChecksum(from manifest: String, for fileName: String) -> String? {
        let matches = manifest.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == fileName || fields[1] == "*\(fileName)" else { return nil }
            let digest = fields[0].lowercased()
            return digest.utf8.count == 64 && digest.allSatisfy { $0.isASCII && $0.isHexDigit } ? digest : nil
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Streams the file through SHA-256 so large archives are not loaded into memory.
    nonisolated public static func sha256Hex(of fileURL: URL) throws -> String {
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

private final class OTAAssetDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double, Int64, Int64) -> Void

    init(progress: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.progress = progress
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite
        progress(total > 0 ? Double(totalBytesWritten) / Double(total) : 0, totalBytesWritten, total)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async download API delivers the file URL to the awaiting task.
    }
}
