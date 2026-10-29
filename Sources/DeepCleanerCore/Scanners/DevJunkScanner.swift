import Foundation

/// Package-manager and IDE caches, plus `node_modules` folders inside project directories.
public struct DevJunkScanner: Sendable {
    public var projectRoots: [URL]
    public var home: URL
    /// node_modules in projects untouched for longer than this are pre-selected.
    public var staleProjectAge: TimeInterval = 30 * 86_400

    public init(projectRoots: [URL] = DevJunkScanner.defaultProjectRoots(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.projectRoots = projectRoots
        self.home = home
    }

    public static func defaultProjectRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Development", "Projects", "Code", "code", "dev", "src", "workspace", "Developer", "GitHub"]
            .map { home.appendingPathComponent($0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
    }

    public func scan(progress: ScanProgress) async -> ScanResult {
        let rules = JunkRules.developer(home: home)
        async let caches = RuleScanner(rules: rules).scan(progress: progress)
        async let modules = nodeModules(progress: progress)
        var items = await caches.items + modules
        if let docker = dockerItem() { items.append(docker) }
        return ScanResult(items: items, allowedRoots: rules.map(\.root) + projectRoots)
    }

    func nodeModules(progress: ScanProgress) async -> [ScanItem] {
        let found = projectRoots.flatMap { Self.findNodeModules(in: $0, progress: progress) }
        let staleCutoff = Date().addingTimeInterval(-staleProjectAge)
        return await withTaskGroup(of: ScanItem?.self) { group in
            for url in found {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    progress.setCurrentPath(url.path)
                    let size = SizeCalculator.allocatedSize(of: url, progress: progress)
                    guard size > 0 else { return nil }
                    let project = url.deletingLastPathComponent()
                    let modified = Self.projectLastModified(project)
                    return ScanItem(
                        url: url, size: size, category: .nodeModules, lastUsed: modified,
                        displayName: project.lastPathComponent, note: url.path,
                        selectedByDefault: modified.map { $0 < staleCutoff } ?? false
                    )
                }
            }
            return await group.reduce(into: []) { if let item = $1 { $0.append(item) } }
        }
    }

    /// Top-most node_modules folders below `root`; nested ones are covered by their parent.
    static func findNodeModules(in root: URL, progress: ScanProgress) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true else {
                continue
            }
            if url.lastPathComponent == "node_modules" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        progress.setCurrentPath(root.path)
        return found
    }

    /// Latest modification among the project's top-level entries (excluding node_modules itself).
    static func projectLastModified(_ project: URL) -> Date? {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        )) ?? []
        return children
            .filter { $0.lastPathComponent != "node_modules" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    func dockerItem() -> ScanItem? {
        let raw = home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        let size = SizeCalculator.allocatedSize(of: raw)
        guard size > 0 else { return nil }
        return ScanItem(
            url: raw, size: size, category: .dockerData,
            note: "Reclaim with `docker system prune -a` — DeepCleaner won't touch Docker's disk image"
        )
    }
}

/// Convenience wrapper so system junk mirrors the developer scanner's API.
public struct SystemJunkScanner: Sendable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan(progress: ScanProgress) async -> ScanResult {
        await RuleScanner(rules: JunkRules.system(home: home)).scan(progress: progress)
    }
}
