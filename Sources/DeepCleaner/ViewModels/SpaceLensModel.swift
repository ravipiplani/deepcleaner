import AppKit
import DeepCleanerCore
import Foundation
import Observation

@MainActor
@Observable
final class SpaceLensModel {
    private(set) var root: DiskNode?
    private(set) var rootURL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var isScanning = false
    private(set) var progress = ScanProgress()
    /// Node IDs from the root to the folder currently shown.
    private(set) var path: [String] = []
    var lastError: String?

    private var scanTask: Task<DiskNode, Never>?

    var current: DiskNode? {
        guard let root else { return nil }
        guard let last = path.last else { return root }
        return root.node(withID: last) ?? root
    }

    var breadcrumbs: [DiskNode] {
        guard let root else { return [] }
        return [root] + path.compactMap { root.node(withID: $0) }
    }

    func scan(_ url: URL? = nil) {
        if let url { rootURL = url }
        scanTask?.cancel()
        let progress = ScanProgress()
        self.progress = progress
        isScanning = true
        root = nil
        path = []
        let target = rootURL
        let task = Task.detached(priority: .userInitiated) {
            await DiskTreeBuilder().build(target, progress: progress)
        }
        scanTask = task
        Task {
            let tree = await task.value
            guard scanTask == task, !task.isCancelled else { return }
            root = tree
            isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            scan(url)
        }
    }

    func open(_ node: DiskNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        path.append(node.id)
    }

    func popTo(_ index: Int) {
        path = Array(path.prefix(index))
    }

    func moveToTrash(_ node: DiskNode) {
        guard let url = node.url else { return }
        let item = ScanItem(url: url, size: node.size, category: .largeFile)
        let report = Cleaner().clean([item], guard: SafetyGuard(allowedRoots: [rootURL]), deleteRegenerablePermanently: false)
        if let failure = report.failures.first {
            lastError = failure.message
            return
        }
        root?.remove(id: node.id)
        path.removeAll { $0 == node.id || $0.hasPrefix(node.id + "/") }
    }
}
