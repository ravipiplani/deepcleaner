import CryptoKit
import Foundation

/// Finds byte-identical files: group by size, then by a hash of the first and last 64 KB,
/// then by a full SHA-256. Hard links to the same file are not treated as duplicates.
public struct DuplicateScanner: Sendable {
    public var roots: [URL]
    public var excluded: [URL]
    public var minSize: Int64

    static let sampleSize = 64 * 1024
    static let chunkSize = 1024 * 1024

    public init(
        roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser],
        excluded: [URL]? = nil,
        minSize: Int64 = 1_000_000
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = roots
        self.excluded = excluded ?? [home.appendingPathComponent("Library"), home.appendingPathComponent(".Trash")]
        self.minSize = minSize
    }

    public func scan(progress: ScanProgress) async -> ScanResult {
        let files = await FileWalker(roots: roots, excluded: excluded, minSize: minSize).walk(progress: progress)

        // Drop extra hard links so the same inode never appears twice.
        var seen = Set<SizeCalculator.FileID>()
        let unique = files.filter { file in
            guard file.linkCount > 1, let id = SizeCalculator.fileID(atPath: file.url.path) else { return true }
            return seen.insert(id).inserted
        }

        let sizeGroups = Dictionary(grouping: unique, by: \.size).values.filter { $0.count > 1 }
        let groups = await withTaskGroup(of: [[WalkedFile]].self) { group in
            for candidates in sizeGroups {
                group.addTask {
                    guard !Task.isCancelled else { return [] }
                    progress.setCurrentPath(candidates[0].url.path)
                    return Self.confirmDuplicates(candidates)
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }

        var items: [ScanItem] = []
        for files in groups {
            // Keep the oldest copy (shortest path breaks ties); select the rest.
            let sorted = files.sorted {
                let a = $0.created ?? .distantFuture, b = $1.created ?? .distantFuture
                return a != b ? a < b : $0.url.path.count < $1.url.path.count
            }
            let groupID = "dup:" + sorted[0].url.path
            let title = "\(sorted[0].url.lastPathComponent) — \(sorted.count) copies"
            for (index, file) in sorted.enumerated() {
                items.append(ScanItem(
                    url: file.url, size: file.size, category: .duplicate, lastUsed: file.modified,
                    note: index == 0 ? "Original (kept) · \(file.url.deletingLastPathComponent().path)" : nil,
                    groupID: groupID, groupTitle: title, selectedByDefault: index != 0
                ))
            }
        }
        return ScanResult(items: items, allowedRoots: roots)
    }

    static func confirmDuplicates(_ candidates: [WalkedFile]) -> [[WalkedFile]] {
        let byPartial = Dictionary(grouping: candidates) { partialHash($0.url) ?? UUID().uuidString }
        var result: [[WalkedFile]] = []
        for group in byPartial.values where group.count > 1 {
            let byFull = Dictionary(grouping: group) { fullHash($0.url) ?? UUID().uuidString }
            result += byFull.values.filter { $0.count > 1 }
        }
        return result
    }

    static func partialHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: sampleSize) ?? Data() else { return nil }
        hasher.update(data: head)
        if let end = try? handle.seekToEnd(), end > UInt64(sampleSize * 2) {
            try? handle.seek(toOffset: end - UInt64(sampleSize))
            if let tail = try? handle.read(upToCount: sampleSize) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            // `read(upToCount:)` returns nil (not empty data) at end of file.
            let chunk: Data?
            do { chunk = try handle.read(upToCount: chunkSize) } catch { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
