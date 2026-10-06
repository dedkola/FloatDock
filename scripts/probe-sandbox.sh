#!/bin/bash
set -euo pipefail

FLOATDOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOATDOCK_SAMPLES="${1:-4}"
if ! [[ "$FLOATDOCK_SAMPLES" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Usage: %s [positive sample count]\n' "$0" >&2
    exit 2
fi

"$FLOATDOCK_ROOT/scripts/build.sh" release --sandbox
"$FLOATDOCK_ROOT/build/FloatDock-Sandbox.app/Contents/MacOS/FloatDock" --probe "$FLOATDOCK_SAMPLES" > "$FLOATDOCK_ROOT/build/sandbox-probe.jsonl"
printf 'Sandbox probe saved to %s\n' "$FLOATDOCK_ROOT/build/sandbox-probe.jsonl"
