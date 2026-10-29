import DeepCleanerCore
import Foundation
import Observation

/// Drives one scan → review → clean → summary flow. Shared by every list-based module.
@MainActor
@Observable
final class CleanupModel {
    enum Phase: Equatable {
        case idle, scanning, review, cleaning, done
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [ScanItem] = []
    private(set) var report: CleanReport?
    /// Actual change in free space measured around the last cleanup.
    private(set) var measuredFreed: Int64?
    private(set) var progress = ScanProgress()
    private(set) var lastScanned: Date?
    var selection: Set<String> = []

    private var allowedRoots: [URL] = []
    private var scanTask: Task<ScanResult, Never>?
    private var waitTask: Task<Void, Never>?

    var hasResults: Bool { !items.isEmpty }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) && !$0.category.isReportOnly } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var selectionHasRegenerable: Bool { selectedItems.contains { $0.category.isRegenerable } }

    /// Item groups ordered by total size, largest first.
    var groups: [(id: String, title: String, items: [ScanItem], size: Int64)] {
        Dictionary(grouping: items, by: \.effectiveGroupID)
            .map { id, items in
                (id, items[0].effectiveGroupTitle, items.sorted { $0.size > $1.size }, items.reduce(0) { $0 + $1.size })
            }
            .sorted { $0.size > $1.size }
    }

    /// Duplicate groups where every copy is selected — cleaning would lose the file entirely.
    var fullySelectedDuplicateGroups: [String] {
        Dictionary(grouping: items.filter { $0.category == .duplicate }, by: \.effectiveGroupID)
            .filter { $0.value.allSatisfy { selection.contains($0.id) } }
            .map { $0.value[0].effectiveGroupTitle }
    }

    func scan(_ operation: @escaping @Sendable (ScanProgress) async -> ScanResult) {
        cancel()
        let progress = ScanProgress()
        self.progress = progress
        phase = .scanning
        items = []
        selection = []
        report = nil
        measuredFreed = nil

        let scanTask = Task.detached(priority: .userInitiated) { await operation(progress) }
        self.scanTask = scanTask
        waitTask = Task {
            let result = await scanTask.value
            guard !Task.isCancelled else { return }
            items = result.items.sorted { $0.size > $1.size }
            allowedRoots = result.allowedRoots
            selection = Set(result.items.filter { $0.selectedByDefault && !$0.category.isReportOnly }.map(\.id))
            lastScanned = Date()
            phase = .review
        }
    }

    func cancel() {
        scanTask?.cancel()
        waitTask?.cancel()
        scanTask = nil
        waitTask = nil
        if phase == .scanning { phase = items.isEmpty ? .idle : .review }
    }

    func clean(deleteRegenerablePermanently: Bool) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        let safety = SafetyGuard(allowedRoots: allowedRoots)
        let before = DiskUsage.current()?.available
        phase = .cleaning
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                Cleaner().clean(targets, guard: safety, deleteRegenerablePermanently: deleteRegenerablePermanently)
            }.value
            let cleanedIDs = Set(report.cleaned.map(\.id))
            items.removeAll { cleanedIDs.contains($0.id) }
            selection.subtract(cleanedIDs)
            if let before, let after = DiskUsage.current()?.available {
                measuredFreed = after - before
            }
            self.report = report
            phase = .done
        }
    }

    func backToReview() {
        phase = items.isEmpty ? .idle : .review
    }

    func toggle(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setGroup(_ items: [ScanItem], selected: Bool) {
        let ids = items.filter { !$0.category.isReportOnly }.map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }
}
