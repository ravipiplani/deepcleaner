import Foundation

/// Scans a set of `JunkRule`s in parallel, sizing each child of each rule's root.
public struct RuleScanner: Sendable {
    public let rules: [JunkRule]

    public init(rules: [JunkRule]) {
        self.rules = rules
    }

    public func scan(progress: ScanProgress) async -> ScanResult {
        let items = await withTaskGroup(of: [ScanItem].self) { group in
            for rule in rules {
                for child in Self.candidates(for: rule) {
                    group.addTask {
                        guard !Task.isCancelled else { return [] }
                        progress.setCurrentPath(child.url.path)
                        let size = SizeCalculator.allocatedSize(of: child.url, progress: progress)
                        guard size > 0 else { return [] }
                        return [ScanItem(url: child.url, size: size, category: rule.category, lastUsed: child.modified)]
                    }
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        return ScanResult(items: items, allowedRoots: rules.map(\.root))
    }

    static func candidates(for rule: JunkRule) -> [(url: URL, modified: Date?)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rule.root, includingPropertiesForKeys: keys, options: []
        ) else { return [] }
        let cutoff = rule.minAge.map { Date().addingTimeInterval(-$0) }
        return children.compactMap { url in
            let name = url.lastPathComponent
            guard name != ".DS_Store", name != ".localized", !rule.excludedNames.contains(name) else { return nil }
            let modified = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate
            if let cutoff, let modified, modified > cutoff { return nil }
            return (url, modified)
        }
    }
}
