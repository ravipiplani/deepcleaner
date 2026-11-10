import AppKit
import DeepCleanerCore
import SwiftUI

/// Compact notice pinned to the bottom of the sidebar when a newer release exists.
struct UpdateBanner: View {
    let release: ReleaseInfo
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available").font(.callout.bold())
                    Text("DeepCleaner \(release.version.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

struct UpdateSheet: View {
    @Bindable var model: UpdateModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.status {
            case .idle, .checking:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…")
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                buttons { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }

            case .upToDate:
                message("You're up to date", systemImage: "checkmark.circle.fill", color: .green,
                        detail: "DeepCleaner \(model.currentVersion?.description ?? "") is the latest version.")
                buttons { Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }

            case .failed(let error):
                message("Couldn't check for updates", systemImage: "exclamationmark.triangle.fill", color: .orange, detail: error)
                buttons {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Try Again") { Task { await model.check() } }.keyboardShortcut(.defaultAction)
                }

            case .available(let release):
                available(release)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func available(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            message("DeepCleaner \(release.version.description) is available", systemImage: "arrow.down.circle.fill", color: .accentColor,
                    detail: "You have \(model.currentVersion?.description ?? "an older version").")

            if let changes = release.changes {
                ScrollView {
                    Text(Self.markdown(changes))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            Label {
                Text("Download the DMG, quit DeepCleaner and drag the new version into Applications. Then turn Full Disk Access back on in System Settings: macOS resets it for each new build until DeepCleaner is notarized.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Skip This Version") { model.skip(release) }
                Spacer()
                Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Download") {
                    NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            Link("View release on GitHub", destination: release.pageURL).font(.caption)
        }
    }

    private func message(_ title: String, systemImage: String, color: Color, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
