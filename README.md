# DeepCleaner

A native SwiftUI macOS app for reviewing and freeing disk space. Nothing is removed until you review and confirm.

**Modules:** Smart Scan · System Junk · Developer Junk · Large & Old Files · Duplicates · Space Lens (treemap)

## Build & run
```sh
scripts/build-app.sh          # → build/DeepCleaner.app (ad-hoc signed)
open build/DeepCleaner.app
scripts/test.sh               # Swift Testing suite
```
Requires macOS 14+. Works with just the Command Line Tools — no Xcode project. Two workarounds make that possible:
- `@ViewState` (alias for `SwiftUI.State`) is used instead of `@State`, whose macro plugin ships only with Xcode in the macOS 27 SDK.
- `scripts/test.sh` passes `-plugin-path` for the swift-testing macros, which SwiftPM can't resolve on CLT alone.

Grant **Full Disk Access** (System Settings → Privacy & Security) so caches, logs and Mail data can be scanned. With ad-hoc signing, the grant may need re-adding after a rebuild.

## Layout
- `Sources/DeepCleanerCore` — scanners, size calculation, `SafetyGuard`, `Cleaner`, treemap layout (no UI)
- `Sources/DeepCleaner` — SwiftUI app; `CleanupModel` drives every scan → review → clean flow
- `Tests/DeepCleanerCoreTests` — fixture-based tests, including safety-guard checks
- `scripts/make-icon.swift` — draws the app icon in code; run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns`

## Safety model
Every deletion goes through `SafetyGuard`, which requires the path to sit strictly inside the scan's roots and rejects
system paths, top-level home folders, Keychains/Mail/iCloud and symlink escapes. Regenerable caches can be deleted
permanently; everything else (large files, duplicates, archives) goes to the Trash. Docker's disk image is report-only.
