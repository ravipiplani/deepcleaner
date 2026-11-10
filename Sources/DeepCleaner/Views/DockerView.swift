import AppKit
import DeepCleanerCore
import SwiftUI

struct DockerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.docker
        VStack(spacing: 0) {
            ModuleHeader(module: .docker) {
                if model.phase == .review || model.phase == .done {
                    Button("Rescan", systemImage: "arrow.clockwise", action: model.scan)
                }
            }
            Divider().padding(.top, 8)
            switch model.phase {
            case .idle:
                idle(model)
            case .scanning:
                busy("Asking Docker what it's storing…", detail: "This can take half a minute with lots of volumes.", stop: model.cancel)
            case .review:
                DockerReviewView(model: model)
            case .cleaning:
                busy("Removing from Docker…", detail: nil, stop: nil)
            case .done:
                DockerSummaryView(model: model)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't read Docker", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    HStack {
                        if FileManager.default.fileExists(atPath: "/Applications/Docker.app") {
                            Button("Open Docker Desktop") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
                            }
                        }
                        Button("Try Again", action: model.scan).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle(Module.docker.title)
    }

    @ViewBuilder
    private func idle(_ model: DockerModel) -> some View {
        if model.isInstalled {
            VStack(spacing: 16) {
                Image(systemName: Module.docker.symbol)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                Text(Module.docker.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button(action: model.scan) {
                    Text("Scan").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                Text("Docker must be running. Items are removed by Docker itself, and only after you confirm.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Docker not found", systemImage: "cube.transparent",
                description: Text("DeepCleaner couldn't find the docker command. Install Docker Desktop to use this.")
            )
        }
    }

    private func busy(_ title: String, detail: String?, stop: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(title)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let stop { Button("Stop", action: stop) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shows how Docker's disk image on the Mac compares with what Docker says it's storing.
private struct DiskImageStrip: View {
    let usage: DockerUsage
    let selected: Int64

    var body: some View {
        HStack(spacing: 24) {
            if usage.diskImage != nil {
                stat("Disk image on your Mac", usage.diskImageSize)
            }
            stat("Used by Docker", usage.totalSize)
            stat("Selected", selected, highlight: true)
            Spacer()
            if let image = usage.diskImage {
                Button("Show Disk Image", systemImage: "magnifyingglass") { image.revealInFinder() }
                    .labelStyle(.iconOnly)
                    .help("Reveal \(image.lastPathComponent) in Finder")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func stat(_ title: String, _ bytes: Int64, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes.formattedBytes)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(highlight ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
    }
}

struct DockerReviewView: View {
    @Bindable var model: DockerModel
    @ViewState private var toggledGroups: Set<String> = []
    @ViewState private var confirming = false

    var body: some View {
        let groups = model.groups
        VStack(spacing: 0) {
            if let usage = model.usage {
                DiskImageStrip(usage: usage, selected: model.selectedSize)
                Divider()
            }
            if groups.isEmpty {
                ContentUnavailableView("Nothing stored", systemImage: "checkmark.seal", description: Text("Docker has no images, containers or volumes."))
            } else {
                List {
                    ForEach(groups, id: \.kind) { group in
                        let expandedByDefault = group.items.count <= 25
                        Section(isExpanded: Binding(
                            get: { expandedByDefault != toggledGroups.contains(group.kind.id) },
                            set: { _ in toggledGroups.formSymmetricDifference([group.kind.id]) }
                        )) {
                            ForEach(group.items) { item in
                                DockerRow(item: item, isSelected: model.selection.contains(item.id)) { model.toggle(item) }
                            }
                        } header: {
                            header(group.kind, items: group.items, size: group.size)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .confirmationDialog(
            "Remove \(model.selectedItems.count) Docker items (\(model.selectedSize.formattedBytes))?",
            isPresented: $confirming
        ) {
            Button("Remove", role: .destructive, action: model.clean)
        } message: {
            Text(confirmMessage)
        }
    }

    private func header(_ kind: DockerResource.Kind, items: [DockerResource], size: Int64) -> some View {
        let removable = items.filter(\.isRemovable)
        let selectedCount = removable.filter { model.selection.contains($0.id) }.count
        let state: CheckState = selectedCount == 0 ? .off : selectedCount == removable.count ? .on : .mixed
        return HStack {
            CheckboxButton(state: state, disabled: removable.isEmpty) {
                model.setGroup(items, selected: state != .on)
            }
            Image(systemName: kind.symbol).foregroundStyle(.secondary)
            Text(kind.title).font(.headline)
            Text("\(items.count)").foregroundStyle(.secondary)
            if removable.count < items.count {
                Text("· \(items.count - removable.count) in use").foregroundStyle(.secondary)
            }
            Spacer()
            Text(size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(model.selectedItems.count) selected · \(model.selectedSize.formattedBytes)")
                .font(.headline)
                .monospacedDigit()
            Text("of \(model.totalSize.formattedBytes) in Docker").foregroundStyle(.secondary)
            Spacer()
            Button {
                confirming = true
            } label: {
                Text("Remove \(model.selectedSize.formattedBytes)").frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedItems.isEmpty)
        }
        .padding()
    }

    private var confirmMessage: String {
        let kinds = Set(model.selectedItems.map(\.kind))
        var parts = ["Docker deletes these permanently; they don't go to the Trash."]
        if kinds.contains(.volume) {
            parts.append("Volumes hold container data such as databases and can't be recovered.")
        }
        if kinds.contains(.image) {
            parts.append("Images can be pulled or rebuilt later.")
        }
        if kinds.contains(.buildCache) {
            parts.append("Your next build will start without its cache.")
        }
        return parts.joined(separator: " ")
    }
}

private struct DockerRow: View {
    let item: DockerResource
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckboxButton(state: isSelected && item.isRemovable ? .on : .off, disabled: !item.isRemovable, action: toggle)
            Image(systemName: item.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    if let reason = item.blockedReason {
                        Text(reason).foregroundStyle(.orange)
                        Text("·")
                    }
                    Text(item.detail).truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let created = item.created {
                Text(created, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(item.kind == .buildCache ? "Last used" : "Created")
            }
            Text(item.size.formattedBytes)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .opacity(item.isRemovable ? 1 : 0.7)
        .contextMenu {
            if !item.refs.isEmpty {
                Button(item.kind == .volume ? "Copy Volume Name" : "Copy ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.kind == .image ? item.key : item.refs[0], forType: .string)
                }
            }
        }
    }
}

private struct DockerSummaryView: View {
    let model: DockerModel

    var body: some View {
        if let report = model.report {
            VStack(spacing: 14) {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(report.failures.isEmpty ? .green : .orange)
                Text("Removed \(report.reclaimedBytes.formattedBytes) from Docker")
                    .font(.largeTitle.bold())
                Text("\(report.removed.count) items removed")
                    .foregroundStyle(.secondary)
                if let before = model.diskImageSizeBeforeClean, let now = model.usage?.diskImageSize {
                    Group {
                        if now < before {
                            Text("Disk image shrank by \((before - now).formattedBytes) to \(now.formattedBytes)")
                        } else {
                            Text("Docker Desktop hands freed space back to macOS in the background; the disk image may take a minute to shrink.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                }

                if !report.failures.isEmpty {
                    GroupBox {
                        DisclosureGroup("\(report.failures.count) items couldn't be removed") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(report.failures) { failure in
                                        VStack(alignment: .leading) {
                                            Text(failure.resource.name).font(.callout)
                                            Text(failure.message).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                        }
                    }
                    .frame(maxWidth: 560)
                }

                HStack {
                    if model.hasResults {
                        Button("Review Remaining") { model.backToReview() }
                    }
                    Button("Scan Again", action: model.scan).buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
