#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_DIR/.build/local-cache"
SCRATCH_DIR="$PROJECT_DIR/.build/release-spm"
DIST_DIR="$PROJECT_DIR/dist"
ZIP_PATH="$DIST_DIR/VPN白名单守卫-macOS.zip"
ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon-1024.png"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
PACKAGE_STAGE_ROOT="${TMPDIR:-/private/tmp}/com.qiming.wifivpnallowlist-build-$UID"
APP_DIR="$PACKAGE_STAGE_ROOT/VPN 白名单守卫.app"

mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm" "$CACHE_DIR/xdg" "$DIST_DIR"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    SWIFT_COMMAND=(xcrun swift)
else
    SWIFT_COMMAND=(swift)
fi

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/swiftpm"
export XDG_CACHE_HOME="$CACHE_DIR/xdg"

"${SWIFT_COMMAND[@]}" build \
    --disable-sandbox \
    --package-path "$PROJECT_DIR" \
    --scratch-path "$SCRATCH_DIR" \
    --configuration release \
    --product WiFiVPNAllowlist

BIN_DIR="$("${SWIFT_COMMAND[@]}" build \
    --disable-sandbox \
    --package-path "$PROJECT_DIR" \
    --scratch-path "$SCRATCH_DIR" \
    --configuration release \
    --show-bin-path)"

rm -rf "$PACKAGE_STAGE_ROOT"
rm -f "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

install -m 755 "$BIN_DIR/WiFiVPNAllowlist" "$APP_DIR/Contents/MacOS/WiFiVPNAllowlist"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ -f "$ICON_SOURCE" ]]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

plutil -lint "$APP_DIR/Contents/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/Resources/WiFiVPNAllowlist.entitlements" \
    "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
rm -rf "$PACKAGE_STAGE_ROOT"

echo "Archive: $ZIP_PATH"
