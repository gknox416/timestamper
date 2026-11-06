# Timestamper 0.1.0 — development preview

A macOS utility for creating verified Broadcast WAV copies with a new start timestamp.

- Drag-and-drop or select multiple Broadcast WAV files.
- Set target timecode and choose 23.976, 24, 25, 29.97 NDF/DF, or 30 fps.
- Preserve output filenames, audio samples, and unrelated file bytes.
- Synchronize timestamps and generate fresh identities for the supported Pro Tools metadata layout.
- Refuse filename collisions and verify each written copy before reporting success.

## Installer

`Timestamper-0.1.0-universal-unsigned.pkg` contains the complete app for Apple Silicon
and Intel Macs running macOS 14.8 or later. It installs into `/Applications` and
requires no Python, Swift toolchain, source checkout, or extra downloads to run.
The package has no installer scripts. It replaces an existing app at that location.

This is an **unsigned, unnotarized development preview**, not a Gatekeeper-ready
public distribution. Downloaded copies may be blocked by macOS. Do not disable
system security. Building from source is available; a future distribution release
requires Developer ID signing and Apple notarization.

## Known limits

- Pro Tools support currently recognizes one narrow metadata layout. Other layouts fail before writing.
- Native Pro Tools tests cover the supplied 23.976 fixture; other rates have automated conversion tests.
- Classic RIFF/WAVE only; no RF64/Wave64, new BEXT creation, cancellation, or resume.
- Files are loaded into memory one at a time.
- A write/verification failure can leave an incomplete or unverified output.
- Finder drag-and-drop needs broader manual testing.
