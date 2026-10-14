# Set up Screenroom

Screenroom needs **macOS 15 or later**. Building from source also needs **Xcode 16 or later**, including its macOS SDK. The app uses only Apple frameworks; there are no package dependencies or audio drivers to install.

Xcode is not needed to run a downloaded app. A source build uses your Mac's architecture; it does not create a universal binary.

## Install the preview download

The **1.0.4 preview is for Apple silicon (arm64), macOS 15 or later**. It is ad-hoc signed and **not notarized**. It does not yet provide the normal installation experience of a Developer ID signed, notarized Mac app. Intel users should build from source; no Intel prebuilt app is provided.

1. Download the [Screenroom 1.0.4 ZIP](https://github.com/SalehMuAm/Screenroom/releases/download/v1.0.4/Screenroom-1.0.4-macos-arm64.zip) and its [SHA-256 checksum](https://github.com/SalehMuAm/Screenroom/releases/download/v1.0.4/Screenroom-1.0.4-macos-arm64.zip.sha256). The [release notes](https://github.com/SalehMuAm/Screenroom/releases/tag/v1.0.4) describe this preview's changes and limitations.
2. Save both files in **Downloads**, keeping their original names. Open Terminal and verify the ZIP against the published checksum:

   ```sh
   cd "$HOME/Downloads"
   shasum -a 256 -c Screenroom-1.0.4-macos-arm64.zip.sha256
   ```

3. Check that verification reports `Screenroom-1.0.4-macos-arm64.zip: OK`. If it fails, do not install that download; download both files again. Expand the ZIP, quit any running Screenroom, and move `Screenroom.app` into **Applications** before opening it.
4. macOS may block the first launch because this preview is not notarized. If you trust this source and verified the download, use the app-specific **Open Anyway** option in **System Settings → Privacy & Security** when available, following [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally. If this route is unavailable, build from source below instead.
5. Follow [Grant capture access](#grant-capture-access), then try your [first screenshot](#first-screenshot) or [first recording](#first-recording). Updating to a different ad-hoc build may require capture permission again.

The checksum checks the downloaded file against the release; it does not substitute for Apple's notarization. For ongoing source development, a stable local Apple Development certificate is recommended.

Manual checks with full-screen apps, Spaces, Stage Manager, and physical keyboard shortcuts remain incomplete for this preview. Try a short capture in your intended setup before an important session.

## Build from source

### 1. Prepare Xcode

Install [Xcode](https://developer.apple.com/xcode/), open it once, and finish its first-launch setup. Check the selected tools in Terminal:

```sh
xcode-select --print-path
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
```

The SDK must be version 15 or later. If the selected tools are older, choose the installed Xcode under **Xcode → Settings → Locations → Command Line Tools**. If Xcode is installed at the standard location, the equivalent command is:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

See Apple's [command-line tools setup](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings) for installations in other locations. A compatible Command Line Tools installation can build the package, but full Xcode also provides the certificate setup described below.

### 2. Clone the source

```sh
git clone https://github.com/SalehMuAm/Screenroom.git
cd Screenroom
```

To make changes in your own repository, start with the [fork workflow](../CONTRIBUTING.md#fork-and-build) instead.

### 3. Choose how to sign your local app

#### Recommended: a stable signing certificate

Use the same certificate for successive builds so macOS can recognize the app when checking capture permissions.

1. Open **Xcode → Settings → Accounts** (called **Apple Accounts** in some versions).
2. Add your Apple Account, select the account/team, and open **Manage Certificates**.
3. Use **+ → Apple Development** to create a development certificate if you do not already have one.
4. Confirm the signing identity is available:

```sh
security find-identity -v -p codesigning
```

See Apple's [signing identity guide](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates) if your account cannot create a certificate or its private key is missing. Keep the private key on your Mac; it does not belong in this repository.

The build script automatically prefers a valid **Developer ID Application** identity, then **Apple Development**. To choose one explicitly, use its exact name or fingerprint from the command above:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (IDENTIFIER)" ./scripts/build-app.sh
```

An Apple Development signature is for local development. It does not notarize the app or provide the normal Gatekeeper experience for public distribution.

#### Temporary option: build without a certificate

For a local trial without setting up a certificate:

```sh
SIGNING_IDENTITY=- ./scripts/build-app.sh
```

This explicitly selects ad-hoc signing. Changed builds can invalidate Screen Recording permission, so you may have to authorize the newly installed app again. Use a stable certificate for ongoing development. The script never silently falls back to ad-hoc signing.

### 4. Build, install, and open

If you have not already built the app in the previous step:

```sh
./scripts/build-app.sh
```

Then quit any running copy of Screenroom and install:

```sh
./scripts/install-app.sh --no-build
open /Applications/Screenroom.app
```

The build produces `dist/Screenroom.app`. The installer verifies it, replaces only an existing Screenroom app at the destination, and registers the installed copy with macOS. It refuses to update a running app, protecting active recordings and unsaved edits. Always launch the installed copy after granting capture permission.

If `/Applications` is not writable by your account, install just for your user:

```sh
SCREENROOM_INSTALL_DIR="$HOME/Applications" ./scripts/install-app.sh --no-build
SCREENROOM_INSTALL_DIR="$HOME/Applications" ./scripts/run.sh --no-build
```

Keep using the same destination for later updates. Do not run the build script with `sudo`.

For subsequent builds, `./scripts/run.sh` builds, installs, and opens the app in one command. `./scripts/run.sh --no-build` only opens the installed copy. Pass `SCREENROOM_INSTALL_DIR` again if using a custom destination. `CONFIGURATION=debug ./scripts/build-app.sh` creates a debug bundle.

<a id="5-grant-capture-access"></a>

## Grant capture access

Start a capture, then follow the macOS permission prompt. In **System Settings → Privacy & Security → Screen & System Audio Recording**, enable the installed Screenroom app. Quit and reopen it if macOS asks. On macOS versions with different wording, look for **Screen Recording**.

Area capture and immediate full-display recording need this access. Window capture uses Apple's content picker. Screenroom never requests microphone access, Accessibility access, or Input Monitoring access.

If permission seems stuck:

1. Stop any recording, save your edits, and quit Screenroom completely; closing its window leaves it running in the menu bar.
2. Check that System Settings lists the installed copy. Use **+** to select `/Applications/Screenroom.app`, or the corresponding app in your user Applications folder.
3. Enable it and reopen that same copy. Avoid launching `dist/Screenroom.app` or the raw `.build` executable for everyday use.
4. If the problem started after rebuilding, check that you used the same certificate. An ad-hoc build or a different signing identity may need fresh authorization.

## First screenshot

1. Open Screenroom. Under **Screenshot**, choose **Area** (the default on a fresh installation).
2. Switch to the browser or other app you want to capture and leave the desired page visible.
3. Press **⌘⇧6**, then drag to select the area. Press **Escape** to cancel the selection.
4. The PNG is saved to `~/Pictures/Screenroom/` and opens in Screenroom for annotation. Export or copy the edited image to preserve any annotations; the original screenshot remains saved.

Screenroom must be running for its global shortcuts to work. Choose **Window** or **Screen** under **Screenshot** for other capture targets. Screenshot and recording targets are remembered separately.

## First recording

1. Open Screenroom and choose **Recording**. It defaults to the entire display under your pointer. Choose **Area** or **Window** if you want a selection step.
2. Turn **System audio** on if you want to capture software audio; it is off on a fresh installation. Microphone audio is never recorded.
3. Switch to the browser or app you want to record. For a full-display recording, place the pointer on the display you want to capture.
4. Press **⌘⇧7** to start, then press it again to stop and save. Wait for saving to finish. The MP4 is saved to `~/Movies/Screenroom/`.

## Update Screenroom

### Downloaded app

1. Check [Releases](https://github.com/SalehMuAm/Screenroom/releases) for a newer version and read its requirements and release notes.
2. Download its ZIP and matching checksum, then verify them using the instructions for that version.
3. Stop any active recording, wait for saving to finish, and export unsaved screenshot annotations. Choose **Screenroom → Quit Screenroom**; closing its window leaves it running in the menu bar.
4. Expand the new ZIP and replace `Screenroom.app` in the same Applications folder used for the previous version. Open that installed copy.
5. Follow [Grant capture access](#grant-capture-access) again if macOS requests permission. Different ad-hoc builds can require fresh authorization.

Replacing the app preserves saved captures and the library index, which live outside the app bundle. Keep using one installation destination to avoid confusing capture permissions between copies.

### Source installation

If your checkout has no local changes, run the following from the repository folder:

```sh
git pull --ff-only
```

Stop recording, export unsaved annotations, and quit Screenroom. Repeat the [build and install steps](#4-build-install-and-open) with the same signing identity and installation destination. Source updates follow the repository branch; to use a packaged release instead, follow the downloaded-app instructions above.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| No software audio | Turn **System audio** on before recording; it is off on a fresh installation. Play audio in the software you are capturing. Window capture follows the selected content filter; full-display capture is a useful diagnostic. Screenroom excludes its own playback audio and always disables the microphone. |
| Preview says “Includes audio,” but playback is silent | That label confirms an audio track exists, not that it contains sound. Check playback volume and verify the source was producing audio while recording. Protected media may not be capturable. |
| Recording stops early | Read the saved recording's interruption message. Free disk space: Screenroom warns below 5 GiB and blocks starts below 1 GiB. macOS can interrupt recording under storage pressure even above that minimum. |
| Shortcut does nothing | Keep Screenroom running, finish any open dialog, and check **Settings** for a shortcut conflict. Another app may already own **⌘⇧6** or **⌘⇧7**. Try the capture button or menu bar command to isolate the problem. |
| Cannot quit or install an update | Stop the active recording and let saving finish. Export unsaved screenshot annotations, then choose **Screenroom → Quit Screenroom** or press **⌘Q**. |
| Compiler cannot find an API | Check that your selected macOS SDK is 15 or later and that the selected Swift compiler is from a compatible Xcode installation. |

## Saved files and uninstalling

Saved files stay on your Mac:

- Screenshots: `~/Pictures/Screenroom/`
- Recordings: `~/Movies/Screenroom/`
- Library index: `~/Library/Application Support/Screenroom/library.json`

Annotations must be exported or copied to preserve the edited image. The original screenshot stays saved. Removing an entry from the library does not delete its media file.

To uninstall, stop recording, save any edits, quit Screenroom, and move the installed app to the Trash. Your saved captures and library index remain in the folders above. If you also want to remove that data, back up any captures you want to keep before deleting `~/Pictures/Screenroom/`, `~/Movies/Screenroom/`, and `~/Library/Application Support/Screenroom/` in Finder. You can also disable Screenroom's capture access in **System Settings → Privacy & Security → Screen & System Audio Recording**.
