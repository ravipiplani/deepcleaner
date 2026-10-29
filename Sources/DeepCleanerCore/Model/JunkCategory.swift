import Foundation

public enum CategoryGroup: String, Sendable {
    case system, developer, files
}

/// Every kind of item DeepCleaner can find. Metadata here drives default selection
/// and how an item may be removed.
public enum JunkCategory: String, CaseIterable, Sendable, Identifiable, Hashable {
    // System junk
    case userCaches, userLogs, crashReports, tempFiles, mailDownloads, trash
    // Developer junk
    case xcodeDerivedData, xcodeArchives, xcodeDeviceSupport, simulatorCaches
    case nodeModules, homebrewCache, npmCache, yarnCache, pnpmStore, pipCache
    case gradleCache, cargoCache, cocoapodsCache, genericCache, dockerData
    // User files
    case largeFile, duplicate

    public var id: String { rawValue }

    public var group: CategoryGroup {
        switch self {
        case .userCaches, .userLogs, .crashReports, .tempFiles, .mailDownloads, .trash:
            .system
        case .largeFile, .duplicate:
            .files
        default:
            .developer
        }
    }

    public var title: String {
        switch self {
        case .userCaches: "User Cache Files"
        case .userLogs: "User Log Files"
        case .crashReports: "Crash Reports"
        case .tempFiles: "Temporary Files"
        case .mailDownloads: "Mail Attachments"
        case .trash: "Trash"
        case .xcodeDerivedData: "Xcode Derived Data"
        case .xcodeArchives: "Xcode Archives"
        case .xcodeDeviceSupport: "iOS Device Support"
        case .simulatorCaches: "Simulator Caches"
        case .nodeModules: "node_modules"
        case .homebrewCache: "Homebrew Cache"
        case .npmCache: "npm Cache"
        case .yarnCache: "Yarn Cache"
        case .pnpmStore: "pnpm Store"
        case .pipCache: "pip Cache"
        case .gradleCache: "Gradle Caches"
        case .cargoCache: "Cargo Registry"
        case .cocoapodsCache: "CocoaPods Cache"
        case .genericCache: "~/.cache"
        case .dockerData: "Docker Disk Image"
        case .largeFile: "Large & Old Files"
        case .duplicate: "Duplicates"
        }
    }

    public var symbol: String {
        switch self {
        case .userCaches, .genericCache: "internaldrive"
        case .userLogs: "doc.text"
        case .crashReports: "exclamationmark.triangle"
        case .tempFiles: "clock.arrow.circlepath"
        case .mailDownloads: "paperclip"
        case .trash: "trash"
        case .xcodeDerivedData, .xcodeArchives: "hammer"
        case .xcodeDeviceSupport, .simulatorCaches: "iphone"
        case .nodeModules, .npmCache, .yarnCache, .pnpmStore: "shippingbox"
        case .homebrewCache: "mug"
        case .pipCache: "chevron.left.forwardslash.chevron.right"
        case .gradleCache, .cargoCache, .cocoapodsCache: "cube.box"
        case .dockerData: "server.rack"
        case .largeFile: "doc.richtext"
        case .duplicate: "doc.on.doc"
        }
    }

    /// Recreated automatically by the owning app or tool, so deleting permanently is safe.
    public var isRegenerable: Bool {
        switch self {
        case .xcodeArchives, .mailDownloads, .largeFile, .duplicate, .dockerData, .trash: false
        default: true
        }
    }

    /// Whether found items start out checked in the review list.
    public var selectedByDefault: Bool {
        switch self {
        case .xcodeArchives, .mailDownloads, .genericCache, .dockerData, .largeFile, .duplicate, .trash: false
        default: true
        }
    }

    /// Shown for information only; DeepCleaner never deletes these.
    public var isReportOnly: Bool { self == .dockerData }
}
