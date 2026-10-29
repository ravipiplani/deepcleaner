import Foundation
import Testing
@testable import DeepCleanerCore

@Suite struct ScannerTests {
    @Test func sizeCountsHardLinksOnce() throws {
        let fixture = try Fixture()
        let a = try fixture.file("dir/a.bin", bytes: 200_000)
        try FileManager.default.linkItem(at: a, to: fixture.root.appendingPathComponent("dir/b.bin"))
        let single = SizeCalculator.allocatedSize(of: a)
        #expect(single >= 200_000)
        #expect(SizeCalculator.allocatedSize(of: fixture.root.appendingPathComponent("dir")) == single)
    }

    @Test func sizeIgnoresSymlinks() throws {
        let fixture = try Fixture()
        try fixture.file("big.bin", bytes: 500_000)
        let dir = try fixture.dir("dir")
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: fixture.root.appendingPathComponent("big.bin"))
        #expect(SizeCalculator.allocatedSize(of: dir) == 0)
    }

    @Test func ruleScannerHonoursExclusionsAndAge() async throws {
        let fixture = try Fixture()
        let old = Date().addingTimeInterval(-10 * 86_400)
        try fixture.file("Caches/com.example.app/cache.db", bytes: 50_000)
        try fixture.file("Caches/CloudKit/db", bytes: 50_000)
        try fixture.file("Tmp/old.tmp", bytes: 10_000, modified: old)
        try fixture.file("Tmp/new.tmp", bytes: 10_000)
        let rules = [
            JunkRule(.userCaches, fixture.root.appendingPathComponent("Caches"), excluding: ["CloudKit"]),
            JunkRule(.tempFiles, fixture.root.appendingPathComponent("Tmp"), minAge: 3 * 86_400),
        ]
        let result = await RuleScanner(rules: rules).scan(progress: ScanProgress())
        #expect(Set(result.items.map(\.displayName)) == ["com.example.app", "old.tmp"])
        #expect(result.items.allSatisfy { $0.selectedByDefault })
    }

    @Test func findsTopLevelNodeModulesOnly() async throws {
        let fixture = try Fixture()
        try fixture.file("web/package.json", bytes: 10)
        try fixture.file("web/node_modules/react/index.js", bytes: 40_000)
        try fixture.file("web/node_modules/react/node_modules/x/index.js", bytes: 40_000)
        try fixture.file("api/node_modules/express/index.js", bytes: 40_000)
        var scanner = DevJunkScanner(projectRoots: [fixture.root], home: fixture.root.appendingPathComponent("nohome"))
        scanner.staleProjectAge = 0
        let result = await scanner.scan(progress: ScanProgress())
        let modules = result.items.filter { $0.category == .nodeModules }
        #expect(Set(modules.map(\.displayName)) == ["web", "api"])
    }

    @Test func largeFilesRespectThresholdAndExclusions() async throws {
        let fixture = try Fixture()
        try fixture.file("Movies/clip.mov", bytes: 3_000_000)
        try fixture.file("Movies/small.mov", bytes: 10_000)
        try fixture.file("Library/huge.cache", bytes: 3_000_000)
        try fixture.file(".hidden/huge.bin", bytes: 3_000_000)
        let scanner = LargeOldFilesScanner(
            roots: [fixture.root], excluded: [fixture.root.appendingPathComponent("Library")], minSize: 1_000_000
        )
        let result = await scanner.scan(progress: ScanProgress())
        #expect(result.items.map(\.displayName) == ["clip.mov"])
        #expect(result.items.first?.groupTitle == FileKind.video.title)
    }

    @Test func duplicatesGroupIdenticalContentAndKeepOne() async throws {
        let fixture = try Fixture()
        try fixture.file("a/photo.jpg", bytes: 300_000, fill: 1)
        try fixture.file("b/photo copy.jpg", bytes: 300_000, fill: 1)
        try fixture.file("c/photo-2.jpg", bytes: 300_000, fill: 1)
        try fixture.file("d/same-size-different.jpg", bytes: 300_000, fill: 2)
        let original = try fixture.file("e/linked.bin", bytes: 300_000, fill: 3)
        try FileManager.default.linkItem(at: original, to: fixture.root.appendingPathComponent("e/hardlink.bin"))

        let result = await DuplicateScanner(roots: [fixture.root], excluded: [], minSize: 100_000).scan(progress: ScanProgress())
        #expect(result.items.count == 3)
        #expect(Set(result.items.map(\.effectiveGroupID)).count == 1)
        #expect(result.items.filter(\.selectedByDefault).count == 2)
    }

    @Test func diskTreeAggregatesSmallItems() async throws {
        let fixture = try Fixture()
        try fixture.file("big/a.bin", bytes: 2_000_000)
        for i in 0..<5 { try fixture.file("small/\(i).txt", bytes: 1_000) }
        let tree = await DiskTreeBuilder(minNodeSize: 1_000_000).build(fixture.root, progress: ScanProgress())
        #expect(tree.children.first?.name == "big")
        #expect(tree.children.last?.isAggregate == true)
        #expect(tree.size == tree.children.reduce(0) { $0 + $1.size })

        var mutable = tree
        let bigFile = try #require(tree.children.first?.children.first)
        let removed = mutable.remove(id: bigFile.id)
        #expect(removed == bigFile.size)
        #expect(mutable.size == tree.size - bigFile.size)
    }
}
