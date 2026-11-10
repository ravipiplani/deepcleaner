import Foundation

/// One thing Docker stores inside its disk image that can be removed through the Docker CLI.
public struct DockerResource: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        // Declared in removal order: containers hold images and volumes, so they go first.
        case container, image, volume, buildCache

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .container: "Containers"
            case .image: "Images"
            case .volume: "Volumes"
            case .buildCache: "Build Cache"
            }
        }

        public var symbol: String {
            switch self {
            case .container: "shippingbox"
            case .image: "square.stack.3d.up"
            case .volume: "externaldrive"
            case .buildCache: "hammer"
            }
        }
    }

    public var id: String { "\(kind.rawValue):\(key)" }
    public let kind: Kind
    /// Stable identity within its kind (image ID, container ID, volume name).
    public let key: String
    /// Arguments that name this resource to the removal command (tags, IDs or names).
    public let refs: [String]
    public var name: String
    public var detail: String
    /// Bytes freed by removing it (an image's unique layers, a container's writable layer, …).
    public let size: Int64
    public var created: Date?
    /// Why it can't be removed right now (running, used by a container…); nil when removable.
    public var blockedReason: String?
    public var selectedByDefault: Bool

    public var isRemovable: Bool { blockedReason == nil }

    public init(
        kind: Kind, key: String, refs: [String], name: String, detail: String, size: Int64,
        created: Date? = nil, blockedReason: String? = nil, selectedByDefault: Bool = false
    ) {
        self.kind = kind
        self.key = key
        self.refs = refs
        self.name = name
        self.detail = detail
        self.size = size
        self.created = created
        self.blockedReason = blockedReason
        self.selectedByDefault = selectedByDefault && blockedReason == nil
    }
}

/// Everything a Docker scan found, plus the disk image those resources live in.
public struct DockerUsage: Sendable {
    public var resources: [DockerResource]
    /// Docker Desktop's VM disk image and its allocated size on the Mac, if found.
    public var diskImage: URL?
    public var diskImageSize: Int64

    public init(resources: [DockerResource], diskImage: URL? = nil, diskImageSize: Int64 = 0) {
        self.resources = resources
        self.diskImage = diskImage
        self.diskImageSize = diskImageSize
    }

    public var totalSize: Int64 { resources.reduce(0) { $0 + $1.size } }
}

public enum DockerError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case notRunning
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Docker isn't installed."
        case .notRunning: "Docker isn't running. Start Docker Desktop, then scan again."
        case .commandFailed(let message): message
        }
    }
}

/// Outcome of removing a batch of Docker resources.
public struct DockerCleanReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public var id: String { resource.id }
        public let resource: DockerResource
        public let message: String
    }

    public var removed: [DockerResource] = []
    public var failures: [Failure] = []
    /// Space Docker says it reclaimed, falling back to the sizes reported at scan time.
    public var reclaimedBytes: Int64 = 0

    public init() {}
}
