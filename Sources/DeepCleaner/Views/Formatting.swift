import AppKit
import Foundation

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    /// Path with the home directory shown as `~`.
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}
