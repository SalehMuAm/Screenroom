#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--no-build" ]]; then
    shift
else
    "$ROOT/scripts/build-app.sh"
fi

if [[ $# -ne 0 ]]; then
    printf '%s\n' 'Usage: ./scripts/run.sh [--no-build]' >&2
    exit 1
fi

APP_PATH="$ROOT/dist/Screenroom.app"
if [[ ! -d "$APP_PATH" ]]; then
    printf '%s\n' 'Screenroom.app has not been built. Run ./scripts/build-app.sh first.' >&2
    exit 1
fi
/usr/bin/open "$APP_PATH"
