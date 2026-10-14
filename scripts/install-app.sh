#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--no-build" ]]; then
    shift
else
    "$ROOT/scripts/build-app.sh"
fi
if [[ $# -ne 0 ]]; then
    printf '%s\n' 'Usage: ./scripts/install-app.sh [--no-build]' >&2
    exit 1
fi

SOURCE_APP="$ROOT/dist/Screenroom.app"
INSTALL_DIR="${SCREENROOM_INSTALL_DIR:-/Applications}"
APP_PATH="$INSTALL_DIR/Screenroom.app"
REGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

if /usr/bin/pgrep -x Screenroom >/dev/null; then
    printf '%s\n' 'Quit Screenroom before installing so recordings and unsaved edits remain safe.' >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$SOURCE_APP"
if [[ -e "$APP_PATH" ]]; then
    EXISTING_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")"
    if [[ "$EXISTING_ID" != 'app.screenroom.Screenroom' ]]; then
        printf '%s\n' 'The destination contains a different app; refusing to replace it.' >&2
        exit 1
    fi
fi

mkdir -p "$INSTALL_DIR"
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.Screenroom-install.XXXXXX")"
cleanup() {
    if [[ ! -e "$APP_PATH" && -d "$STAGING_DIR/previous.app" ]]; then
        mv "$STAGING_DIR/previous.app" "$APP_PATH"
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGING_DIR/Screenroom.app"
/usr/bin/codesign --verify --strict "$STAGING_DIR/Screenroom.app"
if [[ -d "$APP_PATH" ]]; then
    mv "$APP_PATH" "$STAGING_DIR/previous.app"
fi
mv "$STAGING_DIR/Screenroom.app" "$APP_PATH"

# Remove only this project's development registration. Keep one installed
# location so System Settings resolves the same bundle the user launches.
"$REGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
"$REGISTER" -f "$APP_PATH"
printf 'Installed: %s\n' "$APP_PATH"
printf '%s\n' 'Open Screenroom from Applications. If upgrading from an ad-hoc build, reauthorize this installed copy once.'
