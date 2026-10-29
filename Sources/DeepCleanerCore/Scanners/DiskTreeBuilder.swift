import Foundation

/// A folder or file in the Space Lens tree. Items below `DiskTreeBuilder.minNodeSize`
/// are folded into one aggregate "smaller items" node per folder to bound memory.
public struct DiskNode: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let url: URL?
    public var size: Int64
    public let isDirectory: Bool
    public var children: [DiskNode]
    public var isAggregate: Bool { url == nil }

    /// Removes the descendant with `id`, updating sizes along the way. Returns the removed size.
    @discardableResult
    public mutating func remove(id target: String) -> Int64? {
        if let index = children.firstIndex(where: { $0.id == target }) {
            let removed = children.remove(at: index).size
            size -= removed
            return removed
        }
        for index in children.indices where target.hasPrefix(children[index].id + "/") {
            if let removed = children[index].remove(id: target) {
                size -= removed
                return removed
            }
        }
        return nil
    }

    public func node(withID target: String) -> DiskNode? {
        if id == target { return self }
        for child in children where target == child.id || target.hasPrefix(child.id + "/") {
            return child.node(withID: target)
        }
        return nil
    }
}

public struct DiskTreeBuilder: Sendable {
    public var minNodeSize: Int64
    /// Levels below the root that are scanned with one task per child.
    public var parallelDepth: Int

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    public init(minNodeSize: Int64 = 1_000_000, parallelDepth: Int = 2) {
        self.minNodeSize = minNodeSize
        self.parallelDepth = parallelDepth
    }

    public func build(_ url: URL, progress: ScanProgress) async -> DiskNode {
        await node(url, depth: 0, progress: progress)
    }

    func node(_ url: URL, depth: Int, progress: ScanProgress) async -> DiskNode {
        guard depth < parallelDepth, let children = directoryChildren(url) else {
            return syncNode(url, progress: progress)
        }
        progress.setCurrentPath(url.path)
        let built = await withTaskGroup(of: DiskNode.self) { group in
            for child in children {
                group.addTask { await node(child, depth: depth + 1, progress: progress) }
            }
            return await group.reduce(into: [DiskNode]()) { $0.append($1) }
        }
        return directoryNode(url, children: built)
    }

    func syncNode(_ url: URL, progress: ScanProgress) -> DiskNode {
        if let children = directoryChildren(url) {
            if Task.isCancelled { return directoryNode(url, children: []) }
            return directoryNode(url, children: children.map { syncNode($0, progress: progress) })
        }
        let v = try? url.resourceValues(forKeys: Set(Self.keys))
        let size = v?.isSymbolicLink == true ? 0 : Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        progress.add(bytes: size)
        return DiskNode(id: url.path, name: url.lastPathComponent, url: url, size: size, isDirectory: false, children: [])
    }

    /// Children of a real (non-symlink) directory, or nil for files.
    func directoryChildren(_ url: URL) -> [URL]? {
        guard let v = try? url.resourceValues(forKeys: Set(Self.keys)), v.isDirectory == true, v.isSymbolicLink != true else {
            return nil
        }
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])) ?? []
    }

    func directoryNode(_ url: URL, children: [DiskNode]) -> DiskNode {
        let total = children.reduce(0) { $0 + $1.size }
        var kept = children.filter { $0.size >= minNodeSize }.sorted { $0.size > $1.size }
        let small = children.filter { $0.size < minNodeSize }
        let smallTotal = small.reduce(0) { $0 + $1.size }
        if smallTotal > 0 {
            kept.append(DiskNode(
                id: url.path + "/\u{0}smaller", name: "\(small.count) smaller items", url: nil,
                size: smallTotal, isDirectory: false, children: []
            ))
        }
        return DiskNode(id: url.path, name: url.lastPathComponent, url: url, size: total, isDirectory: true, children: kept)
    }
}
