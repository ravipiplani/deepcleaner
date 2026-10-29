import Foundation

/// A folder whose immediate children are each reported as one cleanable item.
public struct JunkRule: Sendable {
    public let category: JunkCategory
    public let root: URL
    /// Only report children not modified within this interval.
    public var minAge: TimeInterval?
    public var excludedNames: Set<String>

    public init(_ category: JunkCategory, _ root: URL, minAge: TimeInterval? = nil, excluding excludedNames: Set<String> = []) {
        self.category = category
        self.root = root
        self.minAge = minAge
        self.excludedNames = excludedNames
    }
}

public enum JunkRules {
    /// Caches that are either sensitive (iCloud, HomeKit, auth) or covered by a more specific developer rule.
    static let excludedCaches: Set<String> = [
        "CloudKit", "com.apple.HomeKit", "com.apple.bird", "com.apple.iCloudHelper", "FamilyCircle",
        "com.apple.akd", "com.apple.containermanagerd", "com.apple.ap.adprivacyd",
        "Homebrew", "pip", "Yarn", "CocoaPods",
        Bundle.main.bundleIdentifier ?? "ai.rhobots.deepcleaner",
    ]

    public static func system(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        tempDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [JunkRule] {
        let lib = home.appendingPathComponent("Library")
        return [
            JunkRule(.userCaches, lib.appendingPathComponent("Caches"), excluding: excludedCaches),
            JunkRule(.userLogs, lib.appendingPathComponent("Logs"), excluding: ["DiagnosticReports"]),
            JunkRule(.crashReports, lib.appendingPathComponent("Logs/DiagnosticReports")),
            JunkRule(.tempFiles, tempDirectory, minAge: 3 * 86_400),
            JunkRule(.mailDownloads, lib.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads")),
            JunkRule(.trash, home.appendingPathComponent(".Trash")),
        ]
    }

    public static func developer(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [JunkRule] {
        let lib = home.appendingPathComponent("Library")
        let xcode = lib.appendingPathComponent("Developer/Xcode")
        return [
            JunkRule(.xcodeDerivedData, xcode.appendingPathComponent("DerivedData")),
            JunkRule(.xcodeArchives, xcode.appendingPathComponent("Archives")),
            JunkRule(.xcodeDeviceSupport, xcode.appendingPathComponent("iOS DeviceSupport")),
            JunkRule(.xcodeDeviceSupport, xcode.appendingPathComponent("watchOS DeviceSupport")),
            JunkRule(.simulatorCaches, lib.appendingPathComponent("Developer/CoreSimulator/Caches")),
            JunkRule(.homebrewCache, lib.appendingPathComponent("Caches/Homebrew")),
            JunkRule(.npmCache, home.appendingPathComponent(".npm/_cacache")),
            JunkRule(.yarnCache, lib.appendingPathComponent("Caches/Yarn")),
            JunkRule(.pnpmStore, lib.appendingPathComponent("pnpm/store")),
            JunkRule(.pnpmStore, home.appendingPathComponent(".pnpm-store")),
            JunkRule(.pipCache, lib.appendingPathComponent("Caches/pip")),
            JunkRule(.gradleCache, home.appendingPathComponent(".gradle/caches")),
            JunkRule(.cargoCache, home.appendingPathComponent(".cargo/registry")),
            JunkRule(.cocoapodsCache, lib.appendingPathComponent("Caches/CocoaPods")),
            JunkRule(.genericCache, home.appendingPathComponent(".cache")),
        ]
    }
}
