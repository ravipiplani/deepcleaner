import Foundation

/// One reviewable entry produced by a scanner: a file or folder plus how much space it uses.
public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    /// Allocated (on-disk) size in bytes, matching what Finder reports.
    public let size: Int64
    public let category: JunkCategory
    public var lastUsed: Date?
    public var displayName: String
    /// Secondary line shown under the name; defaults to the abbreviated path.
    public var note: String?
    /// Items sharing a group ID are listed together (e.g. one duplicate set).
    public var groupID: String?
    public var groupTitle: String?
    public var selectedByDefault: Bool

    public init(
        url: URL,
        size: Int64,
        category: JunkCategory,
        lastUsed: Date? = nil,
        displayName: String? = nil,
        note: String? = nil,
        groupID: String? = nil,
        groupTitle: String? = nil,
        selectedByDefault: Bool? = nil
    ) {
        self.url = url
        self.size = size
        self.category = category
        self.lastUsed = lastUsed
        self.displayName = displayName ?? url.lastPathComponent
        self.note = note
        self.groupID = groupID
        self.groupTitle = groupTitle
        self.selectedByDefault = selectedByDefault ?? category.selectedByDefault
    }

    public var effectiveGroupID: String { groupID ?? category.rawValue }
    public var effectiveGroupTitle: String { groupTitle ?? category.title }
}

/// What a scan returns: the items, plus the roots inside which deletion is permitted.
public struct ScanResult: Sendable {
    public var items: [ScanItem]
    public var allowedRoots: [URL]

    public init(items: [ScanItem], allowedRoots: [URL]) {
        self.items = items
        self.allowedRoots = allowedRoots
    }
}
