#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenroom-shell-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Use isolated copies with inert dependencies. These checks cannot build,
# replace, or open the user's installed app, even if argument parsing regresses.
check_arguments() {
    local script="$1" dependency="$2" fixture status
    fixture="$TEST_DIR/$script"
    mkdir -p "$fixture/scripts"
    cp "$ROOT/scripts/$script" "$fixture/scripts/$script"
    cat > "$fixture/scripts/$dependency" <<'STUB'
#!/bin/bash
touch "$(dirname "$0")/invoked"
exit 73
STUB
    chmod +x "$fixture/scripts/$dependency"

    "$fixture/scripts/$script" --help > "$fixture/output" 2>&1 || fail "$script --help failed"
    [[ ! -e "$fixture/scripts/invoked" ]] || fail "$script --help invoked $dependency"

    for argument in --unknown --no-buid; do
        if "$fixture/scripts/$script" "$argument" > "$fixture/output" 2>&1; then
            fail "$script accepted $argument"
        fi
        [[ ! -e "$fixture/scripts/invoked" ]] || fail "$script $argument invoked $dependency"
    done
    if "$fixture/scripts/$script" --no-build extra > "$fixture/output" 2>&1; then
        fail "$script accepted extra arguments"
    fi
    [[ ! -e "$fixture/scripts/invoked" ]] || fail "$script with extra arguments invoked $dependency"

    status=0
    "$fixture/scripts/$script" > "$fixture/output" 2>&1 || status=$?
    [[ "$status" -eq 73 && -e "$fixture/scripts/invoked" ]] || fail "$script did not invoke $dependency with no arguments"
}

check_arguments install-app.sh build-app.sh
check_arguments run.sh install-app.sh

if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'Argument checks passed; bundle packaging checks require macOS.'
    exit 0
fi

# A tiny disposable app exercises real macOS signatures and packaging without
# using dist/Screenroom.app or requiring a full Screenroom build.
APP_PATH="$TEST_DIR/input/Screenroom.app"
mkdir -p "$APP_PATH/Contents/MacOS"
printf '%s\n' 'int main(void) { return 0; }' > "$TEST_DIR/fixture.c"
xcrun clang "$TEST_DIR/fixture.c" -o "$APP_PATH/Contents/MacOS/Screenroom"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.screenroom.Screenroom</string>
<key>CFBundleExecutable</key><string>Screenroom</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$APP_PATH"

reject_output() {
    local destination="$1"
    # Bound output size if a regression permits archiving inside the bundle.
    if (ulimit -f 4096; "$ROOT/scripts/package-release.sh" "$APP_PATH" "$destination") > "$TEST_DIR/packaging-output" 2>&1; then
        fail "Packager accepted output inside its app: $destination"
    fi
    if ! /usr/bin/grep -q 'Output directory must be outside the app bundle.' "$TEST_DIR/packaging-output"; then
        cat "$TEST_DIR/packaging-output" >&2
        fail 'Packager did not reject the output path before archiving'
    fi
    codesign --verify --strict "$APP_PATH"
}

reject_output "$APP_PATH"
reject_output "$APP_PATH/new/nested"
ln -s "$APP_PATH" "$TEST_DIR/app-alias"
reject_output "$TEST_DIR/app-alias/new/nested"
if [[ -d "$TEST_DIR/input/screenroom.app" ]]; then
    reject_output "$TEST_DIR/input/screenroom.app"
    reject_output "$TEST_DIR/input/screenroom.app/new/nested"
    ORIGINAL_APP_PATH="$APP_PATH"
    APP_PATH="$TEST_DIR/INPUT/Screenroom.app"
    reject_output "$ORIGINAL_APP_PATH/new/nested"
    APP_PATH="$ORIGINAL_APP_PATH"
else
    printf '%s\n' 'Case-alias checks skipped on a case-sensitive filesystem.'
fi
[[ ! -e "$APP_PATH/new" ]] || fail 'Rejected packaging created a directory inside the app'

BUNDLE_OUTPUT="$TEST_DIR/output/new/nested"
"$ROOT/scripts/package-release.sh" "$APP_PATH" "$BUNDLE_OUTPUT"
(
    cd "$BUNDLE_OUTPUT"
    shasum -a 256 -c Screenroom-*.zip.sha256
    unzip -t Screenroom-*.zip > /dev/null
)
if "$ROOT/scripts/package-release.sh" "$APP_PATH" "$BUNDLE_OUTPUT" > "$TEST_DIR/packaging-output" 2>&1; then
    fail 'Packager overwrote an existing release'
fi
(
    cd "$BUNDLE_OUTPUT"
    shasum -a 256 -c Screenroom-*.zip.sha256
)
codesign --verify --strict "$APP_PATH"
printf '%s\n' 'Shell regression checks passed.'
