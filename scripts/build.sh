#!/bin/bash
set -euo pipefail

FLOATDOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOATDOCK_CONFIGURATION="${1:-release}"
FLOATDOCK_VARIANT="${2:-}"

if [[ "$FLOATDOCK_CONFIGURATION" != "debug" && "$FLOATDOCK_CONFIGURATION" != "release" ]]; then
    printf 'Usage: %s [debug|release] [--sandbox]\n' "$0" >&2
    exit 2
fi
if [[ -n "$FLOATDOCK_VARIANT" && "$FLOATDOCK_VARIANT" != "--sandbox" ]]; then
    printf 'Usage: %s [debug|release] [--sandbox]\n' "$0" >&2
    exit 2
fi

source "$FLOATDOCK_ROOT/scripts/toolchain.sh"

FLOATDOCK_APP_NAME="FloatDock"
FLOATDOCK_ENTITLEMENTS="$FLOATDOCK_ROOT/Config/FloatDock.entitlements"
if [[ "$FLOATDOCK_VARIANT" == "--sandbox" ]]; then
    FLOATDOCK_APP_NAME="FloatDock-Sandbox"
    FLOATDOCK_ENTITLEMENTS="$FLOATDOCK_ROOT/Config/FloatDock-Sandbox.entitlements"
fi
FLOATDOCK_APP="$FLOATDOCK_ROOT/build/$FLOATDOCK_APP_NAME.app"
FLOATDOCK_PATH_HASH="$(printf '%s' "$FLOATDOCK_ROOT" | /usr/bin/shasum -a 256)"
FLOATDOCK_STAGING_ROOT="$HOME/Library/Caches/FloatDock/bundles-${FLOATDOCK_PATH_HASH:0:12}"
mkdir -p "$FLOATDOCK_STAGING_ROOT"
FLOATDOCK_STAGING_DIR="$(/usr/bin/mktemp -d "$FLOATDOCK_STAGING_ROOT/local.XXXXXX")"
FLOATDOCK_STAGED_APP="$FLOATDOCK_STAGING_DIR/$FLOATDOCK_APP_NAME.app"
FLOATDOCK_INSTALL_DIR=""
trap 'if [[ -n "$FLOATDOCK_INSTALL_DIR" && -d "$FLOATDOCK_INSTALL_DIR" ]]; then /bin/rm -rf "$FLOATDOCK_INSTALL_DIR"; fi' EXIT

/usr/bin/swift build --package-path "$FLOATDOCK_ROOT" --configuration "$FLOATDOCK_CONFIGURATION" --arch arm64 --sdk "$FLOATDOCK_SDK_PATH"
FLOATDOCK_BIN_DIR="$(/usr/bin/swift build --package-path "$FLOATDOCK_ROOT" --configuration "$FLOATDOCK_CONFIGURATION" --arch arm64 --sdk "$FLOATDOCK_SDK_PATH" --show-bin-path)"
mkdir -p "$FLOATDOCK_STAGED_APP/Contents/MacOS" "$FLOATDOCK_STAGED_APP/Contents/Resources" "$FLOATDOCK_ROOT/build"
cp "$FLOATDOCK_BIN_DIR/FloatDockApp" "$FLOATDOCK_STAGED_APP/Contents/MacOS/FloatDock"
cp "$FLOATDOCK_ROOT/Config/Info.plist" "$FLOATDOCK_STAGED_APP/Contents/Info.plist"
if [[ "$FLOATDOCK_VARIANT" == "--sandbox" ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.floatdock.local.sandbox' "$FLOATDOCK_STAGED_APP/Contents/Info.plist"
fi
printf 'APPL????' > "$FLOATDOCK_STAGED_APP/Contents/PkgInfo"
# Documents may be managed by a file provider that adds Finder metadata to bundles.
# Keep the signed bundle outside Documents: its file provider can add disallowed
# Finder metadata after copying. Every build gets an immutable bundle so rebuilding
# never truncates a running executable. The workspace output links to that bundle.
/usr/bin/xattr -cr "$FLOATDOCK_STAGED_APP"
/usr/bin/codesign --force --sign - --entitlements "$FLOATDOCK_ENTITLEMENTS" "$FLOATDOCK_STAGED_APP"
/usr/bin/codesign --verify --strict "$FLOATDOCK_STAGED_APP"
FLOATDOCK_INSTALL_DIR="$(/usr/bin/mktemp -d "$FLOATDOCK_ROOT/build/.floatdock-install.XXXXXX")"
/bin/ln -s "$FLOATDOCK_STAGED_APP" "$FLOATDOCK_INSTALL_DIR/$FLOATDOCK_APP_NAME.app"
/usr/bin/codesign --verify --strict "$FLOATDOCK_INSTALL_DIR/$FLOATDOCK_APP_NAME.app"
if [[ -e "$FLOATDOCK_APP" || -L "$FLOATDOCK_APP" ]]; then
    /bin/mv "$FLOATDOCK_APP" "$FLOATDOCK_INSTALL_DIR/previous.app"
fi
if ! /bin/mv "$FLOATDOCK_INSTALL_DIR/$FLOATDOCK_APP_NAME.app" "$FLOATDOCK_APP"; then
    if [[ -e "$FLOATDOCK_INSTALL_DIR/previous.app" ]]; then
        /bin/mv "$FLOATDOCK_INSTALL_DIR/previous.app" "$FLOATDOCK_APP"
    fi
    exit 1
fi
/usr/bin/codesign --verify --strict "$FLOATDOCK_APP"
printf 'Built %s\n' "$FLOATDOCK_APP"
