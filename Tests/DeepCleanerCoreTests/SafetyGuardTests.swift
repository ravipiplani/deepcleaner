import Foundation
import Testing
@testable import DeepCleanerCore

@Suite struct SafetyGuardTests {
    let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func rejectsSystemAndHomeLocations() {
        let safety = SafetyGuard(allowedRoots: [URL(fileURLWithPath: "/")], home: home, appBundle: nil)
        for path in ["/System/Library", "/usr/bin/ls", "/Library/Preferences", "/Applications/Safari.app", "/etc/hosts", "/private/etc/hosts"] {
            #expect(throws: SafetyGuard.Violation.self) { try safety.validate(URL(fileURLWithPath: path)) }
        }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(home) }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(home.appendingPathComponent("Documents")) }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(home.appendingPathComponent("Library/Keychains/login.keychain-db")) }
    }

    @Test func allowsOnlyStrictlyInsideRoots() throws {
        let fixture = try Fixture()
        let cache = try fixture.dir("Caches")
        let item = try fixture.file("Caches/app/data.bin", bytes: 10)
        let safety = SafetyGuard(allowedRoots: [cache], home: home, appBundle: nil)

        try safety.validate(item)
        try safety.validate(cache.appendingPathComponent("app"))
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(cache) }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(fixture.root.appendingPathComponent("other")) }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(cache.appendingPathComponent("../other")) }
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(URL(string: "https://example.com/x")!) }
    }

    @Test func blocksSymlinkEscape() throws {
        let fixture = try Fixture()
        let cache = try fixture.dir("Caches")
        let outside = try fixture.dir("Precious")
        try fixture.file("Precious/thesis.pdf", bytes: 10)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("link"), withDestinationURL: outside)
        let safety = SafetyGuard(allowedRoots: [cache], home: home, appBundle: nil)

        // Deleting through the link would hit a file outside the allowed root.
        #expect(throws: SafetyGuard.Violation.self) { try safety.validate(cache.appendingPathComponent("link/thesis.pdf")) }
        // Deleting the link itself is fine.
        try safety.validate(cache.appendingPathComponent("link"))
    }
}
