# Audio Reference Comparison

VoodooTracker X has a local-only diagnostic workflow for comparing two bounded
PCM WAV renders:

- a candidate WAV from VoodooTracker X, a manual capture, or the bounded
  C-backed offline render export helper
- a reference WAV from OpenMPT/libopenmpt/openmpt123, MikMod, or another local
  renderer

This workflow is diagnostic evidence only. It does not prove tracker semantic
correctness, it does not automatically choose fixes, and it must not drive broad
audio rewrites. Use mismatch windows to choose the next smallest targeted PR.

Generated WAVs, JSON reports, Markdown reports, playback traces, screenshots,
logs, and local module files must stay outside git. `_DARKL.XM` is Gregory's
local-only manual regression module at `/Users/syncomm/Desktop/_DARKL.XM`; do
not commit it, copy it into fixtures, or require it from automated tests.

## Current State

Runtime playback still uses `AVAudioPlayerNode` / `AVAudioUnitVarispeed`. The
C-backed mixer remains offline-only and is not connected to the app Play
button.

The bounded offline C-backed path can render tiny adapted `PlaybackSong`
segments in memory, and the local-only `PlaybackSongOfflineRenderer.exportWAV`
helper can write those bounded render blocks as deterministic PCM16 WAV files.
This is not a full module render command and there is no app UI or live playback
integration. The helper is intended for tiny, explicit, bounded local candidate
renders only. Candidate renders now include conservative adapter support for
volume-column set-volume (`0x10...0x50`), set-panning (`0xC0...0xCF`),
row-level volume slides (`0x60...0x9F`), row-level panning slides
(`0xD0...0xEF`), and minimal `Fxx` speed/BPM timing changes, so local
comparisons are more meaningful for simple volume, stereo placement, and
timing-alignment checks in bounded segments.

Current C-backed candidate renders are still expected to differ from
OpenMPT/MikMod for real modules because XM effect-column behavior,
volume-column vibrato/tone-portamento and other unsupported volume-column
semantics, interpolation, full FT2/OpenMPT pitch parity, true Amiga
frequency-table behavior, tempo/BPM semantics beyond minimal bounded `Fxx`, and
full song traversal remain deferred.

MikMod, OpenMPT, `openmpt123`, and libopenmpt are optional local tools. They are
not CI dependencies, and tests for `scripts/audio-compare.py` use temporary
synthetic WAV files only.

## Compare Two WAV Files

Local-only workflow:

1. Produce a bounded VoodooTracker X candidate WAV with
   `PlaybackSongOfflineRenderer.exportWAV(...)`, writing outside the repo, for
   example under `/tmp`.
2. Produce a bounded reference WAV with OpenMPT/libopenmpt/openmpt123, MikMod,
   or another local reference renderer using documented local settings.
3. Run either `scripts/local-reference-compare-smoke.py` or
   `scripts/audio-compare.py` against the candidate and reference WAVs.
4. Inspect the JSON and/or Markdown report as diagnostic evidence, not parity
   proof.

There is no full public module-rendering CLI yet. The practical candidate path
is a small developer-only helper context or focused Swift test/harness code that
builds a `PlaybackSong`, creates a bounded `PlaybackSongOfflineRenderRequest`,
and calls:

```swift
try PlaybackSongOfflineRenderer().exportWAV(request, to: URL(fileURLWithPath: "/tmp/vtx-candidate.wav"))
```

For a local real-module smoke, `PlaybackSongBuilder.build(from:modulePath:)`
can load sample data from a local XM path before the bounded request is created.
Keep the request explicit and small: choose a bounded order/range, sample rate,
channel count, and frame count. This helper does not traverse full songs,
implement effects, or change live playback.

The thin local wrapper validates the existing WAV inputs, writes reports to
`/tmp/vtx-local-reference-comparison` by default, and delegates metric
generation to `scripts/audio-compare.py`:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --label darkl-order-10-smoke \
  --metadata "order 10, bounded local smoke"
```

Explicit report paths are also supported:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --json /tmp/darkl-order-10-audio-compare.json \
  --markdown /tmp/darkl-order-10-audio-compare.md \
  --label darkl-order-10-smoke
```

Local-only example using placeholder paths:

```bash
python3 scripts/audio-compare.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --json /tmp/vtx-audio-compare.json \
  --markdown /tmp/vtx-audio-compare.md
```

Omit `--json` and `--markdown` to print the human-readable Markdown summary to
stdout. The legacy `--report /tmp/report.md` option still writes the same
Markdown summary.

Useful bounds and report options:

```bash
python3 scripts/audio-compare.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --seconds 30 \
  --window-ms 100 \
  --top-windows 5 \
  --json /tmp/vtx-audio-compare.json
```

The script supports uncompressed PCM WAV input. It does not resample, downmix,
upmix, time-align, or compensate for renderer latency.

## Optional Reference Renderers

When `openmpt123` is installed locally, render a bounded reference WAV outside
the repository:

```bash
openmpt123 --render /tmp/openmpt-reference.wav /path/to/local-module.xm
```

MikMod is also acceptable when installed locally:

```bash
mikmod -q -d 2,file=/tmp/mikmod-reference.wav -f 44100 -o 16s /path/to/local-module.xm
```

Renderer settings matter. Record renderer name/version, sample rate,
interpolation mode, ramping/fade behavior, loop handling, gain, and any bounded
duration settings in local notes or PR summaries. Different renderer defaults
can move mismatch windows or change RMS metrics even when both renders are
reasonable.

## Metrics Produced

The JSON and Markdown reports include:

- sample rate, channel count, sample width, frame count, and duration for each
  input
- duration and frame-count deltas
- overall and per-channel RMS
- overall and per-channel peak
- per-channel RMS difference when sample rate and channel count match
- overall RMS difference
- normalized RMS difference against reference RMS when practical
- max absolute sample difference
- clipping sample count
- silence or near-silence sample count and ratio
- stereo balance as left/right RMS and energy difference for stereo files
- normalized correlation over overlapping PCM samples
- first sample-difference timestamp over the configured threshold
- top N worst mismatch windows using non-overlapping windowed RMS difference

JSON output intentionally stores only input basenames, not absolute local paths,
so automation can parse reports without leaking machine-specific locations.

## Interpreting Worst Windows

Worst mismatch windows are ranked by RMS difference over fixed non-overlapping
time ranges. Treat them as leads:

- a short isolated window can point to a note trigger, sample loop, volume
  envelope, panning, or effect decision
- repeated high windows can point to pitch/rate, timing, gain, or stereo
  placement
- a duration or frame-count mismatch can mean the compared bounds differ before
  any sample-level conclusion is useful
- sample-rate or channel-count mismatches skip direct sample comparison and
  should be fixed in local render settings first

Lower numeric difference is not automatically "more correct" tracker behavior.
Use the report alongside playback traces and source-to-synthetic diagnostics to
pick a focused follow-up.

## Local-Only Artifact Rules

Keep all generated files outside the repo, for example under `/tmp`:

- candidate/reference WAV files
- JSON and Markdown comparison reports
- playback trace JSONL files
- screenshots and manual listening notes
- any files derived from `_DARKL.XM`

`_DARKL.XM` may be used on Gregory's machine for local smoke testing,
debugging, listening checks, candidate WAV renders, local reference renders,
and comparison reports. It must not be committed, copied into fixtures,
uploaded, or required by automated tests or CI. Any WAVs, JSON/Markdown reports,
traces, screenshots, logs, or notes derived from it must remain local and out of
git.

The repo `.gitignore` includes local comparison output patterns, but that is a
last line of defense. Before committing, always check `git status --short` and
stage only source, tests, and documentation intended for the PR.

## Manual Verification

For this workflow:

- compare two tiny local WAV files with `scripts/audio-compare.py`
- generate and parse JSON output
- inspect the Markdown summary for format, level, mismatch, and worst-window
  details
- confirm no generated WAVs, reports, traces, screenshots, or local modules are
  staged
- confirm runtime playback behavior did not change
- confirm the C mixer remains offline-only
- confirm tracker viewport and parser architecture code were not modified
