import DeepCleanerCore
import SwiftUI

struct ReviewListView: View {
    @Bindable var model: CleanupModel
    @ViewState private var toggledGroups: Set<String> = []
    @ViewState private var deletePermanently = true
    @ViewState private var confirming = false

    var body: some View {
        let groups = model.groups
        VStack(spacing: 0) {
            if groups.isEmpty {
                ContentUnavailableView("Nothing found", systemImage: "checkmark.seal", description: Text("This area is already clean."))
            } else {
                List {
                    ForEach(groups, id: \.id) { group in
                        let expandedByDefault = groups.count <= 3 || group.items.count <= 4
                        Section(isExpanded: Binding(
                            get: { expandedByDefault != toggledGroups.contains(group.id) },
                            set: { _ in toggledGroups.formSymmetricDifference([group.id]) }
                        )) {
                            ForEach(group.items) { item in
                                ItemRow(item: item, isSelected: model.selection.contains(item.id)) { model.toggle(item) }
                            }
                        } header: {
                            groupHeader(group.title, items: group.items, size: group.size)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .confirmationDialog(confirmTitle, isPresented: $confirming) {
            Button("Clean", role: .destructive) {
                model.clean(deleteRegenerablePermanently: deletePermanently)
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private func groupHeader(_ title: String, items: [ScanItem], size: Int64) -> some View {
        let selectable = items.filter { !$0.category.isReportOnly }
        let selectedCount = selectable.filter { model.selection.contains($0.id) }.count
        let state: CheckState = selectedCount == 0 ? .off : selectedCount == selectable.count ? .on : .mixed
        return HStack {
            CheckboxButton(state: state, disabled: selectable.isEmpty) {
                model.setGroup(items, selected: state != .on)
            }
            Text(title).font(.headline)
            Text("\(items.count)").foregroundStyle(.secondary)
            Spacer()
            Text(size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        let fullDuplicateGroups = model.fullySelectedDuplicateGroups
        return VStack(alignment: .leading, spacing: 8) {
            if !fullDuplicateGroups.isEmpty {
                Label("Every copy is selected in: \(fullDuplicateGroups.prefix(3).joined(separator: ", ")). Keep at least one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack {
                Text("\(model.selectedItems.count) selected · \(model.selectedSize.formattedBytes)")
                    .font(.headline)
                    .monospacedDigit()
                Text("of \(model.totalSize.formattedBytes) found").foregroundStyle(.secondary)
                Spacer()
                if model.selectionHasRegenerable {
                    Toggle("Delete caches permanently", isOn: $deletePermanently)
                        .help("Caches and build products are recreated automatically. Deleting them frees space immediately instead of filling the Trash.")
                }
                Button {
                    confirming = true
                } label: {
                    Text("Clean \(model.selectedSize.formattedBytes)").frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedItems.isEmpty || !fullDuplicateGroups.isEmpty)
            }
        }
        .padding()
    }

    private var confirmTitle: String {
        "Clean \(model.selectedItems.count) items (\(model.selectedSize.formattedBytes))?"
    }

    private var confirmMessage: String {
        let items = model.selectedItems
        let permanent = items.filter { Cleaner.mode(for: $0, deleteRegenerablePermanently: deletePermanently) == .permanent }
        let trashed = items.count - permanent.count
        var parts: [String] = []
        if !permanent.isEmpty {
            parts.append("\(permanent.count) regenerable items (\(permanent.reduce(0) { $0 + $1.size }.formattedBytes)) will be deleted permanently.")
        }
        if trashed > 0 {
            parts.append("\(trashed) items will be moved to the Trash, where you can restore them.")
        }
        return parts.joined(separator: " ")
    }
}

struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckboxButton(state: isSelected ? .on : .off, disabled: item.category.isReportOnly, action: toggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                Text(item.note ?? item.url.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let lastUsed = item.lastUsed {
                Text(lastUsed, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.size.formattedBytes)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { item.url.revealInFinder() }
        .contextMenu {
            Button("Reveal in Finder") { item.url.revealInFinder() }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }
}

enum CheckState {
    case on, off, mixed
}

struct CheckboxButton: View {
    let state: CheckState
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .off: "square"
        case .mixed: "minus.square.fill"
        }
    }
}
