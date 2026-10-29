import Darwin
import Foundation

public enum PermissionChecker {
    /// Deep link to System Settings > Privacy & Security > Full Disk Access.
    public static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    /// Probes TCC-protected files. `access(2)` ignores TCC, so we actually try to open them.
    public static func hasFullDiskAccess(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probes = [
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Safari/Bookmarks.plist",
            "Library/Safari",
        ].map { home.appendingPathComponent($0).path }

        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            return false
        }
        return false
    }
}

public struct DiskUsage: Sendable, Equatable {
    public let total: Int64
    /// Space available for important usage — includes purgeable space, matches Finder's "Available".
    public let available: Int64
    public var used: Int64 { max(total - available, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func current(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskUsage? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]), let total = values.volumeTotalCapacity
        else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskUsage(total: Int64(total), available: available)
    }
}
