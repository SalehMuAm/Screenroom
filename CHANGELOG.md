# Changelog

## 1.0.3 — 2026-10-14

First public preview.

- Native screenshots, screenshot annotations, and MP4 screen recordings.
- Optional software audio; microphone capture remains disabled.
- Full-display recording by default, with separate saved source choices for screenshots and recordings.
- One recording shortcut to start and stop; held-key repeats are ignored.
- Native playback view and explicit AVKit linking to fix the recording-preview crash.
- Recording cleanup handles startup, completion, and system-stop callbacks without stopping the same stream twice.
- Low-storage guidance and clearer messages when macOS interrupts a recording.
- Build and install scripts use one installed app location and support stable signing identities.
- Source setup, contribution instructions, macOS CI, and a preview archive with a SHA-256 checksum.

### Preview limitations

The downloadable app is Apple-silicon-only, ad-hoc signed, and not notarized. Global shortcut delivery has not been fully verified across other applications. Low-storage conditions can still cause macOS to stop a capture. Intel source builds are not runtime-verified. Video editing is not included.
