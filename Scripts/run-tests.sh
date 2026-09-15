#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_DIR/.build/local-cache"
SCRATCH_DIR="$PROJECT_DIR/.build/test-spm"

mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm" "$CACHE_DIR/xdg"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    SWIFT_COMMAND=(xcrun swift)
else
    SWIFT_COMMAND=(swift)
fi

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/swiftpm"
export XDG_CACHE_HOME="$CACHE_DIR/xdg"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    "${SWIFT_COMMAND[@]}" test \
        --disable-sandbox \
        --package-path "$PROJECT_DIR" \
        --scratch-path "$SCRATCH_DIR"
else
    "${SWIFT_COMMAND[@]}" build \
        --disable-sandbox \
        --package-path "$PROJECT_DIR" \
        --scratch-path "$SCRATCH_DIR" \
        --product WiFiVPNAllowlist
    BIN_DIR="$("${SWIFT_COMMAND[@]}" build \
        --disable-sandbox \
        --package-path "$PROJECT_DIR" \
        --scratch-path "$SCRATCH_DIR" \
        --show-bin-path)"
    "$BIN_DIR/WiFiVPNAllowlist" --traffic-self-test
    echo "Full XCTest suite requires Xcode; app build and traffic self-test passed with Command Line Tools."
fi
