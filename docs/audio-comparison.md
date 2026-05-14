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

Generated WAVs, JSON reports, Markdown reports, filled findings reports,
playback traces, screenshots, logs, listening notes, and local module files
must stay outside git. Local/private XM modules may be used on a developer
workstation for manual smoke testing, listening checks, candidate WAV renders,
and local comparisons, but do not commit them, upload them, copy them into
fixtures, or require them from automated tests.

## Current State

Runtime playback still uses `AVAudioPlayerNode` / `AVAudioUnitVarispeed`. The
C-backed mixer remains offline-only and is not connected to the app Play
button.

The bounded offline C-backed path can render tiny adapted `PlaybackSong`
segments in memory, and the local-only `PlaybackSongOfflineRenderer.exportWAV`
helper can write those bounded render blocks as deterministic PCM16 WAV files.
The developer-only `vtx_render_bounded_xm` helper now provides a durable local
command for building an XM through the existing metadata loader and
`PlaybackSongBuilder`, then calling `PlaybackSongOfflineRenderer.exportWAV(...)`.
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

`tests/fixtures/minimal.xm` is a tiny redistribution-safe smoke fixture for
parser/helper validation. It is not a meaningful audio-parity fixture for
MikMod/OpenMPT comparison work.

## Local Bounded Findings Workflow

Use this workflow when turning a local bounded comparison into the first useful
mismatch report for a follow-up implementation PR. The goal is diagnosis, not an
automatic fix.

1. Choose a small bounded target before rendering. Useful local targets include
   order 10 and order 30, but the exact order, row range, duration, sample rate,
   and channel count must be recorded in the local report.
2. If a local/private XM module exists on the developer workstation, render a
   bounded candidate WAV with `swift run vtx_render_bounded_xm`, which loads the
   XM through `ModuleMetadataLoader`, `PlaybackSongBuilder`, and
   `PlaybackSongOfflineRenderer.exportWAV`. Write the WAV under `/tmp` or
   another ignored local output directory.
3. Render a matching bounded reference WAV with a local reference renderer such
   as OpenMPT/libopenmpt/`openmpt123` or MikMod. Match sample rate, channels,
   duration, gain, interpolation, and compatibility settings as closely as the
   tool allows, and record the renderer version/settings.
4. Run `scripts/local-reference-compare-smoke.py` or
   `scripts/audio-compare.py` on the existing candidate/reference WAVs. Keep
   JSON and Markdown reports local.
5. Copy `docs/templates/local-audio-comparison-findings.md` to a local path
   such as
   `/tmp/vtx-local-reference-comparison/local-module-order-10-audio-findings.md`,
   then fill it from the comparison JSON/Markdown, trace notes, and local
   listening notes. Do not commit the filled report when it contains
   private-module-derived findings.
6. Inspect the worst mismatch windows and classify the likely mismatch category.
   Use that classification to choose one narrow next PR.

The committed template is blank and safe to review. Filled reports, local WAVs,
traces, screenshots, and notes are local evidence only.

## Render a Candidate WAV

Build and run the developer-only helper from the repo root:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-module.xm \
  --output /tmp/vtx-candidate.wav \
  --order 10 \
  --order-count 1 \
  --rows 16 \
  --sample-rate 44100
```

The command validates that the input exists, refuses ordinary tracked repo
output paths, prints render details, and writes a local PCM16 WAV through the
existing bounded offline C-backed export path. It does not bypass
`CSoftwareMixer`, duplicate parser logic, implement full song traversal, change
mixer DSP behavior, or affect runtime playback.

Local/private module example:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-module.xm \
  --output /tmp/vtx-local-module-order-10-candidate.wav \
  --order 10 \
  --rows 16 \
  --sample-rate 44100
```

Local/private XM modules are allowed for local smoke testing on a developer
workstation only. Do not commit, upload, copy them into fixtures, or require
them from automated tests. Candidate WAVs derived from them must stay local and
out of git.

## Compare Two WAV Files

Local-only workflow:

1. Produce a bounded VoodooTracker X candidate WAV with
   `swift run vtx_render_bounded_xm`, writing outside the repo, for example
   under `/tmp`.
2. Produce a bounded reference WAV with OpenMPT/libopenmpt/openmpt123, MikMod,
   or another local reference renderer using documented local settings.
3. Run either `scripts/local-reference-compare-smoke.py` or
   `scripts/audio-compare.py` against the candidate and reference WAVs.
4. Inspect the JSON and/or Markdown report as diagnostic evidence, not parity
   proof.

The thin local wrapper validates the existing WAV inputs, writes reports to
`/tmp/vtx-local-reference-comparison` by default, and delegates metric
generation to `scripts/audio-compare.py`:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --label local-module-order-10-smoke \
  --metadata "order 10, bounded local smoke"
```

Explicit report paths are also supported:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/openmpt-reference.wav \
  --json /tmp/local-module-order-10-audio-compare.json \
  --markdown /tmp/local-module-order-10-audio-compare.md \
  --label local-module-order-10-smoke
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

Reference renderer bounding may need workarounds. MikMod and some OpenMPT CLI
flows may not support exact order/row-bounded rendering from the command line,
so record any manual trimming, duration-only bounds, silence padding, or offset
workaround in the findings report. Comparison output is diagnostic evidence,
not a correctness oracle.

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

Likely categories to consider when filling the findings template:

- timing / `Fxx` / row duration
- order traversal / pattern break / position jump
- panning / volume-column behavior
- volume slides / envelope / fadeout / key-off
- pitch / finetune / relative note / linear frequency
- interpolation / resampling
- sample offset / retrigger / note cut / note delay
- loop behavior
- unknown / needs trace correlation

Pick one narrow next PR from the evidence. Good candidates include adapter
support for a specific effect, a focused pitch/period accuracy pass, a local
trace-to-comparison correlation report, additional volume-column semantics, a
loop/interpolation investigation, or a bounded order traversal improvement.
Feature-flagged runtime C mixer backend work should wait until offline
confidence is strong enough to justify runtime risk.

## Local-Only Artifact Rules

Keep all generated files outside the repo, for example under `/tmp`:

- candidate/reference WAV files
- JSON and Markdown comparison reports
- playback trace JSONL files
- screenshots and manual listening notes
- any files derived from local/private XM modules

Local/private XM modules may be used on a developer workstation for local smoke
testing, debugging, listening checks, candidate WAV renders, local reference
renders, and comparison reports. They must not be committed, copied into
fixtures, uploaded, or required by automated tests or CI. Any WAVs,
JSON/Markdown reports, traces, screenshots, logs, or notes derived from them
must remain local and out of git.

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
