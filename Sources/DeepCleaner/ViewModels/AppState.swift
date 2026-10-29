import DeepCleanerCore
import Foundation
import Observation

enum Module: String, CaseIterable, Identifiable, Hashable {
    case dashboard, systemJunk, devJunk, largeFiles, duplicates, spaceLens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Smart Scan"
        case .systemJunk: "System Junk"
        case .devJunk: "Developer Junk"
        case .largeFiles: "Large & Old Files"
        case .duplicates: "Duplicates"
        case .spaceLens: "Space Lens"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "sparkles"
        case .systemJunk: "trash.circle"
        case .devJunk: "hammer.circle"
        case .largeFiles: "doc.circle"
        case .duplicates: "doc.on.doc"
        case .spaceLens: "square.grid.3x3.square"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Find junk across your Mac in one pass"
        case .systemJunk: "Caches, logs, crash reports, temporary files and Trash"
        case .devJunk: "Xcode data, package manager caches and stale node_modules"
        case .largeFiles: "Big files you may no longer need"
        case .duplicates: "Identical copies of the same file"
        case .spaceLens: "See what's taking up space, folder by folder"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selection: Module? = .dashboard
    var hasFullDiskAccess = PermissionChecker.hasFullDiskAccess()
    var disk = DiskUsage.current()

    let systemJunk = CleanupModel()
    let devJunk = CleanupModel()
    let largeFiles = CleanupModel()
    let duplicates = CleanupModel()
    let spaceLens = SpaceLensModel()

    var projectRoots = DevJunkScanner.defaultProjectRoots()
    var largeFileMinSize: Int64 = 100 * 1_000_000
    var largeFileUnusedMonths = 0
    var duplicateMinSize: Int64 = 1_000_000

    func refreshSystemInfo() {
        hasFullDiskAccess = PermissionChecker.hasFullDiskAccess()
        disk = DiskUsage.current()
    }

    func scanSystemJunk() {
        systemJunk.scan { await SystemJunkScanner().scan(progress: $0) }
    }

    func scanDevJunk() {
        let roots = projectRoots
        devJunk.scan { await DevJunkScanner(projectRoots: roots).scan(progress: $0) }
    }

    func scanLargeFiles() {
        let scanner = LargeOldFilesScanner(
            minSize: largeFileMinSize,
            unusedFor: largeFileUnusedMonths > 0 ? Double(largeFileUnusedMonths) * 30 * 86_400 : nil
        )
        largeFiles.scan { await scanner.scan(progress: $0) }
    }

    func scanDuplicates() {
        let scanner = DuplicateScanner(minSize: duplicateMinSize)
        duplicates.scan { await scanner.scan(progress: $0) }
    }

    func smartScan() {
        scanSystemJunk()
        scanDevJunk()
    }

    var smartScanModels: [CleanupModel] { [systemJunk, devJunk] }
    var isSmartScanning: Bool { smartScanModels.contains { $0.phase == .scanning } }
}
