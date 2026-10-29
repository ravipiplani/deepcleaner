import Foundation
import os

/// Thread-safe progress counter shared between scanner tasks and the UI, which polls `snapshot`.
public final class ScanProgress: Sendable {
    public struct State: Sendable {
        public var filesScanned = 0
        public var bytesScanned: Int64 = 0
        public var currentPath = ""
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func add(files: Int = 1, bytes: Int64 = 0) {
        state.withLock {
            $0.filesScanned += files
            $0.bytesScanned += bytes
        }
    }

    public func setCurrentPath(_ path: String) {
        state.withLock { $0.currentPath = path }
    }

    public var snapshot: State { state.withLock { $0 } }
}
