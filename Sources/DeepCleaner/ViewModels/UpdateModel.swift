import DeepCleanerCore
import Foundation
import Observation

/// Checks GitHub for a newer release on launch (at most twice a day) and on demand.
@MainActor
@Observable
final class UpdateModel {
    enum Status: Equatable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Whether the update sheet is showing (opened from the menu or the sidebar banner).
    var isSheetPresented = false

    /// The running app's version; nil for a bare `swift run` binary, which has no Info.plist.
    let currentVersion: AppVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        .flatMap(AppVersion.init)

    private let checker = UpdateChecker()
    private let defaults = UserDefaults.standard
    private static let lastCheckKey = "updates.lastCheck"
    private static let skippedKey = "updates.skippedVersion"
    private static let automaticInterval: TimeInterval = 12 * 3600

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = status { release } else { nil }
    }

    /// Shown in the sidebar unless the user skipped this version.
    var bannerRelease: ReleaseInfo? {
        guard let release = availableRelease, release.version.description != defaults.string(forKey: Self.skippedKey) else {
            return nil
        }
        return release
    }

    func checkAutomatically() {
        guard currentVersion != nil else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.automaticInterval { return }
        Task { await check() }
    }

    func checkFromMenu() {
        isSheetPresented = true
        Task { await check() }
    }

    func check() async {
        guard status != .checking else { return }
        guard let currentVersion else {
            status = .failed("This is a development build without a version number, so there's nothing to compare.")
            return
        }
        status = .checking
        do {
            let version = currentVersion.description
            let newer = try await Task.detached { [checker] in
                try await checker.newerRelease(than: currentVersion, appVersion: version)
            }.value
            defaults.set(Date(), forKey: Self.lastCheckKey)
            status = newer.map(Status.available) ?? .upToDate
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func skip(_ release: ReleaseInfo) {
        defaults.set(release.version.description, forKey: Self.skippedKey)
        isSheetPresented = false
    }
}
