import Foundation

// MARK: - GitHub API Data Transfer Objects

public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String?
    public let publishedAt: String?
    public let prerelease: Bool?
    public let draft: Bool?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlUrl: String? = nil,
        publishedAt: String? = nil,
        prerelease: Bool? = false,
        draft: Bool? = false,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlUrl = htmlUrl
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.draft = draft
        self.assets = assets
    }
}

public struct GitHubReleaseAsset: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int64
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public init(
        id: Int,
        name: String,
        browserDownloadUrl: String,
        size: Int64,
        contentType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.browserDownloadUrl = browserDownloadUrl
        self.size = size
        self.contentType = contentType
    }

    public var isZipPayload: Bool {
        return name.lowercased().hasSuffix(".zip")
    }

    public var isDmgPayload: Bool {
        return name.lowercased().hasSuffix(".dmg")
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Application Update Presentation Models

public struct AppUpdateInfo: Sendable, Identifiable {
    public var id: String { tagName }
    public let tagName: String
    public let version: SemanticVersion
    public let title: String
    public let releaseNotes: String
    public let releasePageURL: URL?
    public let publishedDate: Date?
    public let asset: GitHubReleaseAsset

    public init(
        tagName: String,
        version: SemanticVersion,
        title: String,
        releaseNotes: String,
        releasePageURL: URL?,
        publishedDate: Date?,
        asset: GitHubReleaseAsset
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.releaseNotes = releaseNotes
        self.releasePageURL = releasePageURL
        self.publishedDate = publishedDate
        self.asset = asset
    }
}

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedVersion: String)
    case available(info: AppUpdateInfo)
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case extracting
    case readyToRestart
    case error(message: String)

    public static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.checking, .checking),
             (.extracting, .extracting),
             (.readyToRestart, .readyToRestart):
            return true
        case (.upToDate(let a), .upToDate(let b)):
            return a == b
        case (.available(let a), .available(let b)):
            return a.tagName == b.tagName
        case (.downloading(let p1, let b1, let t1), .downloading(let p2, let b2, let t2)):
            return abs(p1 - p2) < 0.001 && b1 == b2 && t1 == t2
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

public struct ManualCheckNotice: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let isError: Bool

    public init(title: String, message: String, isError: Bool = false) {
        self.title = title
        self.message = message
        self.isError = isError
    }
}
