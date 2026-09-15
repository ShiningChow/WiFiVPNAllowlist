#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZIP_PATH="$PROJECT_DIR/dist/VPN白名单守卫-macOS.zip"
INSTALL_PATH="/Applications/VPN 白名单守卫.app"
INSTALL_STAGE_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/com.qiming.wifivpnallowlist-install.XXXXXX")"
EXTRACTED_APP="$INSTALL_STAGE_ROOT/VPN 白名单守卫.app"
PREVIOUS_APP="$INSTALL_STAGE_ROOT/Previous VPN 白名单守卫.app"

cleanup() {
    rm -rf "$INSTALL_STAGE_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$ZIP_PATH" ]]; then
    "$SCRIPT_DIR/build-app.sh"
fi

ditto -x -k "$ZIP_PATH" "$INSTALL_STAGE_ROOT"
codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"

pkill -x WiFiVPNAllowlist 2>/dev/null || true

if [[ -e "$INSTALL_PATH" ]]; then
    mv "$INSTALL_PATH" "$PREVIOUS_APP"
fi

if ! ditto "$EXTRACTED_APP" "$INSTALL_PATH"; then
    if [[ -e "$PREVIOUS_APP" ]]; then
        mv "$PREVIOUS_APP" "$INSTALL_PATH"
    fi
    exit 1
fi

xattr -cr "$INSTALL_PATH"
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/Resources/WiFiVPNAllowlist.entitlements" \
    "$INSTALL_PATH"
codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"

LOGIN_OUTPUT="$("$INSTALL_PATH/Contents/MacOS/WiFiVPNAllowlist" --register-login-item)"
STATUS_OUTPUT="$("$INSTALL_PATH/Contents/MacOS/WiFiVPNAllowlist" --login-item-status)"

open "$INSTALL_PATH" 2>/dev/null || true

echo "Installed: $INSTALL_PATH"
echo "$LOGIN_OUTPUT"
echo "$STATUS_OUTPUT"
