import Foundation
import Testing
@testable import DeepCleanerCore

@Suite struct UpdateCheckerTests {
    @Test func comparesVersions() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("0.1.2") < v("0.1.10"))
        #expect(try v("v0.2.0") > v("0.1.99"))
        #expect(try v("0.1") == v("0.1.0"))
        #expect(try v("1.0.0-beta.1") == v("1.0.0"))
        #expect(try v("v0.1.1").description == "0.1.1")
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func parsesRelease() throws {
        let json = """
        {"tag_name":"v0.1.4","html_url":"https://github.com/ravipiplani/deepcleaner/releases/tag/v0.1.4","draft":false,"prerelease":false,
         "body":"## Install\\n1. Open the DMG\\n\\n## What's Changed\\n* Add Docker module by @someone in #5\\n\\n**Full Changelog**: https://example.com",
         "assets":[{"name":"DeepCleaner-0.1.4.dmg.sha256","browser_download_url":"https://example.com/a.sha256"},
                   {"name":"DeepCleaner-0.1.4.dmg","browser_download_url":"https://example.com/a.dmg"}]}
        """
        let release = try #require(UpdateChecker.parse(Data(json.utf8)))
        #expect(release.version == AppVersion("0.1.4"))
        #expect(release.downloadURL?.absoluteString == "https://example.com/a.dmg")
        #expect(release.changes == "* Add Docker module by @someone in #5")
    }

    @Test func ignoresDraftsAndPrereleases() {
        let json = #"{"tag_name":"v9.0.0","html_url":"https://example.com","prerelease":true}"#
        #expect(UpdateChecker.parse(Data(json.utf8)) == nil)
    }

    @Test func releaseWithoutChangesSection() {
        #expect(UpdateChecker.changes(in: "## Install\n1. Drag it") == nil)
    }
}
