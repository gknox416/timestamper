# Timestamper

A macOS utility for making verified Broadcast WAV timestamp copies, with a
SwiftUI desktop app and a command-line interface sharing the same processing code.

## Release packaging

The app icon source is in `Artwork/`; the macOS icon sizes are included in the
asset catalog. Build a self-contained universal installer with:

```sh
Scripts/package-macos.sh
```

This produces `Outputs/Releases/0.1.0/`, containing the `.pkg`, app, and SHA-256
checksum. Release folders are never overwritten; set `VERSION` for a new version.
The app supports macOS 14.8 or later on Apple Silicon and Intel. The installer
places it in `/Applications` with no external runtime or downloads.

Without Apple credentials, the app is ad-hoc signed and the installer is unsigned
and unnotarized. For distribution, supply `APP_SIGN_IDENTITY` (Developer ID
Application), `INSTALLER_SIGN_IDENTITY` (Developer ID Installer), and
`NOTARY_PROFILE` (an existing notarytool Keychain profile). The packaging script
then signs, submits, staples, and assesses the installer. No credentials belong
in this repository. See `RELEASE_NOTES.md` for this preview's limitations.

## Desktop app

Open `timestamper.xcodeproj`, select the **Timestamper App** scheme, and Run.
The original **timestamper** scheme remains the command-line tool; `swift test`
runs its shared processing regression tests.

1. Drop files into the Files area or choose **Add Files…** (Command-O).
2. Select the frame rate and enter the target start timecode.
3. Choose a destination folder and click **Create Copies**.
4. Review the verified/failed result for each file. Use **Show in Finder** to
   reveal a successful output.

Current timestamps are interpreted using the selected frame rate. Filename and
source path, sample rate, and sample reference are shown for each input. Invalid
or unsupported files show an error and remain in the batch so failures are
accounted for. Duplicate paths are added only once. Invalid target labels disable
processing; individual file failures do not prevent independent files succeeding.
Reading and writing run on a background queue; settings and file selection stay
locked until the operation completes. Output filenames are preserved exactly.

This first desktop version keeps its queue/settings only while running and has
no cancellation or resume. It is a local development build, not a notarized
release or Mac App Store sandboxed app. Keep it running until processing finishes.

The on-screen checks covered adding the canonical fixture, displaying its
one-hour timestamp, selecting a destination, creating a verified 30-minute copy,
refusing an existing output, and rejecting invalid/drop-frame labels. The GUI
output was independently checked for unchanged audio/unrelated bytes and
synchronized identity/timestamp fields. Finder drag-and-drop still needs a manual
interaction check. All 19 core tests and both Xcode targets build/pass.

## Command-line interface

```sh
swift test
swift run timestamper TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav
mkdir -p Outputs/IdentityTest
swift run timestamper TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav --zero-to Outputs/IdentityTest
swift run timestamper TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav --target 00:30:00:00 --fps 23.976 --output-dir Outputs/IdentityTest
```

CLI and app output filenames are preserved exactly, including extension and case.
The directory must exist. The writer exclusively creates each destination and
never overwrites an existing file, symlink, hard link, or original. Earlier
UUID-suffixed files in `Outputs/` were development experiments; current processing
does not rename outputs.

## Batch processing

```sh
swift run timestamper /path/to/first.wav /path/to/second.wav --target 00:30:00:00 --fps 23.976 --output-dir /path/to/delivery
```

Multiple inputs work for inspection, `--target`, and `--zero-to`. Options may be
interspersed with paths. Use `--` before paths beginning with `--`. One target and
frame rate apply to the batch; each input's own sample rate determines its sample
reference. Files are processed sequentially to bound memory usage.

The batch plans filename collisions before writing. All inputs with conflicting
names (case-insensitive, Unicode-normalized comparison) fail, so input ordering
does not decide which one wins. Existing destination entries, including dangling
symlinks and case-only conflicts, also fail. Resolve collisions by choosing a
different destination or adjusting the input selection; no automatic renaming or
overwriting occurs. Exclusive creation remains in force if a file appears after
planning.

Each file produces a verified success or a failure with its source, destination,
and reason. Failures do not prevent independent inputs from completing. A final
summary counts verified/failed/total files. Exit code is 0 only if all files succeed;
1 means an argument/setup error or at least one file failed. Successful outputs
remain available after partial failures; the batch is not an all-or-nothing
transaction. A write/verification failure can leave an unverified file, as noted
below. Invalid destination directories fail the batch before any output is created.

`BatchProcessor` and its structured per-file results are independent of the CLI,
used by the SwiftUI interface. Batch tests cover mixed sample rates,
unchanged names/audio/sources, distinct identities, duplicate names, existing
files and links, invalid inputs, per-file continuation, and a destination created
after planning.

## Actual app output requirements

- Preserve the input filename exactly, including its extension, in the chosen
  destination directory. Do not append timestamps, UUIDs, counters, or suffixes.
- Create a separate copy; never modify the original or silently overwrite an
  existing destination. Report filename collisions for the user to resolve;
  do not automatically rename outputs to work around collisions.
- Generate a distinct embedded media identity for supported Pro Tools files,
  independently of the filename, so the original and processed copy can coexist
  in a session without a duplicate-identifier warning.

## Pro Tools compatibility work

The initial BEXT-only edit left Pro Tools displaying an hour. The user confirmed
that zeroing the two timestamp fields in `regn` as well gave the correct display.
The diagnostic then triggered a duplicate unique identifier warning. Changing
filenames does not change embedded media identity.

A comparison with the copy restamped by Pro Tools in the user's test session
showed changes in BEXT OriginatorReference, BEXT UMID material identity, and
matching compact identity bytes in `regn` and `umid`. Pro Tools also modified
opaque `minf`/`regn` fields. Those opaque changes are not reproduced by Timestamper.

The writer now recognizes a narrow Pro Tools metadata profile matching these
fixtures. It generates a new random 16-byte material identity per copy, mirrors
its first eight bytes into both compact identity locations, generates a fresh
32-character BEXT OriginatorReference, and updates both `regn` timestamps along
with BEXT TimeReference. It preserves the observed UMID prefix and unused bytes.
This is a compatibility implementation inferred from native before/after files,
not a general implementation of every Pro Tools or SMPTE identity format.
On 2026-09-28, the user confirmed that the new identity test output imported
successfully into Pro Tools without the duplicate-identifier warning and retained
the correct zero timestamp. This validates the tested fixture/profile; broader
Pro Tools layouts still need their own reference files and import checks.

Recognized profile: Pro Tools originator, BEXT v1 with the observed UMID prefix,
a 92-byte single-region `regn` with a short embedded name, a 24-byte compact
`umid`, and 16-byte `minf`. Identity mirrors and all three timestamps must agree.
Unrecognized, missing, duplicate, or inconsistent Pro Tools metadata causes a
failure before writing. Unknown layouts need additional native reference files;
they are never silently processed while retaining a conflicting identity.

Files without a Pro Tools originator or these proprietary chunks retain the
BEXT-only write behavior. Unique media identity handling for other applications
is not yet implemented. Internal region names and other metadata stay unchanged.

## Timecode and frame rates

`--target` requires both `--fps` and `--output-dir`. Rates are `23.976`, `24`,
`25`, `29.97-ndf`, `29.97-df`, and `30`; ambiguous `29.97` is rejected. Read-only
inspection and the legacy `--zero-to` option default to 23.976 unless `--fps` is
specified. The selected rate interprets the timestamp; it does not resample audio
or change session/frame-rate metadata. WAV sample references do not identify
their own frame rate, so select the appropriate rate for the session.

Timecode input is strict `HH:MM:SS:FF`, hours 00–23. DF also accepts
`HH:MM:SS;FF` and always displays a semicolon (quote it in shell commands).
DF skips labels 00 and 01 at each minute except every tenth minute. Boundary
behavior was checked against the rule in
[FFmpeg's timecode implementation](https://ffmpeg.org/doxygen/8.1/timecode_8c_source.html).
The implementation uses rational 24000/1001 and 30000/1001 rates, integer
arithmetic with wide intermediates, and rounds nearest with ties upward.
Fractional frame positions are rounded to whole samples (at most half a sample).
Sample references display at the nearest frame; this display does not alter files.
Out-of-day references are rejected rather than wrapped. Unrepresentable target
labels at unusually low sample rates are rejected before writing.

Tests cover all six rates, every minute of the day at 44.1/48/96 kHz, every frame
label in a ten-minute DF block, rollover boundaries, invalid/skipped labels,
rounding and integer limits. The Pro Tools 23.976 one-hour baseline remains
172972800 samples. Other rates have automated coverage but still need native
Pro Tools reference/import checks before claiming application compatibility.

On 2026-09-28, the user also confirmed that the generated 23.976 output targeting
`00:30:00:00` (86486400 samples) worked in Pro Tools. This validates a nonzero
target in addition to the earlier zero-timestamp and unique-identity checks.

## Verification and limits

`RIFFReader` validates RIFF/WAVE boundaries, chunk padding, a single `fmt ` and
`bext`, nonzero sample rate, and at least one `data` chunk. No BEXT is synthesized.
Undeclared trailing bytes, RF64, and Wave64 are unsupported.

`BWFWriter` patches fixed-width fields in memory. Before writing, it compares all
bytes outside the explicit timestamp/identity ranges with the source. It reopens
the output, checks exact expected bytes and audio contents, and validates identity
and timestamp agreement before reporting success. Audio samples, format, chunk
sizes/order and unrelated metadata remain byte-for-byte unchanged.

A failed write or verification may leave an incomplete or unverified output.
It is reported as a failure and never overwritten automatically. Entire files are
loaded into memory one file at a time.

The canonical fixture remains untouched:

- 48,000 Hz, 24-bit mono; 23.976 TC `01:00:00:00`
- BEXT TimeReference: 172972800
- SHA-256: `b09af898360733a47cd61b86957f238da86408f387c92dafef1e7aafe957014e`

Tests cover exact preservation outside permitted fields, synchronized timestamps
and identities, distinct identities across copies, reprocessing, refusal of
unsupported identity layouts, malformed WAVs, proprietary chunk padding,
64-bit BEXT writes, and overwrite protection including aliases to the source.

The older `Scripts/make_regn_diagnostic.py` is a hash-locked historical experiment.
It intentionally retains the original identity and is not the current writer.
