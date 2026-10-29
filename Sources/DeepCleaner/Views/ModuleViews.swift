import AppKit
import DeepCleanerCore
import SwiftUI

struct SystemJunkView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ModuleScreen(module: .systemJunk, model: state.systemJunk, scan: state.scanSystemJunk) { EmptyView() }
    }
}

struct DevJunkView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ModuleScreen(module: .devJunk, model: state.devJunk, scan: state.scanDevJunk) {
            Menu {
                Section("Searched for node_modules") {
                    ForEach(state.projectRoots, id: \.self) { root in
                        Button("Remove \(root.abbreviatedPath)", systemImage: "minus.circle") {
                            state.projectRoots.removeAll { $0 == root }
                        }
                    }
                }
                Button("Add Folder…", systemImage: "plus") { addFolder() }
            } label: {
                Label("Project Folders (\(state.projectRoots.count))", systemImage: "folder")
            }
            .fixedSize()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls where !state.projectRoots.contains(url) {
                state.projectRoots.append(url)
            }
        }
    }
}

struct LargeFilesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        ModuleScreen(module: .largeFiles, model: state.largeFiles, scan: state.scanLargeFiles) {
            Picker("Larger than", selection: $state.largeFileMinSize) {
                Text("50 MB").tag(Int64(50_000_000))
                Text("100 MB").tag(Int64(100_000_000))
                Text("500 MB").tag(Int64(500_000_000))
                Text("1 GB").tag(Int64(1_000_000_000))
            }
            .fixedSize()
            Picker("Not used for", selection: $state.largeFileUnusedMonths) {
                Text("Any time").tag(0)
                Text("3 months").tag(3)
                Text("6 months").tag(6)
                Text("1 year").tag(12)
            }
            .fixedSize()
        }
    }
}

struct DuplicatesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        ModuleScreen(module: .duplicates, model: state.duplicates, scan: state.scanDuplicates) {
            Picker("Larger than", selection: $state.duplicateMinSize) {
                Text("100 KB").tag(Int64(100_000))
                Text("1 MB").tag(Int64(1_000_000))
                Text("10 MB").tag(Int64(10_000_000))
                Text("100 MB").tag(Int64(100_000_000))
            }
            .fixedSize()
        }
    }
}
