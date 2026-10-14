# Changelog

## 1.0.4 — 2026-10-14

- Keep capture selection over the active app and return focus before screenshots and recordings started from Screenroom.
- Handle cancellation and failed focus restoration before recording starts.
- Keep an open screenshot editor and its unsaved annotations when a recording finishes.
- Preserve unsaved-change tracking when reopening the same image.
- Back up unreadable library indexes before replacing them; leave the original intact if backup fails.
- Validate build/run options before taking action, and support `--help` without installing anything.
- Reject release output inside the app even through case or symlink aliases on macOS.
- Add regression coverage for editor preservation, library recovery, and release scripts.

### Preview limitations

The downloadable app requires macOS 15 or later and is Apple-silicon-only, ad-hoc signed, and not notarized. Manual checks with full-screen apps, Spaces, Stage Manager, and physical keyboard shortcuts remain incomplete. Intel source builds are not runtime-verified.

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
