#!/bin/zsh
# Builds DeepCleaner.app with SwiftPM (no Xcode project needed) and ad-hoc signs it.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

cd "$(dirname "$0")/.."
config="${1:-release}"
app="build/DeepCleaner.app"

swift build -c "$config" --product DeepCleaner
bin="$(swift build -c "$config" --show-bin-path)/DeepCleaner"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/DeepCleaner"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"  # regenerate with: swift scripts/make-icon.swift

# Ad-hoc signature: enough to run locally. A stable identity matters for Full Disk Access,
# since macOS ties the grant to the signature — re-grant after rebuilding if access is lost.
codesign --force --sign - "$app"

echo "Built $app"
