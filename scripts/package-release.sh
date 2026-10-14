#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT/dist/Screenroom.app}"
DIST_DIR="${2:-$ROOT/dist}"

if [[ $# -gt 2 ]]; then
    printf '%s\n' 'Usage: ./scripts/package-release.sh [path/to/Screenroom.app [output-directory]]' >&2
    exit 1
fi
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'Packaging requires macOS and Xcode command line tools.' >&2
    exit 1
fi
if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
    printf '%s\n' 'App bundle is missing. Build it with ./scripts/build-app.sh, or pass an existing Screenroom.app path.' >&2
    exit 1
fi
APP_PATH="$(cd -P "$APP_PATH" && pwd -P)"
PLIST="$APP_PATH/Contents/Info.plist"
if [[ "$(basename "$APP_PATH")" != Screenroom.app ]]; then
    printf '%s\n' 'The bundle directory must be named Screenroom.app.' >&2
    exit 1
fi

/usr/bin/plutil -lint "$PLIST"
IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$PLIST")"
EXECUTABLE="$(/usr/bin/plutil -extract CFBundleExecutable raw "$PLIST")"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$PLIST")"
if [[ "$IDENTIFIER" != app.screenroom.Screenroom || "$EXECUTABLE" != Screenroom ]]; then
    printf '%s\n' 'The bundle is not Screenroom; refusing to package it.' >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    printf '%s\n' 'CFBundleShortVersionString must contain one to three numeric components.' >&2
    exit 1
fi
if [[ ! -x "$APP_PATH/Contents/MacOS/$EXECUTABLE" ]]; then
    printf '%s\n' 'The bundle executable is missing or not executable.' >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$APP_PATH"

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE")"
case "$ARCHITECTURES" in
    arm64) ARCH=arm64 ;;
    x86_64) ARCH=x86_64 ;;
    'arm64 x86_64'|'x86_64 arm64') ARCH=universal ;;
    *) printf 'Unsupported executable architectures: %s\n' "$ARCHITECTURES" >&2; exit 1 ;;
esac

# Resolve existing symlinks before creating output directories. Packaging into
# the app itself would modify its signed contents and archive its own output.
canonical_directory() {
    local path="$1" parent leaf resolved
    if [[ -d "$path" ]]; then
        (cd -P "$path" && pwd -P)
    elif [[ -e "$path" || -L "$path" ]]; then
        printf 'Output path is not a directory: %s\n' "$path" >&2
        return 1
    else
        parent="$(canonical_directory "$(dirname "$path")")" || return 1
        leaf="$(basename "$path")"
        case "$leaf" in
            .) printf '%s\n' "$parent" ;;
            ..) dirname "$parent" ;;
            *)
                resolved="${parent%/}/$leaf"
                if [[ -d "$resolved" ]]; then
                    (cd -P "$resolved" && pwd -P)
                elif [[ -e "$resolved" || -L "$resolved" ]]; then
                    printf 'Output path is not a directory: %s\n' "$resolved" >&2
                    return 1
                else
                    printf '%s\n' "$resolved"
                fi
                ;;
        esac
    fi
}
DIST_DIR="$(canonical_directory "$DIST_DIR")"
case "$DIST_DIR" in
    "$APP_PATH"|"$APP_PATH"/*)
        printf '%s\n' 'Output directory must be outside the app bundle.' >&2
        exit 1
        ;;
esac
mkdir -p "$DIST_DIR"

ARCHIVE_NAME="Screenroom-$VERSION-macos-$ARCH.zip"
CHECKSUM_NAME="$ARCHIVE_NAME.sha256"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$DIST_DIR/$CHECKSUM_NAME"
if [[ -e "$ARCHIVE_PATH" || -L "$ARCHIVE_PATH" || -e "$CHECKSUM_PATH" || -L "$CHECKSUM_PATH" ]]; then
    printf 'An archive or checksum already exists for %s; refusing to overwrite it.\n' "$VERSION" >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "$DIST_DIR/.screenroom-package.XXXXXX")"
CREATED_ARCHIVE=false
COMPLETE=false
cleanup() {
    if [[ "$CREATED_ARCHIVE" == true && "$COMPLETE" != true ]]; then
        rm -f "$ARCHIVE_PATH"
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

# Archive bundle files, including the signature, without local filesystem
# metadata or __MACOSX resource-fork entries. This never re-signs the app.
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_PATH" "$STAGING_DIR/$ARCHIVE_NAME"
(
    cd "$STAGING_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM_NAME"
)
# Hard links on the same volume publish completed files without replacing
# an existing artifact, including one created concurrently after the check.
ln "$STAGING_DIR/$ARCHIVE_NAME" "$ARCHIVE_PATH"
CREATED_ARCHIVE=true
ln "$STAGING_DIR/$CHECKSUM_NAME" "$CHECKSUM_PATH"
COMPLETE=true

printf 'Archive: %s\nChecksum: %s\n' "$ARCHIVE_PATH" "$CHECKSUM_PATH"
printf '%s\n' 'This command only packages the existing app. For a notarized release, complete Developer ID signing and notarization before packaging.'
