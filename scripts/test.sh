#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, SwiftPM can't load the
# swift-testing macro plugin on its own, so point the compiler at it explicitly.
set -euo pipefail

cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$plugins" ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
else
    swift test "$@"
fi
