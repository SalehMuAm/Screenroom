#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${SCREENROOM_INSTALL_DIR:-/Applications}/Screenroom.app"
if [[ "${1:-}" == "--no-build" ]]; then
    shift
else
    "$ROOT/scripts/install-app.sh"
fi

if [[ $# -ne 0 ]]; then
    printf '%s\n' 'Usage: ./scripts/run.sh [--no-build]' >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    printf '%s\n' 'Screenroom.app is not installed. Run ./scripts/install-app.sh first.' >&2
    exit 1
fi
/usr/bin/open "$APP_PATH"
