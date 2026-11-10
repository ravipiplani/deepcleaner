import DeepCleanerCore
import Foundation
import Observation

/// Scan → review → remove flow for Docker images, containers, volumes and build cache.
@MainActor
@Observable
final class DockerModel {
    enum Phase: Equatable {
        case idle, scanning, review, cleaning, done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var usage: DockerUsage?
    private(set) var report: DockerCleanReport?
    /// Disk image size just before the last removal, to show how much it shrank.
    private(set) var diskImageSizeBeforeClean: Int64?
    var selection: Set<String> = []

    let client = DockerClient()
    private var task: Task<Void, Never>?

    var isInstalled: Bool { client != nil }
    var resources: [DockerResource] { usage?.resources ?? [] }
    var hasResults: Bool { !resources.isEmpty }
    var totalSize: Int64 { usage?.totalSize ?? 0 }
    var selectedItems: [DockerResource] { resources.filter { selection.contains($0.id) && $0.isRemovable } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var groups: [(kind: DockerResource.Kind, items: [DockerResource], size: Int64)] {
        let byKind = Dictionary(grouping: resources, by: \.kind)
        return DockerResource.Kind.allCases.compactMap { kind in
            guard let items = byKind[kind], !items.isEmpty else { return nil }
            return (kind, items.sorted { $0.size > $1.size }, items.reduce(0) { $0 + $1.size })
        }
        .sorted { $0.size > $1.size }
    }

    func scan() {
        guard let client else {
            phase = .failed(DockerError.notInstalled.localizedDescription)
            return
        }
        cancel()
        phase = .scanning
        usage = nil
        report = nil
        selection = []
        task = Task {
            do {
                let usage = try await Task.detached(priority: .userInitiated) {
                    try await client.scan()
                }.value
                guard !Task.isCancelled else { return }
                self.usage = usage
                selection = Set(usage.resources.filter(\.selectedByDefault).map(\.id))
                phase = .review
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = hasResults ? .review : .idle }
    }

    func clean() {
        guard let client else { return }
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        diskImageSizeBeforeClean = usage?.diskImageSize
        phase = .cleaning
        task = Task {
            let report = await Task.detached(priority: .userInitiated) { await client.remove(targets) }.value
            let removed = Set(report.removed.map(\.id))
            usage?.resources.removeAll { removed.contains($0.id) }
            selection.subtract(removed)
            self.report = report
            phase = .done
            await refreshDiskImageSize()
        }
    }

    /// Docker Desktop returns freed blocks to macOS in the background, so the image shrinks over a minute or so.
    func refreshDiskImageSize() async {
        guard let image = usage?.diskImage else { return }
        for _ in 0..<6 {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, phase == .done else { return }
            let size = await Task.detached { SizeCalculator.allocatedSize(of: image) }.value
            usage?.diskImageSize = size
        }
    }

    func backToReview() {
        phase = hasResults ? .review : .idle
    }

    func toggle(_ item: DockerResource) {
        guard item.isRemovable else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setGroup(_ items: [DockerResource], selected: Bool) {
        let ids = items.filter(\.isRemovable).map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }
}
