#!/bin/zsh
# Packages build/DeepCleaner.app into a drag-to-Applications DMG plus a SHA-256 checksum.
# Run scripts/build-app.sh first. Output: build/DeepCleaner-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
app="build/DeepCleaner.app"
[[ -d "$app" ]] || { echo "Missing $app — run scripts/build-app.sh first" >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="build/DeepCleaner-$version.dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$dmg" "$dmg.sha256"
hdiutil create -quiet -volname "DeepCleaner" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
(cd build && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")

echo "Built $dmg"
