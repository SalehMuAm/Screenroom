#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/Screenroom.app"
CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"

if ! xcrun --find swift >/dev/null 2>&1; then
    printf '%s\n' 'Swift is unavailable. Install Xcode or its command line tools first.' >&2
    exit 1
fi

# Privacy grants are tied to the signing requirement. Ad-hoc signing changes
# that requirement with every build, invalidating Screen Recording access.
if [[ -z "$SIGNING_IDENTITY" ]]; then
    IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
    SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITIES" | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]+) "Developer ID Application:.*$/\1/p' | head -n 1)"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITIES" | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]+) "Apple Development:.*$/\1/p' | head -n 1)"
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        printf '%s\n' 'No Apple code-signing identity is available. Create an Apple Development certificate in Xcode, or set SIGNING_IDENTITY to an existing identity.' >&2
        printf '%s\n' 'For a temporary build only, use SIGNING_IDENTITY=-. Its privacy permissions will not survive changed builds.' >&2
        exit 1
    fi
fi

mkdir -p "$BUILD_DIR/module-cache" "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security" "$DIST_DIR"
BUILD_OPTIONS=(
    --disable-sandbox
    --package-path "$ROOT"
    --scratch-path "$BUILD_DIR"
    --cache-path "$BUILD_DIR/cache"
    --config-path "$BUILD_DIR/config"
    --security-path "$BUILD_DIR/security"
    --configuration "$CONFIGURATION"
)

printf '%s\n' "Building Screenroom ($CONFIGURATION)…"
xcrun swift build "${BUILD_OPTIONS[@]}" --product Screenroom
BIN_DIR="$(xcrun swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"

ICON_DIR="$BUILD_DIR/assets/Screenroom.iconset"
mkdir -p "$ICON_DIR"
xcrun swift "$ROOT/scripts/make-icon.swift" "$ICON_DIR" "$BUILD_DIR/assets/Screenroom.icns"

STAGING_DIR="$(mktemp -d "$DIST_DIR/.screenroom-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Screenroom.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/Screenroom" "$STAGED_APP/Contents/MacOS/Screenroom"
# SwiftPM release executables retain debug-map paths to local object files.
# Strip only debug symbols from the bundled copy before signing; keep the
# original build products and all runtime symbols for local debugging.
if [[ "$CONFIGURATION" == release ]]; then
    xcrun strip -S "$STAGED_APP/Contents/MacOS/Screenroom"
fi
cp "$ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$BUILD_DIR/assets/Screenroom.icns" "$STAGED_APP/Contents/Resources/Screenroom.icns"
cp "$ROOT/LICENSE" "$STAGED_APP/Contents/Resources/LICENSE"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"
chmod 755 "$STAGED_APP/Contents/MacOS/Screenroom"
/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - --timestamp=none "$STAGED_APP"
else
    /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$STAGED_APP"
fi
/usr/bin/codesign --verify --strict "$STAGED_APP"

# Replace only the app bundle owned by this build, after compilation and signing succeed.
rm -rf "$APP_PATH"
mv "$STAGED_APP" "$APP_PATH"
printf '\nBuilt: %s\n' "$APP_PATH"
printf '%s\n' 'Install with ./scripts/install-app.sh --no-build, then open Screenroom from Applications.'
