import Foundation
import Testing
@testable import DeepCleanerCore

@Suite struct DockerParserTests {
    static let sample = """
    {"Images":[
      {"Containers":"0","CreatedAt":"2026-11-06 11:37:32 +0530 IST","ID":"sha256:aaaa1111bbbb2222","Repository":"web","Tag":"latest","Size":"1.28GB","SharedSize":"13.5MB","UniqueSize":"1.27GB"},
      {"Containers":"0","CreatedAt":"2026-11-06 11:37:32 +0530 IST","ID":"sha256:aaaa1111bbbb2222","Repository":"web","Tag":"v2","Size":"1.28GB","SharedSize":"13.5MB","UniqueSize":"1.27GB"},
      {"Containers":"2","CreatedAt":"2026-11-05 13:05:21 +0530 IST","ID":"sha256:cccc3333","Repository":"redis","Tag":"7","Size":"192MB","SharedSize":"0B","UniqueSize":"192MB"},
      {"Containers":"0","CreatedAt":"2026-10-01 10:00:00 +0000 UTC","ID":"sha256:dddd4444","Repository":"<none>","Tag":"<none>","Size":"500MB","SharedSize":"N/A","UniqueSize":"N/A"}
    ],
    "Containers":[
      {"ID":"c1","Names":"api","Image":"redis:7","State":"running","Status":"Up 3 days","CreatedAt":"2026-11-06 17:49:50 +0530 IST","Size":"2.12MB"},
      {"ID":"c2","Names":"old-job","Image":"redis:7","State":"exited","Status":"Exited (0) 2 weeks ago","Size":"90.1kB"}
    ],
    "Volumes":[
      {"Name":"\(String(repeating: "ab", count: 32))","Links":"0","Size":"1.5GB","Labels":"com.docker.volume.anonymous="},
      {"Name":"shop_pgdata","Links":"1","Size":"300MB","Labels":"com.docker.compose.project=shop,com.docker.compose.volume=pgdata"}
    ],
    "BuildCache":[
      {"InUse":"false","Size":"1GB","LastUsedAt":"2026-10-16 07:17:11.898814755 +0000 UTC"},
      {"InUse":"true","Size":"200MB","LastUsedAt":"2026-10-20 07:17:11.1 +0000 UTC"}
    ]}
    """

    @Test func parsesEveryKind() throws {
        let resources = try DockerParser.parseSystemDF(Data(Self.sample.utf8))
        let byID = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })

        // Two tags of one image collapse into one item removed by both tags.
        let web = try #require(byID["image:sha256:aaaa1111bbbb2222"])
        #expect(web.refs == ["web:latest", "web:v2"])
        #expect(web.size == 1_270_000_000)
        #expect(web.isRemovable && !web.selectedByDefault)

        let redis = try #require(byID["image:sha256:cccc3333"])
        #expect(redis.blockedReason == "Used by 2 containers")

        let dangling = try #require(byID["image:sha256:dddd4444"])
        #expect(dangling.refs == ["sha256:dddd4444"])
        #expect(dangling.size == 500_000_000)
        #expect(dangling.selectedByDefault)

        #expect(byID["container:c1"]?.isRemovable == false)
        #expect(byID["container:c2"]?.isRemovable == true)
        #expect(byID["container:c2"]?.size == 90_100)

        let anonymous = try #require(resources.first { $0.kind == .volume && $0.isRemovable })
        #expect(anonymous.name == "Anonymous volume")
        #expect(!anonymous.selectedByDefault)
        let named = try #require(byID["volume:shop_pgdata"])
        #expect(!named.isRemovable)
        #expect(named.detail.contains("shop"))

        let cache = try #require(resources.first { $0.kind == .buildCache })
        #expect(cache.size == 1_000_000_000)
        #expect(cache.selectedByDefault)
        #expect(cache.created == DockerParser.parseDate("2026-10-20 07:17:11 +0000 UTC"))
    }

    @Test func recognisesBuildxBuilderVolumes() {
        #expect(DockerParser.buildxBuilder("buildx_buildkit_multiarch-builder0_state") == "multiarch-builder")
        #expect(DockerParser.buildxBuilder("shop_pgdata") == nil)
    }

    @Test func parsesSizes() {
        #expect(DockerParser.parseSize("1.28GB") == 1_280_000_000)
        #expect(DockerParser.parseSize("24.32kB") == 24_320)
        #expect(DockerParser.parseSize("0B") == 0)
        #expect(DockerParser.parseSize("2B") == 2)
        #expect(DockerParser.parseSize("1.5GiB") == 1_610_612_736)
        #expect(DockerParser.parseSize("90.1kB (virtual 212MB)") == 90_100)
        #expect(DockerParser.parseSize("N/A") == 0)
        #expect(DockerParser.parseSize(nil) == 0)
    }

    @Test func parsesDates() throws {
        let date = try #require(DockerParser.parseDate("2026-11-06 11:37:32 +0530 IST"))
        #expect(date == Date(timeIntervalSince1970: 1_793_945_252))
        #expect(DockerParser.parseDate("2026-10-16 07:16:53.726917719 +0000 UTC") != nil)
        #expect(DockerParser.parseDate("garbage") == nil)
    }

    @Test func readsPruneTotals() {
        #expect(DockerClient.reclaimedTotal(in: ["ID  RECLAIMABLE", "abc true 1MB", "Total:\t14.75GB"]) == 14_750_000_000)
        #expect(DockerClient.reclaimedTotal(in: ["Deleted build cache objects:", "Total reclaimed space: 1.2GB"]) == 1_200_000_000)
        #expect(DockerClient.reclaimedTotal(in: []) == nil)
    }

    @Test func blockedResourcesAreNeverRemoved() async {
        let client = DockerClient(executable: URL(fileURLWithPath: "/usr/bin/false"))
        let running = DockerResource(kind: .container, key: "c1", refs: ["c1"], name: "api", detail: "", size: 1, blockedReason: "Running")
        let report = await client.remove([running])
        #expect(report.removed.isEmpty)
        #expect(report.failures.map(\.message) == ["Running"])
    }
}
