import Darwin
import Foundation

public enum SizeCalculator {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .linkCountKey,
    ]

    struct FileID: Hashable {
        let device: Int32
        let inode: UInt64
    }

    static func fileID(atPath path: String) -> FileID? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileID(device: info.st_dev, inode: info.st_ino)
    }

    /// Allocated size of a file, or the recursive total of a directory.
    /// Symlinks are not followed and hard-linked files are counted once.
    public static func allocatedSize(of url: URL, progress: ScanProgress? = nil) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else {
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            progress?.add(bytes: size)
            return size
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var seenHardLinks = Set<FileID>()
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count & 1023 == 0 {
                if Task.isCancelled { break }
                progress?.add(files: 1024)
            }
            guard let v = try? child.resourceValues(forKeys: Set(keys)),
                  v.isDirectory != true, v.isSymbolicLink != true
            else { continue }
            if (v.linkCount ?? 1) > 1, let id = fileID(atPath: child.path), !seenHardLinks.insert(id).inserted {
                continue
            }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        progress?.add(files: count & 1023, bytes: total)
        return total
    }
}
