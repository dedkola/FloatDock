#!/bin/bash
# Shared by build and test scripts. Source this file so both use the same SDK.

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
    printf 'Apple developer directory not found: %s\n' "$DEVELOPER_DIR" >&2
    return 1
fi

if [[ -z "${FLOATDOCK_SDK_PATH:-}" ]]; then
    if FLOATDOCK_SDK_PATH="$(/usr/bin/xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null)"; then
        :
    elif FLOATDOCK_SDK_PATH="$(/usr/bin/xcrun --sdk macosx26 --show-sdk-path 2>/dev/null)"; then
        :
    else
        printf 'A macOS 26 SDK was not found. Set FLOATDOCK_SDK_PATH to an installed compatible SDK.\n' >&2
        return 1
    fi
fi
if [[ ! -d "$FLOATDOCK_SDK_PATH" ]]; then
    printf 'macOS SDK not found: %s\n' "$FLOATDOCK_SDK_PATH" >&2
    return 1
fi
export FLOATDOCK_SDK_PATH
