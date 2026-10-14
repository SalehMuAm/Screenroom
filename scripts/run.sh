#!/bin/bash
set -euo pipefail

usage() {
    printf '%s\n' 'Usage: ./scripts/run.sh [--no-build]'
}
if [[ $# -eq 1 && "$1" == "--help" ]]; then
    usage
    exit 0
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--no-build" ) ]]; then
    usage >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${SCREENROOM_INSTALL_DIR:-/Applications}/Screenroom.app"
if [[ $# -eq 0 ]]; then
    "$ROOT/scripts/install-app.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
    printf '%s\n' 'Screenroom.app is not installed. Run ./scripts/install-app.sh first.' >&2
    exit 1
fi
/usr/bin/open "$APP_PATH"
