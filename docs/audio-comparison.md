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
(`0xD0...0xEF`), minimal `Fxx` speed/BPM timing changes, and minimal nonzero
`9xx` sample offsets on same-cell note triggers, so local comparisons are more
meaningful for simple volume, stereo placement, timing-alignment, and obvious
sample-start checks in bounded segments. `900` remains a diagnosed no-op rather
than effect memory, and out-of-range `9xx` offsets are reported as skipped
voices. Linear-frequency songs also carry
explicit XM linear-period/frequency/sample-step diagnostics for bounded adapted
events. Fractional C-backed offline sample steps use simple deterministic
linear interpolation; diagnostics JSON reports this as `sample_interpolation`
with value `linear` in the render section. Candidate diagnostics also report
first-pass volume-envelope sustain, loop, note value `97` key-off/release, and
post-key-off fadeout decisions for bounded offline adapted events, including
whether each decision was applied, deferred, or approximated. Non-linear/Amiga-table pitch
behavior remains deferred and is reported as a neutral step fallback.

The helper can also export the bounded adapter diagnostics that already exist in
memory. `scripts/correlate-audio-comparison.py` can combine those diagnostics
with `scripts/audio-compare.py` JSON and produce a local Markdown report that
maps worst mismatch windows to approximate source rows, channels, note/sample
events, pitch steps, linear period/frequency intermediates when present,
volume-column decisions, Fxx timing changes, sample-offset decisions, envelope
sustain/loop/key-off/fadeout status, and loop metadata.
The same report also summarizes applied, ignored/no-op, deferred/unsupported,
and unknown effect-column and volume-column command frequency near the worst
mismatch windows and across the bounded diagnostics data. It includes a
conservative candidate-next-PR ranking so the next audio-correctness change can
be chosen from local evidence without implementing fixes automatically.
This is still diagnostic evidence only; it does not prove correctness or choose
fixes automatically.

Current C-backed candidate renders are still expected to differ from
OpenMPT/MikMod for real modules because XM effect-column behavior,
volume-column vibrato/tone-portamento and other unsupported volume-column
semantics, true Amiga frequency-table behavior, tempo/BPM semantics beyond
minimal bounded `Fxx`, full song traversal, and full reference resampler parity
remain deferred.

MikMod, OpenMPT, `openmpt123`, and libopenmpt are optional local tools. They are
not CI dependencies, and tests for `scripts/audio-compare.py` use temporary
synthetic WAV files only.

`tests/fixtures/minimal.xm` is a tiny redistribution-safe smoke fixture for
parser/helper validation. It is not a meaningful audio-parity fixture for
MikMod/OpenMPT comparison work.

## Render Duration Safety

`vtx_render_bounded_xm` is intentionally bounded. By default it keeps the
existing conservative safety clamp of 2,646,000 frames, which is 60 seconds at
44.1 kHz. This protects local comparison work from accidentally writing very
large WAV files.

For longer local listening or comparison renders, choose the duration
explicitly and pass `--allow-long-render` when the requested cap exceeds the
default clamp. Use either `--seconds` or `--max-frames`, not both:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-long-candidate.wav \
  --diagnostics-json /tmp/vtx-long-candidate-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --seconds 240 \
  --allow-long-render
```

Equivalent frame-capped form:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-long-candidate.wav \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --max-frames 10584000 \
  --allow-long-render
```

Long candidate WAVs and diagnostics JSON can be large. Write them under `/tmp`
or an ignored scratch directory, and do not commit generated WAVs, JSON reports,
Markdown reports, traces, screenshots, logs, filled local findings, or local
module files.

For longer local renders, add `--progress` to print render percentage by
rendered frame count while the helper runs. The output also reports
loading/build phases, the effective frame and duration cap, and the final
WAV-writing phase.

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
5. If diagnostics JSON was exported, run
   `scripts/correlate-audio-comparison.py` to map worst mismatch windows to
   nearby bounded adapter rows/events. Keep the correlation report local.
6. Copy `docs/templates/local-audio-comparison-findings.md` to a local path
   such as
   `/tmp/vtx-local-reference-comparison/local-module-order-10-audio-findings.md`,
   then fill it from the comparison JSON/Markdown, correlation report, trace
   notes, and local listening notes. Do not commit the filled report when it contains
   private-module-derived findings.
7. Inspect the worst mismatch windows and classify the likely mismatch category.
   Use that classification to choose one narrow next PR.

The committed template is blank and safe to review. Filled reports, local WAVs,
traces, screenshots, and notes are local evidence only.

## Render a Candidate WAV

Build and run the developer-only helper from the repo root:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-candidate.wav \
  --diagnostics-json /tmp/vtx-candidate-diagnostics.json \
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

Local/private module example with an explicit longer duration:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-local-module-order-10-candidate.wav \
  --diagnostics-json /tmp/vtx-local-module-order-10-candidate-diagnostics.json \
  --order 10 \
  --order-count 2 \
  --sample-rate 44100 \
  --seconds 180 \
  --allow-long-render
```

Local/private XM modules are allowed for local smoke testing on a developer
workstation only. Do not commit, upload, copy them into fixtures, or require
them from automated tests. Candidate WAVs derived from them must stay local and
out of git.

## Correlate Mismatch Windows With Adapter Diagnostics

After generating a comparison JSON and candidate diagnostics JSON, write a
local-only correlation report:

```bash
python3 scripts/correlate-audio-comparison.py \
  --comparison-json /tmp/vtx-audio-compare.json \
  --diagnostics-json /tmp/vtx-candidate-diagnostics.json \
  --output-markdown /tmp/vtx-audio-correlation.md \
  --label local-module-order-10-rows-16 \
  --metadata "order 10, rows 16, 44100 Hz, local reference renderer settings recorded separately"
```

The report is approximate. It maps comparison window start/end times to frame
ranges, then lists:

- row timing diagnostics whose frame ranges overlap each worst mismatch window
- candidate events whose scheduled frame ranges overlap each window
- recent candidate events that precede the window when no event directly overlaps
- source order/pattern/row/channel, note, instrument/sample, gain, pan, pitch
  step, linear period/frequency intermediates, volume-column classification,
  Fxx timing changes, sample-offset status, envelope status, loop mode, and
  render interpolation status when those fields are present
- deferred effect commands in the worst windows, applied effect commands in the
  worst windows, deferred volume-column commands in the worst windows, applied
  volume-column commands in the worst windows, ignored/no-op and unknown command
  counts, and overall bounded command frequency
- a transparent heuristic recommendation for the next narrow PR, such as note
  cut/delay, retrigger, sample-offset memory, pattern control effects, or more
  local review when no command clearly dominates

Missing diagnostics fields are reported as unavailable. If no candidate event
overlaps a mismatch window, the report says so explicitly and shows nearby row
or preceding-event context when available.

Use the correlation report to choose the next smallest implementation PR. For
example, if high mismatch windows repeatedly line up with Amiga-table neutral
fallbacks, choose Amiga pitch behavior. If they line up with deferred
effect-column events, choose one specific remaining effect such as note
cut/delay or retrigger. If mismatch windows repeatedly line up with diagnosed
`900` no-ops, decide separately whether effect memory is worth a narrow PR. If
mismatch windows are broad and steady while events look plausible, remaining
resampling details or reference-render settings may be the better next
investigation.
The recommendation line is a heuristic summary of the bounded diagnostics; it
is not an automatic correctness decision and should be checked against listening
notes, renderer settings, and the actual row/event context before opening the
follow-up implementation PR.

Order 10 and order 30 of a local/private module can be useful exploratory
bounded targets when they expose dense transitions. They remain local-only
debugging inputs. Do not commit the module or any generated WAV, JSON,
Markdown, trace, screenshot, log, or filled findings artifact derived from it.

## Compare Two WAV Files

Local-only workflow:

1. Produce a bounded VoodooTracker X candidate WAV with
   `swift run vtx_render_bounded_xm`, optionally with `--diagnostics-json`,
   writing outside the repo, for example under `/tmp`.
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

MikMod is also acceptable when installed locally, but do not use its default
playlist mode with the WAV disk writer. On MikMod 3.2.9 the default playlist
mode can repeat a single module into the same WAV indefinitely, creating
multi-GB files. Use one-pass playlist mode and disable user config when making
local references:

```bash
mikmod -norc -q --playmode 0 --noloops \
  -d 2,file=/tmp/mikmod-reference.wav \
  -f 44100 \
  -o 16s \
  /path/to/local-module.xm
```

Renderer settings matter. Record renderer name/version, sample rate,
interpolation mode, ramping/fade behavior, loop handling, gain, and any bounded
duration settings in local notes or PR summaries. Different renderer defaults
can move mismatch windows or change RMS metrics even when both renders are
reasonable.

For agents: never start a MikMod disk-writer render that can grow without a
clear stop condition. Monitor the file size and process status while it runs.
If `--playmode 0` is not accepted by the installed MikMod, use another local
reference renderer or an explicit time/size-capped wrapper. A one-pass 44.1 kHz
stereo PCM16 render of a roughly 3:25 module is about 35 MB; growth into GBs is
a sign that the module or playlist is repeating and the process should be
stopped before it can fill the disk.

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
Use the report alongside playback traces, source-to-synthetic diagnostics, and
the correlation report to pick a focused follow-up.

Likely categories to consider when filling the findings template:

- timing / `Fxx` / row duration
- order traversal / pattern break / position jump
- panning / volume-column behavior
- volume slides / envelope / fadeout / key-off
- pitch / finetune / relative note / linear frequency
- remaining resampling / reference-render settings
- sample offset / retrigger / note cut / note delay
- loop behavior
- unknown / needs trace correlation

Pick one narrow next PR from the evidence. Good candidates include adapter
support for a specific effect, Amiga pitch behavior if non-linear modules need
it, additional diagnostics, additional volume-column semantics, a remaining
resampling or loop investigation, or a bounded order traversal improvement.
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
