import Foundation
import Testing
@testable import DeepCleanerCore

@Suite struct CleanerTests {
    @Test func modeSelection() {
        let url = URL(fileURLWithPath: "/tmp/x")
        #expect(Cleaner.mode(for: ScanItem(url: url, size: 1, category: .userCaches), deleteRegenerablePermanently: true) == .permanent)
        #expect(Cleaner.mode(for: ScanItem(url: url, size: 1, category: .userCaches), deleteRegenerablePermanently: false) == .trash)
        #expect(Cleaner.mode(for: ScanItem(url: url, size: 1, category: .largeFile), deleteRegenerablePermanently: true) == .trash)
        #expect(Cleaner.mode(for: ScanItem(url: url, size: 1, category: .trash), deleteRegenerablePermanently: false) == .permanent)
        #expect(Cleaner.mode(for: ScanItem(url: url, size: 1, category: .dockerData), deleteRegenerablePermanently: true) == .skip)
    }

    @Test func dryRunLeavesFilesAlone() throws {
        let fixture = try Fixture()
        let file = try fixture.file("Caches/a/data", bytes: 1_000)
        let item = ScanItem(url: file.deletingLastPathComponent(), size: 1_000, category: .userCaches)
        let safety = SafetyGuard(allowedRoots: [fixture.root.appendingPathComponent("Caches")], appBundle: nil)
        let report = Cleaner(dryRun: true).clean([item], guard: safety, deleteRegenerablePermanently: true)
        #expect(report.cleaned.count == 1)
        #expect(report.deletedBytes == 1_000)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deletesPermittedAndRefusesOutsideRoots() throws {
        let fixture = try Fixture()
        let inside = try fixture.file("Caches/a/data", bytes: 1_000).deletingLastPathComponent()
        let outside = try fixture.file("Documents/keep.txt", bytes: 1_000)
        let safety = SafetyGuard(allowedRoots: [fixture.root.appendingPathComponent("Caches")], appBundle: nil)
        let report = Cleaner().clean([
            ScanItem(url: inside, size: 1_000, category: .userCaches),
            ScanItem(url: outside, size: 1_000, category: .userCaches),
        ], guard: safety, deleteRegenerablePermanently: true)

        #expect(!FileManager.default.fileExists(atPath: inside.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(report.cleaned.map(\.url) == [inside])
        #expect(report.failures.map(\.item.url) == [outside])
    }
}
