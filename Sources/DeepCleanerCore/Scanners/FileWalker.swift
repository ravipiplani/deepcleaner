import Foundation

/// A regular file found while walking user folders.
public struct WalkedFile: Sendable {
    public let url: URL
    public let size: Int64
    public let modified: Date?
    public let accessed: Date?
    public let created: Date?
    public let linkCount: Int
}

/// Walks user folders for regular files, skipping hidden items, package contents, symlinks
/// and excluded subtrees. Top-level children of each root are walked in parallel.
public struct FileWalker: Sendable {
    public var roots: [URL]
    public var excluded: [URL]
    public var minSize: Int64

    static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey, .creationDateKey, .linkCountKey,
    ]

    public init(roots: [URL], excluded: [URL] = [], minSize: Int64 = 0) {
        self.roots = roots
        self.excluded = excluded
        self.minSize = minSize
    }

    public func walk(progress: ScanProgress) async -> [WalkedFile] {
        let excludedPaths = Set(excluded.map { $0.standardizedFileURL.path })
        let tops = roots.flatMap { root -> [URL] in
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles]
            )) ?? []
        }
        return await withTaskGroup(of: [WalkedFile].self) { group in
            for top in tops where !excludedPaths.contains(top.standardizedFileURL.path) {
                group.addTask { walkTree(top, excludedPaths: excludedPaths, progress: progress) }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    func walkTree(_ top: URL, excludedPaths: Set<String>, progress: ScanProgress) -> [WalkedFile] {
        var found: [WalkedFile] = []
        if let file = file(at: top) { return file.size >= minSize ? [file] : [] }
        guard (try? top.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])).map({
            $0.isDirectory == true && $0.isSymbolicLink != true && $0.isPackage != true
        }) == true else { return [] }

        progress.setCurrentPath(top.path)
        guard let enumerator = FileManager.default.enumerator(
            at: top, includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }

        var count = 0
        for case let url as URL in enumerator {
            count += 1
            if count & 1023 == 0 {
                if Task.isCancelled { break }
                progress.add(files: 1024)
            }
            if excludedPaths.contains(url.standardizedFileURL.path) {
                enumerator.skipDescendants()
                continue
            }
            if let file = file(at: url), file.size >= minSize {
                found.append(file)
            }
        }
        progress.add(files: count & 1023)
        return found
    }

    func file(at url: URL) -> WalkedFile? {
        guard let v = try? url.resourceValues(forKeys: Set(Self.keys)),
              v.isRegularFile == true, v.isSymbolicLink != true
        else { return nil }
        return WalkedFile(
            url: url,
            size: Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0),
            modified: v.contentModificationDate,
            accessed: v.contentAccessDate,
            created: v.creationDate,
            linkCount: v.linkCount ?? 1
        )
    }
}
