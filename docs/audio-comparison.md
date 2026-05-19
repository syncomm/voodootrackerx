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
button. Offline candidate/reference comparison remains the validation path
before any future feature-flagged runtime C mixer experiment is enabled or
expanded; see ADR 007 for the runtime planning guidance.

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
(`0xD0...0xEF`), minimal `Cxx` set-volume, `8xx` set-panning, nonzero
row-level `Axy` volume slide state updates, minimal `Fxx` speed/BPM timing
changes, minimal nonzero `9xx` sample offsets on same-cell note triggers, and
minimal `1xx`/`2xx` portamento up/down, minimal `3xx` tone portamento, and
minimal `E9x` retriggers for the tracked active adapted voice.
Empty-note volume-column set-volume/set-panning cells and supported
effect-column state commands can update the currently tracked active voice in
bounded offline renders from the update frame forward. Those bounded/offline
gain and pan update events are smoothed by a fixed 32-frame deterministic
micro-ramp in the C mixer, including empty-note volume-column set-volume,
empty-note volume-column set-panning, `Cxx`, `8xx`, and nonzero row-level
`Axy` updates and minimal row-level `Hxy` global volume slides that actually
change an active voice. `ECx` note cuts remain hard cuts. `H00` is diagnosed as
a no-op without effect memory, and both-nibble `Hxy` parameters use the same
safe up-nibble precedence policy as the current runtime effect helper.
Normal note triggers also use
parsed XM instrument note-sample maps/keymaps when a valid bounded offline
mapping exists, with deterministic first-playable fallback or skip diagnostics
when it does not. Local comparisons are therefore more meaningful for simple
volume, stereo placement, timing-alignment, obvious sample-start checks, and
mapped-sample selection in bounded segments. `900` remains a diagnosed no-op
rather than effect memory, and out-of-range `9xx` offsets are reported as
skipped voices. Linear-frequency songs also carry
explicit XM linear-period/frequency/sample-step diagnostics for bounded adapted
events. Fractional C-backed offline sample steps use simple deterministic
linear interpolation; diagnostics JSON reports this as `sample_interpolation`
with value `linear` in the render section. Candidate diagnostics also report
first-pass volume-envelope sustain, loop, note value `97` key-off/release, and
post-key-off fadeout decisions for bounded offline adapted events, including
whether each decision was applied, deferred, or approximated. Non-linear/Amiga-table pitch
behavior remains deferred and is reported as a neutral step fallback.
Diagnostics JSON also includes an event-coverage summary for missing-note
investigations. It compares parsed bounded `PlaybackSong` cells against
scheduled C-backed adapter events, counts normal notes, note-offs, empty and
invalid cells, skipped notes, skip reasons, first-playable-sample fallback
usage, sample-map/keymap selections, fallback-after-invalid-map cases,
skipped-no-valid-sample cases, missing/deferred keymap state, current C mixer
scheduled/active capacity values, accepted scheduled voices, capacity reject
counts, and rejected event coordinates.
The helper also reports export-level headroom and clipping diagnostics for the
Float32 render block before PCM16 conversion. Optional `--gain`,
`--headroom-db`, and `--auto-headroom` controls apply only at the WAV export
boundary, after Float32 offline rendering and before PCM16 encoding. Default
export gain remains unchanged when none of those options is passed.

The helper can also export the bounded adapter diagnostics that already exist in
memory. `scripts/correlate-audio-comparison.py` can combine those diagnostics
with `scripts/audio-compare.py` JSON and produce a local Markdown report that
maps worst mismatch windows to approximate source rows, channels, note/sample
events, pitch steps, linear period/frequency intermediates when present,
volume-column decisions, volume/panning/global-volume state-update diagnostics,
Fxx timing changes, sample-offset decisions, `1xx`/`2xx` portamento-slide
current sample-step diagnostics, `3xx` tone-portamento target/current
sample-step diagnostics, `E9x` retrigger decisions and generated frames,
envelope sustain/loop/key-off/fadeout status, and loop metadata.
When diagnostics JSON contains event coverage, the correlation report includes
a concise event-coverage section with normal note counts, scheduled events,
skipped notes, top skip reasons, and first skipped coordinates.
It also summarizes sample-selection counts so missing or wrong notes can be
separated from fallback-heavy mapped-sample behavior, invalid maps, and current
C mixer capacity limits. When missing notes line up with capacity diagnostics,
check the scheduled capacity, active capacity, rejected count, and rejected
event coordinates before choosing an effect-handling PR.
For long candidate renders, treat `scheduled_voice_capacity` as distinct from
active voice pressure: it can mean the helper scheduled too many future events
into the fixed offline pool up front, even when active mixer capacity is mostly
not the limiting factor. For developer-only long local candidate renders,
`vtx_render_bounded_xm --window-rows N` can now opt into row-windowed offline
scheduling so each window reuses the fixed C scheduled-voice pool instead of
requiring the full range to fit at once. Keep this separate from active voice
pressure and from effect/traversal parity work.
The same report also summarizes applied, ignored/no-op, deferred/unsupported,
and unknown effect-column and volume-column command frequency near the worst
mismatch windows and across the bounded diagnostics data. It includes a
conservative candidate-next-PR ranking so the next audio-correctness change can
be chosen from local evidence without implementing fixes automatically.
Candidate diagnostics and the correlation report also include a focused
pitch-modulation/deferred-effect summary for remaining deferred `0xy`, `4xy`,
`5xy`, `6xy`, `7xy`, and volume-column vibrato/tone-portamento ranges. Applied
`1xx`/`2xx` portamento slides and applied `3xx` tone portamento are reported in
the general command frequency and dedicated portamento diagnostics instead of
the deferred pitch-modulation bucket. The report groups deferred
pitch-modulation counts into arpeggio, remaining portamento-family, vibrato,
and tremolo buckets, shows whether they appear near the worst mismatch windows,
and recommends a conservative next pitch-effect PR only when one bucket
dominates.
For stuck or repeating carried voices, inspect the volume/panning state-update
summary first: it reports empty-note volume-column set-volume/set-panning,
`Cxx`, `8xx`, `Axy`, and `Hxy` applied/deferred/no-op counts, whether an active
voice was updated, effective channel volume/pan and global volume before and
after, global-volume slide direction/amount/clamping, and the source
order/pattern/row/channel plus synthetic frame.
Candidate diagnostics now include a pattern traversal/timing hazard summary for
wrong structure or groove investigations. It counts `Bxx` position jump, `Dxx`
pattern break, `EEx` pattern delay, contextual `Fxx` timing changes, minimal
`E9x` retriggers, and other observed `E` subcommands while keeping `Bxx`,
`Dxx`, and `EEx` diagnostic/deferred only. The correlation report includes
these hazards near worst mismatch windows and can conservatively recommend a
traversal-focused PR when those hazards dominate the local evidence.
This is still diagnostic evidence only; it does not prove correctness or choose
fixes automatically.

Current C-backed candidate renders are still expected to differ from
OpenMPT/MikMod for real modules because XM effect-column behavior,
volume-column vibrato/tone-portamento and other unsupported volume-column
semantics, true Amiga frequency-table behavior, tempo/BPM semantics beyond
minimal bounded `Fxx`, `Gxx` set-global-volume behavior,
tick-accurate volume and pitch-slide behavior, `5xy` tone portamento plus
volume slide, full song traversal, and full reference resampler parity remain
deferred.

MikMod, OpenMPT, `openmpt123`, and libopenmpt are optional local tools. They are
not CI dependencies, and tests for `scripts/audio-compare.py` use temporary
synthetic WAV files only.

`tests/fixtures/minimal.xm` is a tiny redistribution-safe smoke fixture for
parser/helper validation. It is not a meaningful audio-parity fixture for
MikMod/OpenMPT comparison work. Bounded render and effect smoke tests should
use generated or otherwise playable redistribution-safe XM inputs.

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

For local listening where the selected order range ends before a large hard
duration cap, use `--until-song-end` instead. This computes the bounded
selected order-range end from the same adapter timing model used by
`vtx_render_bounded_xm`, including the minimal supported `Fxx` speed/BPM timing
changes. It does not implement full FT2/OpenMPT song duration parity, song
loop/restart behavior, `Bxx`/`Dxx` traversal, or `EEx` pattern delay traversal.
Treat it as a practical bounded adapter duration helper.

`--tail-seconds N` may be used with `--until-song-end` to add a short local
release/listening tail after the calculated bounded range end. When omitted,
the tail defaults to `0` seconds. `--until-song-end` is mutually exclusive with
`--seconds`, `--max-frames`, and `--rows`; `--tail-seconds` is accepted only
with `--until-song-end`. If the calculated song-end plus tail exceeds the
default safety clamp, pass `--allow-long-render` intentionally.

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-song-end-candidate.wav \
  --diagnostics-json /tmp/vtx-song-end-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --until-song-end \
  --tail-seconds 3 \
  --window-rows 64 \
  --auto-headroom \
  --progress
```

Command output and diagnostics JSON report the render duration mode, calculated
song-end frames, tail seconds/frames, effective frame cap, and effective
duration. `--seconds` and `--max-frames` remain hard debug caps for fixed
duration/frame-count renders.

Long candidate WAVs and diagnostics JSON can be large. Write them under `/tmp`
or an ignored scratch directory, and do not commit generated WAVs, JSON reports,
Markdown reports, traces, screenshots, logs, filled local findings, or local
module files.

For longer local renders, add `--progress` to print render percentage by
rendered frame count while the helper runs. When `--window-rows` is used,
progress reports window `i / N`, percentage by rendered frames, and per-window
carried voice, scheduled, accepted, and rejected event counts. The output also
reports loading/build phases, the render duration mode, the effective frame and
duration cap, and the final WAV-writing phase.

## Export Headroom And Clipping Diagnostics

`vtx_render_bounded_xm` writes PCM16 WAV files, so Float32 samples outside the
`-1.0...1.0` range must be clamped during export. Full-scale saturation can
make local candidate renders crackle or mask other offline-render issues. The
helper now reports export-level diagnostics in its command summary and optional
diagnostics JSON:

- effective export gain
- requested export headroom dB when supplied
- pre-export Float32 peak and per-channel peak
- pre-export overrange sample count where `abs(sample) > 1.0`
- pre-export RMS
- post-gain peak and per-channel peak
- post-gain RMS
- auto-headroom enabled flag and fixed safety margin when used
- computed export gain and equivalent computed headroom dB
- PCM16 clipping/clamping sample count after gain
- clipping-detected flag for post-gain PCM16 clipping/clamping and a recommendation
  to rerender with headroom when that count is nonzero

Use `--headroom-db` for a dB-style attenuation or `--gain` for an explicit
linear multiplier. Use `--auto-headroom` when a local developer candidate WAV
should choose its own export gain from the rendered Float32 peak. These options
are mutually exclusive, and all three are applied before PCM16 conversion.
Treat any numeric headroom value in examples as a starting point, not a
guarantee that clipping is eliminated. Inspect the reported pre-export peak
first, then choose attenuation from that peak or rerender with
`--auto-headroom`. The minimum dB value needed to bring the peak to full scale
is approximately `20 * log10(1 / preExportPeak)`; add a safety margin such as
another `1...3` dB. For example, a pre-export peak near `4.0` needs at least
about `-12 dB` before any margin, so `--headroom-db -13`,
`--headroom-db -14`, or an explicit `--gain` around `0.20`, is more
appropriate than a smaller example attenuation.

`--auto-headroom` uses a fixed `-1 dB` safety margin. If the rendered Float32
peak is at or below `1.0`, it keeps export gain at `1.0`. If the peak is above
`1.0`, it computes `gain = (1.0 / peak) * pow(10, -1.0 / 20.0)`, reports the
computed gain and equivalent dB, and applies that gain only before PCM16 WAV
encoding.

Auto-headroom is local/offline candidate-export policy only. It does not change
runtime playback, does not switch the app to the C mixer, does not change C
mixer DSP semantics, and does not affect default output behavior when
`--auto-headroom` is omitted.

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-headroom-candidate.wav \
  --diagnostics-json /tmp/vtx-headroom-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --seconds 240 \
  --allow-long-render \
  --window-rows 64 \
  --headroom-db -6 \
  --progress
```

Equivalent linear-gain form:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-gain-candidate.wav \
  --diagnostics-json /tmp/vtx-gain-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --seconds 240 \
  --allow-long-render \
  --window-rows 64 \
  --gain 0.5
```

Auto-headroom form:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-auto-headroom-candidate.wav \
  --diagnostics-json /tmp/vtx-auto-headroom-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --seconds 240 \
  --allow-long-render \
  --window-rows 64 \
  --auto-headroom \
  --progress
```

This is an export policy only. It does not change internal mixer math, C mixer
DSP semantics, runtime playback, parser behavior, or tracker UI behavior. If
crackle remains after clipping is eliminated or reduced, treat click,
discontinuity, loop-boundary, retrigger, residual gain/pan update, or
effect-timing diagnostics as separate follow-up work.

## Click / Discontinuity Diagnostics

After export headroom eliminates PCM16 clipping but local listening still
reports light crackle or static, inspect the candidate WAV for adjacent-sample
jumps before choosing an audio-fix PR. `scripts/analyze-audio-discontinuities.py`
is a local/offline helper for that purpose:

```bash
python3 scripts/analyze-audio-discontinuities.py \
  --wav /tmp/vtx-candidate.wav \
  --diagnostics-json /tmp/vtx-candidate-diagnostics.json \
  --json /tmp/vtx-clicks.json \
  --markdown /tmp/vtx-clicks.md \
  --top 50 \
  --threshold 12000
```

The diagnostics JSON is optional. Without it, the report still summarizes WAV
format, peak/RMS, PCM16 clipping count when applicable, the largest
adjacent-sample jumps per channel, threshold counts, and jumps per second. With
`vtx_render_bounded_xm` diagnostics JSON, the report also maps top jumps to
nearby local adapter events such as gain/pan state updates, volume-column
updates, note triggers, `E9x` retriggers, `ECx` note cuts, `EDx` note delays,
key-off/release or fadeout events, looped voices when exposed, carried voices,
and row-window boundaries.

Treat the result as diagnostic evidence, not proof. A jump near a gain/pan
update after this micro-ramping pass suggests checking whether the jump
magnitude decreased, whether the update interrupted an active ramp, or whether
another nearby event is the stronger lead. A jump near an `ECx` cut suggests a
separate cut-ramping investigation; a jump near a looped voice or window
boundary suggests loop-boundary or carryover investigation. Use the analyzer
before and after targeted smoothing PRs to compare adjacent-sample jump
magnitudes. Do not use this helper to implement automatic fixes, broad
smoothing, gain changes, or runtime playback changes.

Generated discontinuity JSON/Markdown reports derived from private/local
modules must remain under `/tmp` or another ignored local directory and must not
be committed.

## Windowed Long Candidate Renders

Long local candidate renders may contain far more adapted note events than the
fixed C scheduled-voice pool can hold at once. The pool is intentionally fixed
and deterministic for the offline C mixer path, so the developer helper offers
an explicit row-windowed scheduling mode:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-long-candidate.wav \
  --diagnostics-json /tmp/vtx-long-candidate-diagnostics.json \
  --order 0 \
  --order-count 4 \
  --sample-rate 44100 \
  --seconds 240 \
  --allow-long-render \
  --window-rows 64 \
  --progress
```

Windowed mode is still a developer/offline helper path. It keeps runtime
playback on `AVAudioPlayerNode` / `AVAudioUnitVarispeed`, keeps the C mixer
offline-only, and does not implement new XM effects or change C mixer DSP
semantics. It plans the bounded range through the existing adapter, schedules
only one row window into a fresh C mixer at a time, carries practical active
voice state from earlier windows where the adapter can determine it, renders
that window, appends the PCM, and aggregates diagnostics across windows.
Diagnostics include
`windowed_render_enabled`, `window_rows`, `window_count`, aggregate scheduled,
accepted, and rejected counts, per-window scheduled/accepted/rejected counts,
aggregate/per-window carried voice counts, released/fadeout carryover counts,
boundary continuation counts, boundary drop counts, whether the output may
contain boundary cuts, known unsupported carryover reasons, the first rejecting
windows, and known state-carryover limitations.

Window carryover is intentionally narrow. It is computed from the bounded Swift
adapter plan and reschedules continuation voices into each fresh offline C mixer
window with the current source sample position, forward or ping-pong loop
direction, volume-envelope position, key-on/key-off release state, fadeout
value, gain, and pan. Volume/panning state updates that occurred before a
window boundary are folded into the carried voice state, and updates inside the
window are scheduled at local frames. If a newer note event on the same adapted
channel reaches the boundary, the older voice is not carried into the next
window. This improves long local candidate continuity for sustained one-shot and
looped voices without switching runtime playback or adding broad effect support.

Remaining limitations are still important. Carryover is approximate bounded
offline behavior, not FT2/OpenMPT parity or a generic mixer-state serialization
framework. Unsupported/deferred effects, deferred volume-column semantics,
pattern traversal effects, advanced note cut/delay/retrigger quirks, and other
effect-driven voice state can still make continuity wrong. Boundary drops can
still occur if too many continuation voices need to be rescheduled into one
window. Use the carryover diagnostics and listening notes to decide whether a
later
window-carryover follow-up or a targeted effect PR is warranted.

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
   Read the event-coverage summary first when listening reports suggest missing
   notes. Missing/unknown instruments, empty sample PCM, no-playable-sample
   reasons, sample-map selections, first-playable-sample fallbacks,
   fallback-after-invalid-map cases, skipped-no-valid-sample cases,
   out-of-range `9xx`, C mixer scheduled/active capacity rejections with
   rejected coordinates, and deferred effect interactions should each guide a
   separate targeted follow-up PR.
   When the problem sounds like wrong song structure or groove, inspect the
   pattern traversal/timing hazard section for `Bxx`, `Dxx`, `EEx`, contextual
   `Fxx`, and nearby `E` subcommands before choosing an implementation PR.
6. If clipping is eliminated but crackle/static remains audible, run
   `scripts/analyze-audio-discontinuities.py` on the candidate WAV and optional
   candidate diagnostics JSON. Keep the click/discontinuity reports local.
7. Copy `docs/templates/local-audio-comparison-findings.md` to a local path
   such as
   `/tmp/vtx-local-reference-comparison/local-module-order-10-audio-findings.md`,
   then fill it from the comparison JSON/Markdown, correlation report,
   discontinuity report, trace notes, and local listening notes. Do not commit
   the filled report when it contains private-module-derived findings.
8. Inspect the worst mismatch windows and largest jumps, then classify the likely mismatch category.
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
  --allow-long-render \
  --headroom-db -6
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
  step, linear period/frequency intermediates, sample-selection method and
  mapped-sample validity, volume-column classification, Fxx timing changes,
  sample-offset status, minimal `1xx`/`2xx` portamento-slide diagnostics,
  minimal `3xx` tone-portamento diagnostics, minimal `E9x` retrigger
  diagnostics, minimal `ECx` note-cut diagnostics, minimal `EDx` note-delay
  diagnostics, envelope status, loop mode, and render interpolation status when
  those fields are present
- deferred effect commands in the worst windows, applied effect commands in the
  worst windows, deferred volume-column commands in the worst windows, applied
  volume-column commands in the worst windows, ignored/no-op and unknown command
  counts, and overall bounded command frequency
- pattern traversal/timing hazards near the worst windows, including `Bxx`,
  `Dxx`, `EEx`, contextual `Fxx`, and other observed `E` subcommands when
  diagnostics JSON contains them
- pitch-modulation/deferred-effect counts near the worst windows and overall,
  including arpeggio, remaining deferred portamento-family commands, vibrato,
  tremolo, and deferred volume-column vibrato/tone-portamento commands
- event-coverage totals and skipped-note hotspots when diagnostics JSON
  contains them
- a transparent heuristic recommendation for the next narrow PR, such as
  a minimal arpeggio, portamento, vibrato, or tremolo implementation PR,
  sample-offset
  memory, pattern control effects, mixer headroom diagnostics, or more local
  review when no command clearly dominates

Missing diagnostics fields are reported as unavailable. If no candidate event
overlaps a mismatch window, the report says so explicitly and shows nearby row
or preceding-event context when available.

Use the correlation report to choose the next smallest implementation PR. For
example, if high mismatch windows repeatedly line up with Amiga-table neutral
fallbacks, choose Amiga pitch behavior. If they line up with applied or
deferred effect-column events, choose one specific remaining effect such as
portamento, vibrato, arpeggio, or a focused follow-up to
minimal `E9x`/`ECx`/`EDx`. If mismatch windows repeatedly line up with
diagnosed `900` or `E90` no-ops, decide separately whether effect memory is
worth a narrow PR. If mismatch windows are broad and steady while events look
plausible, remaining resampling details, loop details, headroom/clipping
diagnostics, or reference-render settings may be the better next investigation.
For pitch-modulation diagnostics, prefer the specific pitch bucket that
dominates the top mismatch windows: arpeggio for dense `0xy`, remaining
portamento-family work for `5xy` or volume-column tone portamento, vibrato for
`4xy`/`6xy` or volume-column vibrato, and tremolo for `7xy`. If counts are
sparse or split, record the evidence and do not start an implementation PR from
that signal alone. If windows line up with applied `1xx`/`2xx` or `3xx`, inspect
their current/target step diagnostics before deciding whether a follow-up should
refine portamento or move to another effect family.
If the event-coverage section shows parsed normal notes that never became
scheduled events, prioritize the reported skip reasons and capacity fields
before implementing more effects. In long/full-song renders, separate
`scheduled_voice_capacity` from active capacity symptoms before deciding whether
the next PR should be chunked/windowed scheduling or effect traversal. If sample-map selections remain low for a bounded target, confirm
whether the local module's active instruments actually map those notes to
multiple playable samples before treating it as an adapter bug. Keep capacity
fixes, sample-offset refinements, traversal behavior implementation, and effect
handling as separate targeted follow-up PRs.
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
duration settings in local notes or PR summaries. Also record candidate export
gain/headroom and clipping diagnostics when comparing PCM16 candidate WAVs.
Different renderer defaults can move mismatch windows or change RMS metrics
even when both renders are reasonable.

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
`scripts/analyze-audio-discontinuities.py` separately reports top
adjacent-sample jumps in a single local WAV and follows the same basename-only
reporting rule for its WAV and optional diagnostics JSON inputs.

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
- output headroom / clipping / render gain policy
- click / discontinuity / adjacent-sample jump clustering
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
- JSON and Markdown click/discontinuity reports
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
- analyze a tiny local WAV file with `scripts/analyze-audio-discontinuities.py`
- generate and parse JSON output
- inspect the Markdown summary for format, level, mismatch, and worst-window
  details
- confirm no generated WAVs, reports, traces, screenshots, or local modules are
  staged
- confirm runtime playback behavior did not change
- confirm the C mixer remains offline-only
- confirm tracker viewport and parser architecture code were not modified
- confirm export gain/headroom, when used, was applied before PCM16 conversion
- confirm generated WAVs and diagnostics JSON remain local and unstaged
