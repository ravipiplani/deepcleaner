import Foundation

public struct CleanReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public var id: String { item.id }
        public let item: ScanItem
        public let message: String
    }

    public var cleaned: [ScanItem] = []
    public var failures: [Failure] = []
    /// Bytes deleted outright — available immediately.
    public var deletedBytes: Int64 = 0
    /// Bytes moved to the Trash — reclaimed once the Trash is emptied.
    public var trashedBytes: Int64 = 0

    public var totalBytes: Int64 { deletedBytes + trashedBytes }
}

public struct Cleaner: Sendable {
    public enum Mode: Equatable, Sendable {
        case trash, permanent, skip
    }

    public var dryRun: Bool

    public init(dryRun: Bool = false) {
        self.dryRun = dryRun
    }

    /// Emptying the Trash is always permanent; other regenerable caches are permanent only when
    /// the user opts in. Everything else goes to the Trash so it can be restored.
    public static func mode(for item: ScanItem, deleteRegenerablePermanently: Bool) -> Mode {
        if item.category.isReportOnly { return .skip }
        if item.category == .trash { return .permanent }
        if item.category.isRegenerable && deleteRegenerablePermanently { return .permanent }
        return .trash
    }

    public func clean(_ items: [ScanItem], guard safety: SafetyGuard, deleteRegenerablePermanently: Bool) -> CleanReport {
        var report = CleanReport()
        let fm = FileManager.default
        for item in items {
            if Task.isCancelled { break }
            let mode = Self.mode(for: item, deleteRegenerablePermanently: deleteRegenerablePermanently)
            do {
                guard mode != .skip else {
                    throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Shown for information only"])
                }
                try safety.validate(item.url)
                if !dryRun {
                    if mode == .permanent {
                        try fm.removeItem(at: item.url)
                    } else {
                        try fm.trashItem(at: item.url, resultingItemURL: nil)
                    }
                }
                report.cleaned.append(item)
                if mode == .permanent {
                    report.deletedBytes += item.size
                } else {
                    report.trashedBytes += item.size
                }
            } catch {
                report.failures.append(.init(item: item, message: error.localizedDescription))
            }
        }
        return report
    }
}
