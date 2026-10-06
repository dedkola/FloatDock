#!/bin/bash
set -euo pipefail

FLOATDOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$FLOATDOCK_ROOT/scripts/toolchain.sh"
FLOATDOCK_PATH_HASH="$(printf '%s' "$FLOATDOCK_ROOT" | /usr/bin/shasum -a 256)"
FLOATDOCK_TEST_BUILD_PATH="${FLOATDOCK_TEST_BUILD_PATH:-$HOME/Library/Caches/FloatDock/tests-${FLOATDOCK_PATH_HASH:0:12}}"
FLOATDOCK_TEST_FLAGS=(--enable-swift-testing --disable-xctest)
FLOATDOCK_SWIFTC="$(/usr/bin/xcrun --find swiftc)"
FLOATDOCK_TESTING_PLUGIN="$(dirname "$FLOATDOCK_SWIFTC")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$FLOATDOCK_TESTING_PLUGIN" ]]; then
    # Some Command Line Tools versions don't discover this nested macro plugin.
    FLOATDOCK_TEST_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$FLOATDOCK_TESTING_PLUGIN")
fi
/usr/bin/swift test --package-path "$FLOATDOCK_ROOT" --scratch-path "$FLOATDOCK_TEST_BUILD_PATH" --arch arm64 --sdk "$FLOATDOCK_SDK_PATH" "${FLOATDOCK_TEST_FLAGS[@]}" "$@"
