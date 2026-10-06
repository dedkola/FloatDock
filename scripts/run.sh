#!/bin/bash
set -euo pipefail

FLOATDOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOATDOCK_CONFIGURATION="${1:-release}"
"$FLOATDOCK_ROOT/scripts/build.sh" "$FLOATDOCK_CONFIGURATION"
/usr/bin/open "$FLOATDOCK_ROOT/build/FloatDock.app"
