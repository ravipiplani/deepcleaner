import Foundation

/// A published DeepCleaner release.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL
    /// The DMG asset, when the release has one.
    public let downloadURL: URL?
    /// The auto-generated "What's Changed" section, without the install boilerplate.
    public let changes: String?
}

/// A dotted numeric version such as `0.1.12`. Leading `v` and pre-release suffixes are ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing components count as zero, so `0.1` == `0.1.0`.
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// Checks GitHub Releases for a newer build. Only reads public release metadata; nothing is
/// downloaded or installed automatically.
public struct UpdateChecker: Sendable {
    public static let repository = "ravipiplani/deepcleaner"

    public var latestReleaseURL = URL(string: "https://api.github.com/repos/\(UpdateChecker.repository)/releases/latest")!
    public var session: URLSession = .shared

    public init() {}

    public enum Failure: LocalizedError {
        case badResponse(Int)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .badResponse(let status): "GitHub answered with status \(status)."
            case .unreadable: "The release information couldn't be read."
            }
        }
    }

    /// The latest release if it is newer than `current`, otherwise nil.
    public func newerRelease(than current: AppVersion, appVersion: String) async throws -> ReleaseInfo? {
        let latest = try await latestRelease(appVersion: appVersion)
        return latest.version > current ? latest : nil
    }

    public func latestRelease(appVersion: String) async throws -> ReleaseInfo {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeepCleaner/\(appVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.badResponse(http.statusCode)
        }
        guard let release = Self.parse(data) else { throw Failure.unreadable }
        return release
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: URL
            }

            var tag_name: String
            var html_url: URL
            var body: String?
            var draft: Bool?
            var prerelease: Bool?
            var assets: [Asset]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name) else { return nil }
        let dmg = payload.assets?.first { $0.name.hasSuffix(".dmg") }
        return ReleaseInfo(
            version: version, pageURL: payload.html_url, downloadURL: dmg?.browser_download_url,
            changes: payload.body.flatMap(changes(in:))
        )
    }

    /// Pulls the bullet list GitHub generates under "What's Changed".
    static func changes(in body: String) -> String? {
        guard let start = body.range(of: "## What's Changed") else { return nil }
        var section = body[start.upperBound...]
        if let end = section.range(of: "**Full Changelog**") { section = section[..<end.lowerBound] }
        let text = section.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
