import Foundation
import os

/// Talks to Docker through its CLI. DeepCleaner never touches Docker's disk image directly:
/// everything is removed by Docker itself, which then hands the space back to macOS.
public struct DockerClient: Sendable {
    public let executable: URL
    public var home: URL

    public init?(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        guard let executable = Self.locate(home: home) else { return nil }
        self.init(executable: executable, home: home)
    }

    public init(executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.executable = executable
        self.home = home
    }

    /// Apps launched from Finder don't inherit the shell's PATH, so look in the usual places.
    public static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            home.appendingPathComponent(".docker/bin/docker").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home.appendingPathComponent(".orbstack/bin/docker").path,
            home.appendingPathComponent(".rd/bin/docker").path,
        ]
        return candidates.lazy
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Docker Desktop's Linux VM disk. Its allocated size is what Docker really costs on disk.
    public static func diskImage(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let data = home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data")
        return ["Docker.raw", "Docker.qcow2"]
            .map { data.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Scanning

    public func scan() async throws -> DockerUsage {
        let result = try await run(["system", "df", "-v", "--format", "json"])
        guard result.status == 0 else { throw Self.error(from: result) }
        let resources = try DockerParser.parseSystemDF(result.stdout)
        let image = Self.diskImage(home: home)
        return DockerUsage(
            resources: resources,
            diskImage: image,
            diskImageSize: image.map { SizeCalculator.allocatedSize(of: $0) } ?? 0
        )
    }

    // MARK: - Removal

    /// Removes resources in dependency order (containers, then images, volumes and build cache).
    /// Never forces: anything Docker considers in use is left alone and reported as a failure.
    public func remove(_ resources: [DockerResource]) async -> DockerCleanReport {
        var report = DockerCleanReport()
        let byKind = Dictionary(grouping: resources.filter(\.isRemovable), by: \.kind)
        for kind in DockerResource.Kind.allCases {
            guard let items = byKind[kind], !Task.isCancelled else { continue }
            switch kind {
            case .container: await removeBatched(items, command: ["rm"], into: &report)
            case .volume: await removeBatched(items, command: ["volume", "rm"], into: &report)
            case .image: await removeImages(items, into: &report)
            case .buildCache: await pruneBuildCache(items, into: &report)
            }
        }
        for item in resources where !item.isRemovable {
            report.failures.append(.init(resource: item, message: item.blockedReason ?? "In use"))
        }
        return report
    }

    /// `docker rm` and `docker volume rm` print each name they removed and keep going past failures.
    private func removeBatched(_ items: [DockerResource], command: [String], into report: inout DockerCleanReport) async {
        for start in stride(from: 0, to: items.count, by: 50) {
            if Task.isCancelled { return }
            let chunk = Array(items[start..<min(start + 50, items.count)])
            let result: CommandResult
            do {
                result = try await run(command + chunk.flatMap(\.refs))
            } catch {
                report.failures += chunk.map { .init(resource: $0, message: error.localizedDescription) }
                continue
            }
            let removed = Set(result.stdoutLines)
            let errors = result.stderrLines
            for item in chunk {
                if item.refs.contains(where: removed.contains) {
                    report.removed.append(item)
                    report.reclaimedBytes += item.size
                } else {
                    let message = errors.first { line in item.refs.contains { line.contains($0) } }
                        ?? errors.first ?? "Docker didn't remove it"
                    report.failures.append(.init(resource: item, message: Self.clean(message)))
                }
            }
        }
    }

    private func removeImages(_ items: [DockerResource], into report: inout DockerCleanReport) async {
        for item in items {
            if Task.isCancelled { return }
            do {
                let result = try await run(["rmi"] + item.refs)
                if result.status == 0 {
                    report.removed.append(item)
                    report.reclaimedBytes += item.size
                } else {
                    report.failures.append(.init(resource: item, message: Self.error(from: result).localizedDescription))
                }
            } catch {
                report.failures.append(.init(resource: item, message: error.localizedDescription))
            }
        }
    }

    private func pruneBuildCache(_ items: [DockerResource], into report: inout DockerCleanReport) async {
        do {
            let result = try await run(["builder", "prune", "--all", "--force"])
            guard result.status == 0 else {
                let message = Self.error(from: result).localizedDescription
                report.failures += items.map { .init(resource: $0, message: message) }
                return
            }
            report.removed += items
            report.reclaimedBytes += Self.reclaimedTotal(in: result.stdoutLines) ?? items.reduce(0) { $0 + $1.size }
        } catch {
            report.failures += items.map { .init(resource: $0, message: error.localizedDescription) }
        }
    }

    /// Finds "Total reclaimed space: 1.2GB" (classic builder) or "Total:  1.2GB" (buildx).
    static func reclaimedTotal(in lines: [String]) -> Int64? {
        guard let line = lines.last(where: { $0.hasPrefix("Total") }),
              let value = line.split(whereSeparator: \.isWhitespace).last else { return nil }
        return DockerParser.parseSize(String(value))
    }

    // MARK: - Process

    struct CommandResult: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data

        var stdoutLines: [String] { Self.lines(stdout) }
        var stderrLines: [String] { Self.lines(stderr) }

        static func lines(_ data: Data) -> [String] {
            String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    func run(_ arguments: [String]) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let extraPath = [executable.deletingLastPathComponent().path, "/usr/local/bin", "/opt/homebrew/bin"]
        environment["PATH"] = (extraPath + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        environment["HOME"] = environment["HOME"] ?? home.path
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let handle = ProcessHandle(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    // Drain both pipes concurrently so a chatty command can't fill a buffer and stall.
                    let stderrData = OSAllocatedUnfairLock(initialState: Data())
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let data = err.fileHandleForReading.readDataToEndOfFile()
                        stderrData.withLock { $0 = data }
                        group.leave()
                    }
                    let stdout = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: CommandResult(
                            status: process.terminationStatus, stdout: stdout, stderr: stderrData.withLock { $0 }
                        ))
                    }
                }
            }
        } onCancel: {
            handle.terminate()
        }
    }

    static func error(from result: CommandResult) -> DockerError {
        let message = clean(result.stderrLines.joined(separator: "\n"))
        if message.contains("Cannot connect to the Docker daemon") || message.contains("docker daemon is not running")
            || message.contains("Is the docker daemon running") {
            return .notRunning
        }
        return .commandFailed(message.isEmpty ? "Docker exited with status \(result.status)" : message)
    }

    /// Drops Docker's "Error response from daemon:" prefix.
    static func clean(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Error response from daemon: ", with: "")
            .replacingOccurrences(of: "Error: ", with: "")
    }
}

/// Lets the cancellation handler stop a running command.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}
