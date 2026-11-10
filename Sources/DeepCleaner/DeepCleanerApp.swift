import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DeepCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var state = AppState()

    var body: some Scene {
        WindowGroup("DeepCleaner") {
            ContentView()
                .environment(state)
                .frame(minWidth: 960, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    state.refreshSystemInfo()
                }
        }
        .windowToolbarStyle(.unified)
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                Section {
                    sidebarRow(.dashboard)
                }
                Section("Cleanup") {
                    sidebarRow(.systemJunk, model: state.systemJunk)
                    sidebarRow(.devJunk, model: state.devJunk)
                    dockerRow
                }
                Section("Files") {
                    sidebarRow(.largeFiles, model: state.largeFiles)
                    sidebarRow(.duplicates, model: state.duplicates)
                    sidebarRow(.spaceLens)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch state.selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .systemJunk: SystemJunkView()
            case .devJunk: DevJunkView()
            case .docker: DockerView()
            case .largeFiles: LargeFilesView()
            case .duplicates: DuplicatesView()
            case .spaceLens: SpaceLensView()
            }
        }
    }

    private var dockerRow: some View {
        sidebarLabel(.docker) {
            let docker = state.docker
            if docker.phase == .scanning || docker.phase == .cleaning {
                ProgressView().controlSize(.small)
            } else if docker.hasResults {
                SidebarSize(bytes: docker.totalSize)
            }
        }
    }

    private func sidebarRow(_ module: Module, model: CleanupModel? = nil) -> some View {
        sidebarLabel(module) {
            if let model {
                if model.phase == .scanning {
                    ProgressView().controlSize(.small)
                } else if model.hasResults {
                    SidebarSize(bytes: model.totalSize)
                }
            }
        }
    }

    private func sidebarLabel(_ module: Module, @ViewBuilder accessory: () -> some View) -> some View {
        Label {
            HStack {
                Text(module.title)
                Spacer()
                accessory()
            }
        } icon: {
            Image(systemName: module.symbol)
        }
        .tag(module)
    }
}

private struct SidebarSize: View {
    let bytes: Int64

    var body: some View {
        Text(bytes.formattedBytes)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
