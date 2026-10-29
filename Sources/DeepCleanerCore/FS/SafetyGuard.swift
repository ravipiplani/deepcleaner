import Darwin
import Foundation

/// Last line of defence before anything is removed. A path is only deletable when it lies
/// strictly inside one of the scan's allowed roots and is not a protected system or home location.
/// Paths are compared after resolving symlinks in the parent, so a link can't smuggle a deletion
/// outside the allowed roots.
public struct SafetyGuard: Sendable {
    public enum Violation: Error, LocalizedError, Equatable {
        case notAbsolute(String)
        case protectedPath(String)
        case outsideAllowedRoots(String)

        public var errorDescription: String? {
            switch self {
            case .notAbsolute(let p): "Not an absolute file path: \(p)"
            case .protectedPath(let p): "Protected location, refusing to delete: \(p)"
            case .outsideAllowedRoots(let p): "Outside the scanned folders, refusing to delete: \(p)"
            }
        }
    }

    public let allowedRoots: [String]
    let protectedExact: Set<String>
    let protectedSubtrees: [String]

    public init(
        allowedRoots: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appBundle: URL? = Bundle.main.bundleURL
    ) {
        let homePath = Self.canonical(home.path)
        self.allowedRoots = allowedRoots.map { Self.canonical($0.path) }

        let homeFolders = [
            "", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
            "Applications", "Public", "Library/Caches", "Library/Logs", "Library/Containers",
            "Library/Application Support", "Library/Developer", ".Trash",
        ]
        var exact = Set(["/", "/Users", "/Volumes", "/private", "/var", "/tmp"].map(Self.canonical))
        for folder in homeFolders {
            exact.insert(folder.isEmpty ? homePath : homePath + "/" + folder)
        }
        protectedExact = exact

        var subtrees = [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/private/var/db", "/Library",
            "/Applications", "/opt", "/cores",
        ].map(Self.canonical)
        subtrees += [
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Mobile Documents",
            "Library/Application Support/com.apple.TCC", "Library/Group Containers", "Library/Photos",
        ].map { homePath + "/" + $0 }
        if let appBundle, appBundle.pathExtension == "app" {
            subtrees.append(Self.canonical(appBundle.path))
        }
        protectedSubtrees = subtrees
    }

    public func validate(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw Violation.notAbsolute(url.path) }
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else {
            throw Violation.protectedPath(url.path)
        }
        let parent = Self.canonical(standardized.deletingLastPathComponent().path)
        let target = parent == "/" ? "/" + name : parent + "/" + name

        if protectedExact.contains(target) || protectedSubtrees.contains(where: { Self.isInside(target, $0, orEqual: true) }) {
            throw Violation.protectedPath(target)
        }
        guard allowedRoots.contains(where: { Self.isInside(target, $0, orEqual: false) }) else {
            throw Violation.outsideAllowedRoots(target)
        }
    }

    public func isAllowed(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }

    static func isInside(_ path: String, _ root: String, orEqual: Bool) -> Bool {
        if path == root { return orEqual }
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// `realpath` when the path exists (resolves symlinks like /var -> /private/var), else the standardized path.
    static func canonical(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
