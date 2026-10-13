# Screenroom

A lightweight, native macOS screen recorder and screenshot editor built with SwiftUI, AppKit, and ScreenCaptureKit. No web runtime, third-party dependencies, audio drivers, accounts, or uploads.

## Requirements

- macOS 15 or later.
- Xcode 16 or later, or a compatible Swift 5.10+ toolchain and macOS 15+ SDK, to build from source.
- Screen Recording permission, granted by you when you first capture.

## Build and run

```sh
./scripts/build-app.sh
./scripts/run.sh --no-build
```

The build creates `dist/Screenroom.app` for your Mac’s architecture. You can also run `./scripts/run.sh` to build and launch in one step. Drag the app into Applications if desired. The app bundle is self-contained; Xcode is needed to build it, not to use it.

The default signature is ad-hoc for local development. To sign with an installed Developer ID certificate instead:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

Signing does not notarize the app. Distributing it to other Macs requires your own Developer ID and Apple notarization for a normal Gatekeeper experience. Rebuilding an ad-hoc signed app can cause macOS to ask for capture permission again; keeping one installed copy at a stable path helps avoid confusing duplicate entries.

## Capture and edit

- Capture an area, a window, or a display as a PNG screenshot.
- Record an area, window, or display to an MP4 video. Choose 30 or 60 fps.
- Turn **System audio** on to include sound produced by the captured software. It is off by default. Microphone capture stays off, so external conversation and room sounds are never requested or recorded.
- Annotate screenshots with freehand drawing, arrows, rectangles, ellipses, and text. Use undo/redo, then copy or export the result.
- Open an existing image to annotate it, browse recent captures in the library, or preview a recorded video.
- Use the menu bar controls for a quick screenshot or to stop recording.
- Global shortcuts: **⇧⌘6** takes a screenshot, and **⇧⌘7** starts or stops a recording. If another app owns either shortcut, Screenroom reports this in Settings.

When you first capture, allow Screenroom in **System Settings → Privacy & Security → Screen & System Audio Recording** (the name can vary slightly by macOS version). Follow the system prompt to reopen the app if required. Window capture limits the recording to your selected window; system audio follows ScreenCaptureKit’s selected content filter. Some protected media cannot be captured.

Screenshot annotations are for still images; video trimming and annotation are not included.

Closing the main window keeps Screenroom in the menu bar. A red recording icon and Stop & Save control are available there while recording. Screenroom protects unsaved screenshot annotations when changing views, starting another capture, opening an image, or quitting.

## Local files

- Screenshots: `~/Pictures/Screenroom/`
- Recordings: `~/Movies/Screenroom/`
- Capture index: `~/Library/Application Support/Screenroom/library.json`

Media stays on your Mac. Exporting or copying an edited screenshot does not upload it anywhere.

## Development

```sh
swift build
swift test
```

Use the `.app` bundle to test permissions and normal launch behavior. The build scripts place compiler caches under `.build/`, generate all native icon resolutions with AppKit, and validate the finished bundle’s code signature. `CONFIGURATION=debug ./scripts/build-app.sh` creates a debug app bundle.

Screenroom uses Apple’s [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/) for capture, its [system audio option](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio) for software audio, and explicitly disables [microphone capture](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone). Image editing uses native AppKit drawing.
