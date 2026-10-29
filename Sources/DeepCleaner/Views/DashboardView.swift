import DeepCleanerCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var state
    @ViewState private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !state.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }
                HStack(alignment: .top, spacing: 20) {
                    DiskCard(disk: state.disk)
                    smartScanCard
                }
                Text("Tools").font(.title3.bold())
                HStack(spacing: 16) {
                    ForEach([Module.largeFiles, .duplicates, .spaceLens]) { module in
                        ToolTile(module: module) { state.selection = module }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Smart Scan")
        .confirmationDialog("Clean \(recommendedSize.formattedBytes) of junk?", isPresented: $confirming) {
            Button("Clean", role: .destructive) {
                for model in state.smartScanModels where model.phase == .review {
                    model.clean(deleteRegenerablePermanently: true)
                }
            }
        } message: {
            Text("Caches and build products are deleted permanently (they are recreated automatically). Everything else goes to the Trash.")
        }
        .onChange(of: state.isSmartScanning) { state.refreshSystemInfo() }
    }

    private var recommendedSize: Int64 {
        state.smartScanModels.reduce(0) { $0 + $1.selectedSize }
    }

    private var cleanedSize: Int64 {
        state.smartScanModels.compactMap(\.report).reduce(0) { $0 + $1.totalBytes }
    }

    private var smartScanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Smart Scan").font(.title2.bold())
            Text("Scans system and developer junk. You review everything before it's removed.")
                .foregroundStyle(.secondary)

            if state.isSmartScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                }
            }
            if state.smartScanModels.contains(where: { $0.phase != .idle }) {
                VStack(spacing: 8) {
                    resultRow(.systemJunk, state.systemJunk)
                    resultRow(.devJunk, state.devJunk)
                }
            }
            if state.smartScanModels.contains(where: { $0.phase == .done }), cleanedSize > 0 {
                Label("Cleaned \(cleanedSize.formattedBytes)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer(minLength: 0)
            HStack {
                Button(state.smartScanModels.allSatisfy { $0.phase == .idle } ? "Scan" : "Scan Again") {
                    state.smartScan()
                }
                .controlSize(.large)
                .disabled(state.isSmartScanning)
                if recommendedSize > 0, !state.isSmartScanning {
                    Button("Clean \(recommendedSize.formattedBytes)") { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func resultRow(_ module: Module, _ model: CleanupModel) -> some View {
        HStack {
            Image(systemName: module.symbol).foregroundStyle(.tint)
            Text(module.title)
            Spacer()
            switch model.phase {
            case .scanning:
                ProgressView().controlSize(.small)
            case .cleaning:
                Text("Cleaning…").foregroundStyle(.secondary)
            default:
                Text("\(model.selectedSize.formattedBytes) selected")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Review") { state.selection = module }
                .disabled(model.phase == .scanning)
        }
    }
}

struct DiskCard: View {
    let disk: DiskUsage?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: disk?.usedFraction ?? 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(disk?.available.formattedBytes ?? "—").font(.title2.bold()).monospacedDigit()
                    Text("available").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            if let disk {
                Text("\(disk.used.formattedBytes) used of \(disk.total.formattedBytes)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 240, height: 240)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var color: Color {
        let fraction = disk?.usedFraction ?? 0
        return fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor
    }
}

struct ToolTile: View {
    let module: Module
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: module.symbol).font(.title).foregroundStyle(.tint)
                Text(module.title).font(.headline)
                Text(module.subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
