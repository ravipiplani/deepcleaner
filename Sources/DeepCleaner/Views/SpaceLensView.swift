import DeepCleanerCore
import SwiftUI

struct SpaceLensView: View {
    @Environment(AppState.self) private var state
    @ViewState private var pendingTrash: DiskNode?

    private var model: SpaceLensModel { state.spaceLens }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.top, 8)
            if model.isScanning {
                ScanningView(progress: model.progress, cancel: model.cancel)
            } else if let current = model.current {
                HSplitView {
                    TreemapView(node: current, open: model.open, trash: { pendingTrash = $0 })
                        .padding(8)
                        .frame(minWidth: 400)
                    childList(current)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                }
            } else {
                idle
            }
        }
        .navigationTitle("Space Lens")
        .confirmationDialog(
            "Move \(pendingTrash?.name ?? "") to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })
        ) {
            Button("Move to Trash", role: .destructive) {
                if let node = pendingTrash { model.moveToTrash(node) }
                pendingTrash = nil
            }
        } message: {
            Text("\(pendingTrash?.size.formattedBytes ?? "") · \(pendingTrash?.url?.abbreviatedPath ?? "")")
        }
        .alert("Couldn't move to Trash", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: Module.spaceLens.symbol).font(.system(size: 30)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Space Lens").font(.title2.bold())
                if model.root == nil {
                    Text(Module.spaceLens.subtitle).foregroundStyle(.secondary)
                } else {
                    breadcrumbs
                }
            }
            Spacer()
            Button("Choose Folder…", systemImage: "folder") { model.chooseFolder() }
            if model.root != nil {
                Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
            }
        }
        .padding([.horizontal, .top])
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Button(index == 0 ? node.url?.abbreviatedPath ?? node.name : node.name) { model.popTo(index) }
                    .buttonStyle(.link)
            }
            if let current = model.current {
                Text("· \(current.size.formattedBytes)").foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: Module.spaceLens.symbol).font(.system(size: 64, weight: .light)).foregroundStyle(.tint)
            Text("Map your home folder to see where the space goes.").font(.title3).foregroundStyle(.secondary)
            HStack {
                Button("Scan Home Folder") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                Button("Choose Folder…") { model.chooseFolder() }
                    .controlSize(.extraLarge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func childList(_ node: DiskNode) -> some View {
        List(node.children) { child in
            HStack {
                Image(systemName: child.isAggregate ? "ellipsis.circle" : child.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(child.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(child.name).lineLimit(1).truncationMode(.middle)
                    ProgressView(value: node.size > 0 ? Double(child.size) / Double(node.size) : 0)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
                Text(child.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.open(child) }
            .contextMenu { nodeMenu(child) }
        }
    }

    @ViewBuilder
    private func nodeMenu(_ node: DiskNode) -> some View {
        if let url = node.url {
            Button("Reveal in Finder") { url.revealInFinder() }
            Button("Move to Trash…", role: .destructive) { pendingTrash = node }
        }
    }
}

struct TreemapView: View {
    let node: DiskNode
    let open: (DiskNode) -> Void
    let trash: (DiskNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let children = Array(node.children.sorted { $0.size > $1.size }.prefix(150))
            let rects = Treemap.squarify(children.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    let rect = rects[index]
                    if rect.width >= 2, rect.height >= 2 {
                        TreemapTile(node: child, color: color(for: index, node: child), size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .onTapGesture { open(child) }
                            .contextMenu {
                                if let url = child.url {
                                    Button("Reveal in Finder") { url.revealInFinder() }
                                    Button("Move to Trash…", role: .destructive) { trash(child) }
                                }
                            }
                    }
                }
            }
        }
    }

    private func color(for index: Int, node: DiskNode) -> Color {
        if node.isAggregate { return .gray }
        let hue = (Double(index) * 0.618_034).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: node.isDirectory ? 0.55 : 0.3, brightness: 0.85)
    }
}

struct TreemapTile: View {
    let node: DiskNode
    let color: Color
    let size: CGSize
    @ViewState private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(hovering ? 0.95 : 0.75))
            .overlay(alignment: .topLeading) {
                if size.width > 70, size.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.caption.bold()).lineLimit(1)
                        Text(node.size.formattedBytes).font(.caption2).monospacedDigit()
                    }
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(5)
                }
            }
            .padding(1)
            .onHover { hovering = $0 }
            .help("\(node.name) — \(node.size.formattedBytes)")
    }
}
