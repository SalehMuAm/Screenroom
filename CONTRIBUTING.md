# Contributing to Screenroom

Bug reports, focused fixes, documentation improvements, and accessibility improvements are welcome. For a substantial feature or architectural change, open an issue first to explain the problem and proposed behavior.

## Fork and build

1. Fork [SalehMuAm/Screenroom](https://github.com/SalehMuAm/Screenroom) on GitHub.
2. Clone your fork, replacing `YOUR_USERNAME` below:

```sh
git clone https://github.com/YOUR_USERNAME/Screenroom.git
cd Screenroom
git remote add upstream https://github.com/SalehMuAm/Screenroom.git
git switch -c fix/describe-the-change
```

3. Follow [SETUP.md](docs/SETUP.md) for Xcode, signing, and installation. Use macOS 15 or later with a macOS 15+ SDK. No third-party dependencies are needed.
4. Make and validate your change, then push your branch:

```sh
git push -u origin fix/describe-the-change
```

5. Open a pull request against upstream `main`. Explain the problem, resulting behavior, and what you tested. Include before/after images for visible changes when useful, with private screen content removed.

To update an unchanged local `main` from upstream:

```sh
git fetch upstream
git switch main
git merge --ff-only upstream/main
```

If you have your own commits on `main`, reconcile them deliberately rather than discarding them. Use your own signing identity for local builds; signing keys and Apple account credentials must never be committed.

## Project map

| File or folder | Responsibility |
| --- | --- |
| `Sources/Screenroom/ScreenroomApp.swift` | App entry point, window lifecycle, menus, and menu bar controls. |
| `Sources/Screenroom/AppModel.swift` | Coordinates capture, editing, library navigation, and persisted user options. |
| `Sources/Screenroom/CaptureService.swift` | ScreenCaptureKit selection, screenshots, system audio, recording, and delegate callbacks. |
| `Sources/Screenroom/RecordingStreamLifecycle.swift` | Recording start/stop state and interruption handling. |
| `Sources/Screenroom/ScreenCapturePermission.swift` | Capture authorization policy. |
| `Sources/Screenroom/CaptureSourcePreferences.swift` | Separate screenshot and recording target preferences. |
| `Sources/Screenroom/RecordingStorage.swift` | Available-space checks and recording warnings. |
| `Sources/Screenroom/CaptureGeometry.swift` | Coordinate conversion and output dimensions. |
| `Sources/Screenroom/AnnotationEditor.swift` | Native screenshot canvas, annotations, undo/redo, and export. |
| `Sources/Screenroom/CaptureLibrary.swift` | Media destinations and the local capture index. |
| `Sources/Screenroom/LibraryView.swift` | Capture browsing, thumbnails, and native video playback. |
| `Sources/Screenroom/HotKeyManager.swift` | Global shortcuts and key-repeat suppression. |
| `Sources/Screenroom/CapturePanel.swift`, `WorkspaceView.swift` | Capture controls, workspace layout, and settings. |
| `Tests/ScreenroomTests/` | XCTest coverage of logic that can run without interactive capture permissions. |
| `Resources/`, `scripts/` | Bundle metadata, native icon generation, building, signing, and installation. |

Screenroom is a Swift package written in Swift 5 language mode. The UI uses SwiftUI and AppKit. ScreenCaptureKit captures media, `SCRecordingOutput` writes MP4 files, and AVKit plays them. Keep media processing native and avoid adding a dependency for functionality the platform already supplies.

## Validate your change

Run the relevant automated tests from the repository root:

```sh
swift build
swift test
```

For a release configuration check:

```sh
swift test --configuration release
```

These checks do not establish that macOS permissions, global shortcuts, audio capture, or video playback work. Test those through the installed `.app` bundle when your change affects them. Running `swift run` or the executable under `.build` does not reproduce the normal installed-app identity and permission flow.

Build a bundle with your usual signing identity, quit the running app, and install it:

```sh
./scripts/build-app.sh
./scripts/install-app.sh --no-build
./scripts/run.sh --no-build
```

Use the temporary `SIGNING_IDENTITY=-` option from [SETUP.md](docs/SETUP.md#temporary-option-build-without-a-certificate) only when needed; a changed ad-hoc build may require capture permission again.

For capture or lifecycle changes, check the affected flows manually:

- Start a full-display recording with **⌘⇧7**, let it run beyond a few seconds, then stop with the same physical shortcut. Confirm the saved duration, framing, and playback. Also try the capture button and menu bar controls.
- Record with **System audio** on while another app plays sound, and listen to the saved file. Repeat with it off. The preview's audio-track label alone does not prove audible audio was captured.
- Select Area and Window; test cancellation, permission denial, and repeated start/stop without a crash or a leftover recording session.
- For screenshot/editor changes, draw and move annotations, undo/redo, copy/export, and verify the unsaved-edit prompts protect your work.
- If recording is interrupted, verify the app reports the reason and keeps any finalized file. Do not fill your disk deliberately to simulate low storage; test the storage policy with unit tests.

State which macOS version, Mac architecture, signing method, and manual flows you checked in the pull request. Be explicit about anything you could not test. Use test content that does not expose private windows, notifications, or conversations.

## Reporting a bug

Use the [issue tracker](https://github.com/SalehMuAm/Screenroom/issues). Include:

- Screenroom version, macOS version, and Apple silicon or Intel Mac.
- Whether you downloaded a release or built from source; for source builds, include the commit and signing method.
- Exact reproduction steps, capture target, System audio setting, and expected/actual behavior.
- The complete error message and available disk space if recording stops early.
- A relevant crash report excerpt if the app crashes, with personal paths and captured content redacted.

Do not upload recordings containing private information or full system logs without reviewing them first. A small reproduction with synthetic content is usually more useful.

## Change guidelines

Keep changes focused. Preserve the separation between screenshot and recording preferences, explicit system-audio opt-in, disabled microphone capture, and protection for unsaved annotations. Add targeted tests for changed state transitions or calculations. UI-only changes generally need a manual check rather than tests that mirror implementation details.

Do not commit `.build/`, `dist/`, recordings, developer certificates, provisioning profiles, or account credentials. Installation scripts must continue to preserve active recordings and avoid changing the user's privacy grants automatically.
