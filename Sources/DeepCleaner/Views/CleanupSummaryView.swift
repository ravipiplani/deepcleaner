import DeepCleanerCore
import SwiftUI

struct CleanupSummaryView: View {
    let model: CleanupModel
    let rescan: () -> Void

    var body: some View {
        if let report = model.report {
            VStack(spacing: 14) {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(report.failures.isEmpty ? .green : .orange)
                Text("Cleaned \(report.totalBytes.formattedBytes)")
                    .font(.largeTitle.bold())
                VStack(spacing: 4) {
                    if report.deletedBytes > 0 {
                        Text("\(report.deletedBytes.formattedBytes) deleted permanently")
                    }
                    if report.trashedBytes > 0 {
                        Text("\(report.trashedBytes.formattedBytes) moved to the Trash — empty it to reclaim this space")
                    }
                    if let measured = model.measuredFreed, measured > 0 {
                        Text("Free space increased by \(measured.formattedBytes)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)

                if !report.failures.isEmpty {
                    GroupBox {
                        DisclosureGroup("\(report.failures.count) items couldn't be removed") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(report.failures) { failure in
                                        VStack(alignment: .leading) {
                                            Text(failure.item.url.abbreviatedPath).font(.callout)
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
                    if report.trashedBytes > 0 {
                        Button("Open Trash") {
                            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                        }
                    }
                    if model.hasResults {
                        Button("Review Remaining") { model.backToReview() }
                    }
                    Button("Scan Again", action: rescan).buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
