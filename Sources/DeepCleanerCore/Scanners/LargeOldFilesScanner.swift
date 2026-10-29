import CoreServices
import Foundation

public struct LargeOldFilesScanner: Sendable {
    public var roots: [URL]
    public var excluded: [URL]
    public var minSize: Int64
    /// When set, only files not used within this interval are reported.
    public var unusedFor: TimeInterval?

    public init(
        roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser],
        excluded: [URL]? = nil,
        minSize: Int64 = 100 * 1_000_000,
        unusedFor: TimeInterval? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = roots
        self.excluded = excluded ?? [home.appendingPathComponent("Library"), home.appendingPathComponent(".Trash")]
        self.minSize = minSize
        self.unusedFor = unusedFor
    }

    public func scan(progress: ScanProgress) async -> ScanResult {
        let files = await FileWalker(roots: roots, excluded: excluded, minSize: minSize).walk(progress: progress)
        let cutoff = unusedFor.map { Date().addingTimeInterval(-$0) }
        let items: [ScanItem] = files.compactMap { file in
            let lastUsed = Self.lastUsedDate(for: file)
            if let cutoff, let lastUsed, lastUsed > cutoff { return nil }
            let kind = FileKind(url: file.url)
            return ScanItem(
                url: file.url, size: file.size, category: .largeFile, lastUsed: lastUsed,
                groupID: kind.rawValue, groupTitle: kind.title
            )
        }
        return ScanResult(items: items, allowedRoots: roots)
    }

    /// Spotlight's "last opened" date when available, falling back to modification/access dates.
    static func lastUsedDate(for file: WalkedFile) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, file.url as CFURL),
           let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return [used, file.modified].compactMap { $0 }.max()
        }
        return [file.modified, file.accessed].compactMap { $0 }.max()
    }
}

public enum FileKind: String, Sendable, CaseIterable {
    case video, diskImage, archive, audio, image, document, other

    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg": self = .video
        case "dmg", "iso", "pkg", "img", "sparseimage", "sparsebundle", "vmdk", "qcow2", "vdi", "ipsw": self = .diskImage
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst": self = .archive
        case "mp3", "wav", "aiff", "flac", "m4a", "aac", "logicx": self = .audio
        case "jpg", "jpeg", "png", "heic", "tiff", "raw", "cr2", "nef", "arw", "dng", "psd": self = .image
        case "pdf", "key", "pages", "numbers", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "csv": self = .document
        default: self = .other
        }
    }

    public var title: String {
        switch self {
        case .video: "Movies & Videos"
        case .diskImage: "Disk Images & Installers"
        case .archive: "Archives"
        case .audio: "Audio"
        case .image: "Images"
        case .document: "Documents"
        case .other: "Other"
        }
    }
}
