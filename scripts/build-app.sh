#!/bin/zsh
# Builds DeepCleaner.app with SwiftPM (no Xcode project needed) and ad-hoc signs it.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
#
# Optional environment:
#   VERSION=0.1.3     sets CFBundleShortVersionString in the bundle
#   BUILD_NUMBER=42   sets CFBundleVersion in the bundle
#   UNIVERSAL=1       builds for both arm64 and x86_64
set -euo pipefail

cd "$(dirname "$0")/.."
config="${1:-release}"
app="build/DeepCleaner.app"

build_args=(-c "$config" --product DeepCleaner)
[[ "${UNIVERSAL:-0}" == 1 ]] && build_args+=(--arch arm64 --arch x86_64)

swift build "${build_args[@]}"
bin="$(swift build "${build_args[@]}" --show-bin-path)/DeepCleaner"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/DeepCleaner"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"  # regenerate with: swift scripts/make-icon.swift

plist="$app/Contents/Info.plist"
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist"
[[ -n "${BUILD_NUMBER:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"

# Ad-hoc signature: enough to run locally. A stable identity matters for Full Disk Access,
# since macOS ties the grant to the signature — re-grant after rebuilding if access is lost.
codesign --force --sign - "$app"

echo "Built $app ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist"), $(lipo -archs "$app/Contents/MacOS/DeepCleaner"))"
