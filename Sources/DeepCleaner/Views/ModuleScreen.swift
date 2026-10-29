import DeepCleanerCore
import SwiftUI

/// Common chrome for list-based modules: header, idle hero, scanning progress, review list, summary.
struct ModuleScreen<Options: View>: View {
    let module: Module
    let model: CleanupModel
    let scan: () -> Void
    @ViewBuilder var options: () -> Options

    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header
            if !state.hasFullDiskAccess, module != .spaceLens {
                FullDiskAccessBanner().padding([.horizontal, .top])
            }
            Divider().padding(.top, 8)
            switch model.phase {
            case .idle:
                idle
            case .scanning:
                ScanningView(progress: model.progress, cancel: model.cancel)
            case .review:
                ReviewListView(model: model)
            case .cleaning:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cleaning…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                CleanupSummaryView(model: model, rescan: scan)
            }
        }
        .navigationTitle(module.title)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: module.symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.title2.bold())
                Text(module.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            options()
            if model.phase == .review || model.phase == .done {
                Button("Rescan", systemImage: "arrow.clockwise", action: scan)
            }
        }
        .padding([.horizontal, .top])
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: module.symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text(module.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Button(action: scan) {
                Text("Scan").frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            Text("Nothing is removed until you review and confirm.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let snapshot = progress.snapshot
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Scanning… \(snapshot.filesScanned.formatted()) items · \(snapshot.bytesScanned.formattedBytes)")
                    .monospacedDigit()
                Text(URL(fileURLWithPath: snapshot.currentPath).abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                Button("Stop", action: cancel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FullDiskAccessBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is off").font(.headline)
                Text("Without it, some caches, logs and Mail data can't be scanned. Add DeepCleaner in System Settings, then relaunch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(PermissionChecker.fullDiskAccessSettingsURL)
            }
            Button("Check Again") { state.refreshSystemInfo() }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
