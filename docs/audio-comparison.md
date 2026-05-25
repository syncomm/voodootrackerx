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

For local private XM corpus scans, use a stable local-only JSON label map
outside the repository. Reuse existing `xm-corpus-###` labels when the map is
present, append labels for newly discovered XM files, and never renumber
existing labels. Keep the map out of git and fixtures because it may contain
private filenames or paths. Public reports should use anonymized labels only;
local-only notes for the maintainer may refer back to the private mapping.

## Current State

Default runtime playback uses the CoreAudio DefaultOutput Audio Unit C mixer
backend. `VTX_AUDIO_BACKEND=c_mixer` and
`VTX_AUDIO_BACKEND=c_mixer_coreaudio` remain accepted aliases for the same
CoreAudio host. `VTX_AUDIO_BACKEND=av_audio` is a retired legacy value and now
falls back to the CoreAudio C mixer with a diagnostic fallback reason. The
retired AVAudioSourceNode-hosted C mixer backend is no longer selectable.
Offline candidate/reference comparison remains the authoritative render
validation path.

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
tick-level `Axy` volume slide updates after tick 0, minimal `Fxx` speed/BPM
timing changes, minimal `9xx` sample offsets on same-cell note triggers including
per-channel `900` memory replay, minimal `0xy` arpeggio, minimal `1xx`/`2xx`
portamento up/down, minimal `3xx` tone portamento, minimal `E1x` fine
portamento up, minimal `E2x` fine portamento down, minimal `EAx`/`EBx` fine
volume slides, minimal `4xy` vibrato, minimal `6xy` vibrato + volume slide, and
`E9x` retriggers for the tracked active adapted voice. The
`1xx`/`2xx` foundation replays per-channel `100`/`200` memory from the prior
nonzero same-family slide amount when available; unavailable memory remains a
diagnosed effect-memory-deferred no-op. The `E1x` foundation applies one
deterministic row-level linear-period/sample-step
pitch-up adjustment; `E10` remains an effect-memory-deferred no-op. The `E2x`
foundation applies one deterministic row-level linear-period/sample-step
pitch-down adjustment; `E20` remains an effect-memory-deferred no-op. The
`4xy` foundation uses
deterministic sine-based linear-period sample-step updates on row ticks in the
shared runtime/offline C mixer adapter path; `400` and single-zero nibbles
reuse available per-channel speed/depth memory, while unavailable memory,
volume-column vibrato, and vibrato waveform controls remain deferred. The
`6xy` foundation reuses prior channel vibrato memory and its existing row-level
volume-slide/gain path; `600` can replay vibrato memory without volume-slide
memory, while unavailable vibrato memory remains an effect-memory-deferred
no-op.
The `EAx`/`EBx` foundation applies one deterministic row-level channel-volume
change through the shared gain-update path, clamps to the XM `0...64` channel
volume range, and leaves `EA0`/`EB0` as effect-memory-deferred no-ops.
Empty-note volume-column set-volume/set-panning cells, same-cell valid-note
`3xx` tone-portamento cells that suppress retriggering, and supported
effect-column state commands can update the currently tracked active voice in
bounded offline renders from the update frame forward. Those bounded/offline
gain and pan update events are smoothed by a fixed 32-frame deterministic
micro-ramp in the C mixer, including empty-note and same-cell `3xx`
no-retrigger volume-column set-volume/set-panning, `Cxx`, `8xx`, and nonzero
tick-level `Axy` updates, minimal row-level `EAx`/`EBx` fine volume slides,
minimal `6xy` volume-slide gain updates, and minimal row-level `Hxy` global
volume slides that actually change an active voice.
`ECx` note cuts remain hard cuts. `H00` is diagnosed as a no-op without effect
memory, and both-nibble `Hxy` parameters use the same safe up-nibble precedence
policy as the current runtime effect helper.
Normal note triggers also use
parsed XM instrument note-sample maps/keymaps when a valid bounded offline
mapping exists, with deterministic first-playable fallback or skip diagnostics
when it does not. Local comparisons are therefore more meaningful for simple
volume, stereo placement, timing-alignment, obvious sample-start checks, and
mapped-sample selection in bounded segments. `900` remains a diagnosed no-op
when no prior same-channel nonzero `9xx` memory exists, and out-of-range `9xx`
offsets are reported as skipped voices. Linear-frequency songs also carry
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
Diagnostics JSON also reports `vibrato_effects` plus render counters such as
`vibrato_4xy_effect_count`, applied/no-active/effect-memory-deferred buckets,
`vibrato_4xy_memory_applied_count`, `vibrato_4xy_memory_missing_count`, and
scheduled sample-step update counts for first-pass `4xy` coverage.
`vibrato_volume_slide_6xy_effects` and render-level
`vibrato_volume_slide_6xy_*` counters report detected, applied,
no-active-voice, missing-memory deferred, memory-applied/missing counts,
scheduled sample-step updates, and scheduled gain-update counts for first-pass
`6xy` coverage. Sample-offset diagnostics include
`effect_memory_reused`, `effect_memory_missing`, memory source/target metadata,
and `900_sample_offset_memory_applied` for `900` replays.
`portamento_slide_effects` and render-level `portamento_1xx_*`,
`portamento_2xx_*`, and `portamento_memory_missing_count` counters report
detected/applied/no-active/missing-memory `1xx`/`2xx` coverage, per-channel
`100`/`200` memory reuse, memory source/target metadata, and scheduled
sample-step update counts.
`fine_portamento_up_effects` / `fine_portamento_down_effects` and render-level
`e1x_fine_portamento_up_*` / `e2x_fine_portamento_down_*` counters report
detected/applied/no-active/effect-memory-deferred `E1x` and `E2x` coverage, the
fine amount nibble, current period/sample-step before/after, and scheduled
sample-step update counts where a row-level update is emitted.
Render-level `eax_fine_volume_slide_up_*` and
`ebx_fine_volume_slide_down_*` counters report detected, applied,
no-active-voice, zero-amount/effect-memory-deferred, and scheduled gain-update
counts; the generic `volume_panning_state_updates` entries include the fine
amount nibble plus channel volume and gain before/after.
For narrow channel investigations, `scripts/focused-xm-channel-diagnostics.py`
can combine a local `mc_dump --json --pattern N` artifact with a bounded render
diagnostics JSON artifact. Its schema 3 output includes per-row decoded cell
data, trigger/replacement and same-cell `3xx` suppress-retrigger flags, channel
volume/gain before and after tick 0, nonzero tick carry-forward state, active
voice gain-update scheduling, effective gain sent to the C mixer, and
zero/near-zero gain rows. Same-cell `3xx` detail rows also report sample
position reset, instrument/sample state before/after, instrument default-volume
restoration, envelope-reset modeling status, tone target/sample-step before and
after, expected audible onset, and whether the C mixer received a new voice or
only gain/step state updates. Keep those focused reports under `/tmp` or
another untracked local path.
The helper also reports export-level headroom and clipping diagnostics for the
Float32 render block before PCM16 conversion. Optional `--gain`,
`--headroom-db`, and `--auto-headroom` controls apply only at the WAV export
boundary, after Float32 offline rendering and before PCM16 encoding. Default
export gain remains unchanged when none of those options is passed.

## Runtime C Mixer Listening Diagnostics

Runtime playback now defaults to the CoreAudio DefaultOutput Audio Unit C mixer
host. `VTX_AUDIO_BACKEND=c_mixer` and
`VTX_AUDIO_BACKEND=c_mixer_coreaudio` explicitly select the same CoreAudio host.
`VTX_AUDIO_BACKEND=av_audio` is retired and falls back to the same CoreAudio
default with `fallbackReason=retired_backend`. Unknown backend values fall back
to the CoreAudio default with `fallbackReason=unknown_backend`.

For local listening diagnostics, build the app first:

```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Launch with the default CoreAudio C mixer backend:

```bash
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Launch with the explicit CoreAudio-hosted runtime C mixer backend:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Launch with the explicit CoreAudio compatibility alias:

```bash
VTX_AUDIO_BACKEND=c_mixer_coreaudio \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Verify the retired legacy `av_audio` value falls back to the CoreAudio C mixer:

```bash
VTX_AUDIO_BACKEND=av_audio \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

When a runtime C mixer backend is selected, the C mixer chooses
its runtime render sample rate from the output graph/device where practical.
The selected rate is used for the C mixer render config, CoreAudio host format,
runtime capture, planned adapter event frames, and sample-time position
resolution. For local diagnostics only, developers can force the runtime C
mixer rate with `VTX_C_MIXER_RUNTIME_SAMPLE_RATE=48000`.

Enable a local-only runtime C mixer JSONL trace:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Use no `VTX_AUDIO_BACKEND` value to verify the default CoreAudio path, or use
`VTX_AUDIO_BACKEND=c_mixer_coreaudio` with the same trace controls to verify the
compatibility alias. Trace rows and summaries report `runtimeAudioBackend`,
`backendFlagValue`, `fallbackReason`, summary `selection_mode`,
`runtimeOutputHostType`, output-unit prepare/initialize/start/stop `OSStatus`
values, and the last nonzero host status when one is observed. For the default CoreAudio path,
`backendFlagValue` is absent and `runtimeAudioBackend` is `c_mixer`; for the
retired `av_audio` value, `backendFlagValue` is `av_audio`,
`runtimeAudioBackend` is `c_mixer`, and `fallbackReason` is `retired_backend`.

For controlled alias smoke testing, run the same local/private module from the
same start position with both accepted backend names:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-primary-trace.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-primary-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_DEBUG_STOP_AFTER_SECONDS=240 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX

VTX_AUDIO_BACKEND=c_mixer_coreaudio \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-alias-trace.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-alias-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_DEBUG_STOP_AFTER_SECONDS=240 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Summarize each trace with the same command and compare requested backend flag,
host type, sample rate, channel count, callback counts, callback frame count
range, underrun/zero-fill/failed render counters, callback duration warnings,
near-budget warnings, callback lock attempts/try-lock failures, stale-output
fallbacks, skipped-audio and skipped-diagnostics counters, lifecycle-overlap
counters, capture duration/clipping, route/sample-rate diagnostics, and
CoreAudio output-unit `OSStatus` values:

```bash
python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-primary-trace.jsonl \
  --live-artifact-reported unknown \
  --json /tmp/vtx-c-primary-summary.json \
  --markdown /tmp/vtx-c-primary-summary.md

python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-alias-trace.jsonl \
  --live-artifact-reported unknown \
  --json /tmp/vtx-c-alias-summary.json \
  --markdown /tmp/vtx-c-alias-summary.md
```

The summary also separates capture lifetime from playback lifetime. It reports
`runtimeCaptureSeconds`, `debugStopAfterSeconds`, planned song-end frame/time,
runtime tail seconds/frames, song-end stop frame/time, capture end frame/time,
runtime stop frame/time, event-queue exhaustion frame/time, active/loaded
voices at planned song end and tail stop, whether output continued after
planned song end, whether capture cap or debug stop triggered the stop, and
whether planned song end plus tail triggered stop or silence.
`VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS` is a capture-buffer cap only; it must not
be used as the playback lifetime. A shorter capture cap truncates only the
local capture, and a longer cap does not extend playback. Runtime C mixer
playback stops or silences at planned song end plus the runtime tail, which
defaults to 3 seconds and can be overridden locally with
`VTX_C_MIXER_RUNTIME_TAIL_SECONDS=N`. `VTX_DEBUG_STOP_AFTER_SECONDS` may stop
playback during local automation. Both `c_mixer` and `c_mixer_coreaudio` remain
accepted backend names for the same CoreAudio host, and `av_audio` remains
accepted only as a retired value that falls back to that host;
generated traces, captures, WAVs, JSON reports, Markdown summaries, logs,
screenshots, and listening notes should stay local and unstaged.

For overhead isolation, `VTX_C_MIXER_RUNTIME_DISABLE_TRACE=1` disables the
runtime C mixer trace writer when a C mixer backend is selected.

For live-only pop isolation, run the same CoreAudio C mixer smoke against a
small output-route matrix. Use safe route labels such as `built-in`,
`bluetooth`, or `usb-interface`; do not use local device names, machine names,
or full hardware identifiers in docs or committed notes. Local traces may
contain the hashed output-device UID and the safe route label under `/tmp`.

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_ROUTE_LABEL=built-in \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-route-built-in.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-route-built-in-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_DEBUG_STOP_AFTER_SECONDS=240 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Repeat with another available route, for example:

- built-in speakers or wired output, if available
- AirPods/Bluetooth, if that is where artifacts are heard
- USB or interface output, if available

After each run, summarize the trace and record the manual listening result
locally:

```bash
python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-route-built-in.jsonl \
  --live-artifact-reported unknown \
  --json /tmp/vtx-c-route-built-in-summary.json \
  --markdown /tmp/vtx-c-route-built-in-summary.md
```

Use `--live-artifact-reported yes` only when the current route produced an
audible live artifact during that run; use `no` when the run was listened to
and no artifact was heard. Keep the trace, capture, summary, listening notes,
and any files derived from local/private modules outside git.

Enable a local-only runtime C mixer live output capture when the actual
post-gain PCM handed to the runtime host needs to be compared with the clean
offline C mixer render:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-capture-trace.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-runtime-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_DEBUG_STOP_AFTER_SECONDS=240 \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Capture is ignored unless a C mixer backend is selected and
`VTX_C_MIXER_RUNTIME_CAPTURE_PATH` is set. The captured WAV is a diagnostic
PCM16 file written from an in-memory Float32 capture buffer outside the audio
callback when playback stops or the backend resets. The callback captures the
same already-gained interleaved scratch frames that are handed to the selected
CoreAudio DefaultOutput Audio Unit host for both `c_mixer` and
`c_mixer_coreaudio`. It does not perform file I/O, call AppKit, or write the
WAV. Capture reports and WAV headers use the selected runtime C mixer sample
rate. The default capture limit is 240 seconds.
`VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS` can lower the cap, and larger values are
clamped to the same local-debug safety limit. If the cap is reached, capture
stops and the runtime trace reports truncation.

`VTX_C_MIXER_RUNTIME_DISABLE_CAPTURE=1` disables capture even if a capture path
is present. `VTX_C_MIXER_RUNTIME_MINIMAL_CALLBACK=1` disables trace and capture
and keeps only minimal callback/output-delivery diagnostics for the C mixer
backend. `VTX_C_MIXER_RUNTIME_DISABLE_FOLLOW_PUBLICATION=1` suppresses C-mixer
tracker-follow publication for local callback/UI isolation without changing
offline rendering.
`VTX_C_MIXER_RUNTIME_VERIFY_OUTPUT_COPY=1` enables the optional
scratch/capture/output hash verifier for short local diagnostics; it is off by
default so normal callback diagnostics use fixed-capacity ring
buffers, fixed top peak/jump slots, and counters instead of growing diagnostic
collections. The CoreAudio callback records render/copy/timing counters through
one non-blocking render-core entry in the normal path. Follow-position and
row-transition trace breadcrumbs published while the host is running use the
callback-published sample-time frame instead of taking a render-core snapshot,
so long-run UI/follow diagnostics do not add render-lock pressure. If the
diagnostic ring fills, the trace summary reports `callbackDiagnosticDropCount`
and continues without allocating more callback storage. A useful local isolation matrix is:
trace plus capture with normal follow publication, trace/capture disabled with
follow publication disabled, trace only, capture only, both disabled, minimal
callback mode, and a short output-copy-verifier run when needed. Generated
traces, captures, reports, logs, screenshots, and listening notes remain
local-only.

To compare the runtime capture against an offline C mixer render, first render a
clean local candidate WAV under `/tmp`:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-offline-c-mixer.wav \
  --diagnostics-json /tmp/vtx-offline-c-mixer-diagnostics.json \
  --until-song-end \
  --tail-seconds 3 \
  --window-rows 64 \
  --auto-headroom \
  --allow-long-render
```

Then analyze the captured WAV and compare aligned ranges:

```bash
python3 scripts/analyze-audio-discontinuities.py \
  --wav /tmp/vtx-c-runtime-capture.wav \
  --json /tmp/vtx-c-runtime-capture-discontinuities.json \
  --markdown /tmp/vtx-c-runtime-capture-discontinuities.md

python3 scripts/audio-compare.py \
  --reference /tmp/vtx-offline-c-mixer.wav \
  --candidate /tmp/vtx-c-runtime-capture.wav \
  --seconds 240 \
  --json /tmp/vtx-runtime-vs-offline-audio-compare.json \
  --markdown /tmp/vtx-runtime-vs-offline-audio-compare.md
```

For remaining subtle runtime/offline differences, compare the full or
near-full capture first, then correlate specific mismatch windows with the
runtime trace and optional offline diagnostics JSON:

```bash
python3 scripts/correlate-runtime-offline-window.py \
  --runtime-wav /tmp/vtx-c-runtime-capture.wav \
  --offline-wav /tmp/vtx-offline-c-mixer.wav \
  --runtime-trace /tmp/vtx-c-runtime-capture-trace.jsonl \
  --offline-diagnostics-json /tmp/vtx-offline-c-mixer-diagnostics.json \
  --comparison-json /tmp/vtx-runtime-vs-offline-audio-compare.json \
  --comparison-window-limit 8 \
  --window 181.2:181.7 \
  --window 188.5:188.7 \
  --alignment-search-frames 1024 \
  --json /tmp/vtx-runtime-offline-window-correlation.json \
  --markdown /tmp/vtx-runtime-offline-window-correlation.md
```

The correlation helper reports runtime/offline peak and RMS, normalized
correlation, RMS difference, max absolute difference, best local runtime
alignment shift, scalar gain normalization evidence, nearby runtime trace event
categories, same-frame bursts, sustained voice association fields, active and
loaded voice ranges, cleanup/ramp evidence, optional offline diagnostics counts,
and a conservative next-PR recommendation. It is a local diagnostic report
only. It does not alter runtime output, offline rendering, mixer DSP, gain,
timing, parser behavior, tracker UI, or XM effect support.

Use `scripts/summarize-runtime-c-mixer-trace.py` on the JSONL trace to recap
capture enablement, basename-only output path, sample rate, channel count,
captured frames/duration, truncation, runtime sample-rate policy, runtime
gain/headroom policy, callback timing, callback thread/main-thread isolation,
event queue producer/consumer threads, playback-follow publication counts,
output buffer copy verification, scratch/capture/output hash checks,
CoreAudio output-host fields, hardware IO/latency fields, route and
configuration-change counts, output route labels, hashed device identity,
transport type labels, output peak/RMS, and
overrange/clipping counters. The summary also includes a
`clean_source_dirty_live` conclusion with runtime-capture cleanliness,
output-copy-verifier cleanliness, the manual live-artifact note, route/device
candidate status, and callback candidate status.
Keep all WAVs, PCM-derived reports, JSONL traces, logs, and listening notes
outside git. Public docs and tests must continue to use placeholder module
paths only.

ADR 008 records the runtime-host decision to retire the AVAudioSourceNode C
mixer path after persistent live-output artifacts and use the CoreAudio
DefaultOutput Audio Unit host as the C mixer delivery surface.
AVAudioPlayerNode/AVAudioUnitVarispeed has since been retired after serving
first audible playback.

The runtime C mixer applies a conservative output gain at the runtime handoff
before samples are copied to the selected live host buffers.
The default policy is `default_runtime_headroom_db`, currently `-12 dB`, which
keeps runtime playback away from heavy unity-gain clipping seen in local
diagnostic traces. This does not affect `vtx_render_bounded_xm` offline renders.

For local C-mixer-only smoke runs, override the runtime policy with exactly one
of these variables:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_GAIN=0.5 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_HEADROOM_DB=-9 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

`VTX_C_MIXER_RUNTIME_GAIN` accepts finite values greater than `0` and at most `1`.
`VTX_C_MIXER_RUNTIME_HEADROOM_DB` accepts finite `0` or negative dB values and
converts them to linear gain. If both variables are set, or either value is
invalid, the runtime C mixer falls back to the default conservative policy and
reports `runtimeGainConfigurationWarning` in the trace. Runtime trace rows also
report the active gain policy label, fixed headroom dB, default `-12 dB`
headroom, and whether the gain came from an environment override. These
variables apply to the CoreAudio C mixer path, including the retired `av_audio`
fallback.

The live runtime path keeps a simple fixed headroom policy. It does not
implement offline-style auto-headroom. Matching the `vtx_render_bounded_xm`
`--auto-headroom` policy for runtime playback would require a future
pre-playback preflight or dry-render peak-analysis pass from the selected start
position, or equivalent lookahead, without adding dynamic limiting.

For local epsilon/delta guard diagnostics, Debug builds also accept
`VTX_C_MIXER_RUNTIME_UPDATE_EPSILON` when a C mixer backend is selected.
The default remains `1e-5`; use `0` only for local/synthetic comparison runs to
see whether tiny gain/pan/sample-step changes move from `suppressed_epsilon` to
applied trace rows. Trace rows report the active `runtimeUpdateEpsilon` and
policy. This is diagnostic-only and does not affect offline WAV export.

When comparing a specific start point, use the existing debug launch controls:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl \
VTX_PLAYBACK_TRACE_PATH=/tmp/vtx-playback-trace.jsonl \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_DEBUG_START_ROW=0 \
VTX_DEBUG_STOP_AFTER_SECONDS=45 \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Use `VTX_AUDIO_BACKEND=c_mixer_coreaudio` in the same command to verify the
same CoreAudio host through the compatibility alias at the same start point.

The runtime C mixer trace records backend selection, PlaybackEngine
order/pattern/row/tick/channel context, note trigger and key-off events, C mixer
add-voice calls, applied and deferred runtime gain/pan/sample-step update calls,
channel-scoped voice stops, replacement stop ramps, true global clear/stop
calls, C call success/failure when available, voices stopped or ramped counts
when available, active/loaded voice counts before and after stop, ramp, or
update actions when available, and approximate C mixer render cursor/frame
counters.
This makes it possible to check whether note events continue after an audible
drop, whether the C backend continues receiving events, and whether an
unexpected all-voice clear/stop coincides with the dropout. Immediate channel
stops in the runtime C mixer path emit `c_mixer_stop_channel`.
Same-channel note replacement now emits `c_mixer_stop_channel_ramped`, reports
`rampedVoiceCount`, `replacementRampFrames` (`32`), and
`replacementVoicesOverlap`, and lets the new replacement voice start while the
old voice fades out briefly. Dense burst diagnostics also report the outgoing
voice id/tag, old gain/pan/sample-step/key/fadeout state, replacement ramp
start/target state, new voice id/tag when known, and booleans such as
`replacementGainPanAppliedBeforeRamp` and `replacementStepAppliedBeforeRamp`.
The summary helper counts those fields so local captures can distinguish
replacement ramps whose outgoing voice already reflected final same-frame state
from ramps that started with older C-side state. True transport stop/reset
actions still emit `c_mixer_clear_all` and target all channels.
Runtime C mixer traces also include local-only output-host and route diagnostics:
selected runtime sample rate, runtime sample-rate policy (`graph_aligned`,
`explicit_env`, or `fallback_44100`), selected backend, host type, CoreAudio
output-unit `OSStatus` breadcrumbs, C mixer render sample rate/channel count,
default output device nominal sample rate, hardware buffer frame size/duration
when accessible, `audioFormatConversionLikely`, and whether capture format
matches the hardware sample rate.
Callback timing fields report requested frame ranges, min/max/average callback
duration, conservative duration warning counts, estimated render quantum
duration, callbacks over the render quantum budget, and callback-to-callback
interval ranges. Output-copy verification fields report buffer layout,
requested/copied frames and samples, channel-count matches, partial-copy
evidence, and scratch/capture/output hash comparisons.
Supported runtime updates emit `c_mixer_update_gain_pan_applied`,
`c_mixer_update_step_applied`, or
`c_mixer_update_gain_pan_step_applied` when the handoff can target and change
the current channel voice. No-change refreshes are suppressed as
`c_mixer_update_suppressed_no_change` rather than treated as unsupported.
Gain/pan updates with no active voice may be retained as
`c_mixer_update_stored_channel_state` so a later note can use the latest channel
gain/pan state without inventing playback. Step/pitch updates without an active
sample/note target remain deferred as `c_mixer_update_deferred_no_active_voice`
or, when target data is incomplete, `c_mixer_update_deferred_missing_data`.
Updates after a channel stop are reported separately as
`c_mixer_update_deferred_stale_after_stop`, and invalid values remain
`c_mixer_update_deferred_unsupported`.

Runtime update rows include `updateDisposition`, `updateType`, source
order/pattern/row/tick/channel context when available, target voice index when
available, gain/pan/sample-step before/after values when available, and
active/loaded voice snapshots. The common dispositions are `update_applied`,
`update_suppressed_no_change`, `update_stored_channel_state`,
`update_deferred_no_active_voice`, `update_deferred_stale_after_stop`,
`update_deferred_missing_data`, and `update_deferred_unsupported`. Runtime C
mixer updates are filtered with a `1e-5` epsilon for gain, pan, and sample-step
deltas before C mixer events are scheduled. Per-field deltas at or below the
epsilon are reported with statuses such as `suppressed_epsilon`, combined
updates apply only fields above the threshold, and all-fields-below-epsilon
refreshes remain `update_suppressed_no_change` so gain/pan ramps are not
restarted by tiny discrepancies. Trace rows may include `updateEpsilon`,
`gainRequested`, `panRequested`, `sampleStepRequested`, `gainDelta`, `panDelta`,
`sampleStepDelta`, `gainUpdateStatus`, `panUpdateStatus`, and
`sampleStepUpdateStatus`. Gain/pan updates keep the runtime C mixer's fixed
micro-ramp and the runtime headroom policy still applies only at the CoreAudio
runtime host handoff.

The same trace carries runtime output diagnostics for the CoreAudio C mixer
path: backend sample rate and channel count, render callback count,
requested frame counts, cumulative requested/rendered frames, min/max/last
callback sizes, successful/failed render counts, detected zero-fill and underrun
counts, silent-output counts, callback duration/interval/budget counters,
output buffer fill/copy/hash verification, post-gain output peak/RMS summaries,
post-gain overrange/clipping counts, `clippingDetected`,
`runtimeClippingRecommendation` when clipping remains, runtime output gain,
configured runtime headroom dB when applicable, runtime gain policy labels,
active/loaded voice snapshots, row-transition breadcrumbs, backend lifecycle
breadcrumbs, and cumulative event counters for note triggers, C mixer
add-voice calls, gain/pan update attempts, sample-step update attempts,
epsilon-suppressed gain/pan/sample-step fields, no-change suppressions,
updates applied after epsilon filtering, channel-scoped stops, and clear-all
calls. Runtime traces report `eventQueueBacklogCount` as the number of planned
adapter events still queued for their render callback frame when the runtime
plan is active.
This is intended to show whether a harsh transition lines up with a clear-all,
many channel stops, a burst of new note triggers or control updates, a
voice-count collapse/spike, zero-fill/underrun evidence, remaining clipping
after runtime gain, a backend reset, or epsilon-suppressed updates near the same
runtime frame.

The runtime C mixer trace now keeps lower-threshold transient evidence as well:
cumulative adjacent same-channel jump counts for `0.25`, `0.35`, `0.50`, and
the existing high threshold, bounded top adjacent jumps, top output peaks above
`0.95`, and peak/clip locations above `1.0`. Replacement ramp cleanup snapshots
include ramp start/completion counts, voices still ramping out, and any abrupt
removal of a voice while its ramp was active.

Runtime C mixer traces also include sample-time event-application breadcrumbs
for the runtime backend. Planned offline-adapter events are queued by intended
runtime frame and applied inside the selected runtime host callback by splitting
the render at the in-buffer event offset. Trace rows may report the host
callback index and frame range, cumulative runtime rendered frames, the
offline-adapter planned source order/pattern/row/tick/channel, the planned
absolute frame, the planned frame adjusted to the runtime start offset, the
event applied frame, the in-callback offset, the planned-vs-applied delta, the
same-frame burst size, and exact-frame/callback-boundary/late counters.
Row-entry diagnostics include before/after transition breadcrumbs with
previous/next order-row context, active/loaded voice counts, replacement ramp
deltas, and update deltas. These fields are for diagnosing remaining
runtime-only clicks or stumbles; they do not make the C mixer the default,
alter offline rendering, or implement new XM effects.

The same local-only runtime trace can now resolve the C mixer sample-time frame
cursor back to the planned adapter order/pattern/row/tick timeline and compare
that with the `PlaybackEngine` order/pattern/row/tick context recorded at the
same trace point. Fields such as `cMixerRenderedFrames`,
`cMixerPlaybackSeconds`, `cMixerSampleTimeFrame`,
`cMixerSampleTimeOrderIndex`, `cMixerSampleTimeRowIndex`,
`cMixerSampleTimeTickInRow`, `playbackEngineToCMixerFrameDelta`, and
`playbackEngineToCMixerPositionMismatch` separate sample-time
position/reporting drift from real runtime playback timing problems. The
comparison fields do not change tracker viewport behavior, Stop behavior,
keyboard shortcuts, audio event timing, or offline renders.

The runtime C mixer publishes tracker-follow position from the C mixer
sample-time resolver when its planned adapter timeline is available.
The trace records this as `publishedPlaybackFollowPositionSource` with
`c_mixer_sample_time`, alongside the still-traced `PlaybackEngine` timer
position. The legacy AVAudio fallback has been retired. There is no user-facing
backend toggle.

Use the summary helper to distinguish exact planned event application from
position/reporting drift. It reports PlaybackEngine-vs-C-mixer frame and
millisecond deltas from row-transition breadcrumbs, the first divergence above
the summary threshold, whether the evidence looks like accumulating drift or a
mostly constant offset, and selected order-transition samples. Transport
stop/reset cursor jumps and exact in-callback event timestamps that appear
after callback-end breadcrumbs are reported separately from in-playback drift.
It also reports published-follow-vs-C-mixer deltas so local traces can show
whether the position sent to tracker follow is aligned even when the main-run-loop
timer position has drifted. These diagnostics do not modify tracker viewport
behavior.

Offline candidate WAV export gain/headroom remains separate from runtime
playback. The offline helper can use `--gain`, `--headroom-db`, or
`--auto-headroom` at the WAV export boundary. The runtime C mixer uses its own
fixed runtime gain policy and does not run offline
`--auto-headroom` during live playback. This does not change C mixer DSP
semantics or runtime backend selection.

Runtime traces, playback traces, logs, screenshots, WAVs, JSON reports, and
notes derived from private/local modules must remain under `/tmp` or another
ignored local path. Do not commit, upload, copy into fixtures, or require any
private/local module or derived artifact from automated tests.

Summarize a runtime C mixer JSONL trace with:

```bash
python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-runtime-trace.jsonl \
  --json /tmp/vtx-c-runtime-summary.json \
  --markdown /tmp/vtx-c-runtime-summary.md
```

The summary is diagnostic-only. It reports peak/clipping/underrun/zero-fill
and failed-render counters, add-voice counts, ramped replacement stops,
immediate hard channel stops, normal-playback clear-all evidence, active and
loaded voice ranges, applied gain/pan and step updates, suppressed no-change
updates, epsilon-suppressed field counts and motion assessment, stored
channel-state updates, remaining deferred update categories, lower-threshold
discontinuity counts, top jumps, top peaks, same-row/tick event bursts, largest
planned-vs-applied frame deltas,
exact-frame and callback-boundary application counts, late planned events,
same-frame event bursts, max/average/median row-transition deltas,
PlaybackEngine-vs-C-mixer position frame/millisecond delta statistics,
constant-offset versus accumulating-drift classification,
PlaybackEngine-vs-C-mixer sample-time position mismatches, transport/reset
cursor jumps, in-callback timestamp ordering cases, unexpected backward cursor
movement, order/row ranges where mismatch is largest, selected order-transition
position samples,
order/row transition bursts, and top suspicious order/row/tick positions.
Same-frame burst summaries include burst IDs, event ordinals, affected
channels, event categories, active/loaded voice counts before and after,
ramp-down starts/completions, new voices, sustained carried voices, and
order-start/row-transition flags. Sustained-voice transition summaries report
order-start update cells, retained or lost channel associations,
update-without-note applications, and missed or stored update events. It also
calls out whether observed same-channel note
replacements used
`c_mixer_stop_channel_ramped` or fell back to immediate `c_mixer_stop_channel`
hard stops.

The summary includes a runtime-vs-offline-adapter category checklist for
gain/pan state updates, step/pitch updates, `Hxy` global-volume updates,
`ECx`/`EDx`/`E9x`, and `1xx`/`2xx`/`3xx` portamento updates. Runtime C mixer
trace rows now also report whether events came from the precomputed
`offline_adapter_plan`, the simpler `playback_engine_simple` fallback, or a
`hybrid` path. Inspect `adapterPlanGenerated`, `adapterPlanGenerationMS`,
`plannedEventCount`, `consumedPlannedEventCount`,
`skippedUnmatchedPlannedEventCount`, `adapterEventCategoriesConsumed`, and
`runtimeEventFallbackReason` before choosing the next runtime stabilization
step. Remaining gaps after a healthy
adapter plan should be treated separately from C mixer DSP, runtime headroom,
parser changes, tracker UI, and tracker-follow/sample-time position work.
For the runtime C mixer render queue, same-frame planned events use the
same frame-boundary ordering as the offline C mixer path: gain/pan and
sample-step voice-state updates, then note cuts, then note triggers. This does
not add new XM effects.

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
For a broader local audit that is not tied to audio mismatch windows, use
`scripts/summarize-xm-effect-coverage.py` directly on one or more
`vtx_render_bounded_xm --diagnostics-json` files. The effect coverage summary
reports detected, applied, deferred, unsupported, and no-op/effect-memory
counts by command, source coordinates for the first examples, effect-family
counts, unresolved key-off/no-active buckets, and a conservative next-effect
recommendation. It is local diagnostics only; generated JSON/Markdown reports
derived from private modules must stay under `/tmp` or another ignored path.
Candidate diagnostics and the correlation report also include a focused
pitch-modulation/deferred-effect summary for remaining deferred `5xy`, `7xy`,
and volume-column vibrato/tone-portamento ranges. Applied `0xy` arpeggio,
applied `1xx`/`2xx` portamento slides, applied `3xx` tone portamento, applied
`E1x` fine portamento up, applied `E2x` fine portamento down, applied
`EAx`/`EBx` fine volume slides, and applied `4xy`/`6xy` vibrato-family effects
are reported in the general command frequency and dedicated diagnostics instead
of the deferred pitch-modulation bucket. The report groups remaining deferred
pitch-modulation counts into portamento-family, vibrato, and tremolo buckets,
shows whether they appear near the worst mismatch windows, and recommends a
conservative next pitch-effect PR only when one bucket dominates.
For stuck or repeating carried voices, inspect the volume/panning state-update
summary first: it reports empty-note volume-column set-volume/set-panning,
`Cxx`, `8xx`, `Axy`, `EAx`/`EBx`, and `Hxy` applied/deferred/no-op counts,
whether an active voice was updated, effective channel volume/pan and global
volume before and after, `Axy` tick-level update counts, tick-0 suppression,
mixed-nibble policy, scheduled gain-update counts, fine slide amount,
global-volume slide direction/amount/clamping, and the source
order/pattern/row/channel plus synthetic tick/frame.
Candidate diagnostics now include a pattern traversal/timing hazard summary for
wrong structure or groove investigations. It counts `Bxx` position jump, `Dxx`
pattern break, `E6x` pattern loop, `EEx` pattern delay, contextual `Fxx`
timing changes, minimal `E9x` retriggers, and other observed `E` subcommands.
The bounded/offline and CoreAudio C mixer adapter paths now apply a focused
first-pass traversal model for `Dxx`, `Bxx`, and `E6x`: `Dxx` uses XM-style BCD
row targets, same-row `Bxx` + `Dxx` jumps to the `Bxx` order using the `Dxx`
row target, and `E6x` uses per-channel order/pattern loop markers while missing
`E60` starts are diagnosed without inventing a loop. `EEx` pattern delay and
broader FT2/OpenMPT traversal quirks remain deferred.
This is still diagnostic evidence only; it does not prove correctness or choose
fixes automatically.

For runtime live-output captures versus offline C mixer WAVs, prefer
`scripts/correlate-runtime-offline-window.py`. It consumes the full-song
`scripts/audio-compare.py` JSON worst windows plus any explicit `--window`
values, then maps those windows to runtime JSONL trace rows and optional offline
diagnostics JSON. This keeps full-song evidence visible while still producing
small, readable window-level reports for follow-up runtime decisions.

Current C-backed candidate renders are still expected to differ from
OpenMPT/MikMod for real modules because XM effect-column behavior,
volume-column vibrato/tone-portamento and other unsupported volume-column
semantics, true Amiga frequency-table behavior, tempo/BPM semantics beyond
minimal bounded `Fxx`, `Gxx` set-global-volume behavior,
tick-accurate volume and pitch-slide behavior, `5xy` tone portamento plus
volume slide, full FT2/OpenMPT traversal parity, and full reference resampler
parity remain deferred.

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
changes and focused `Dxx`/`Bxx`/`E6x` traversal. It does not implement full
FT2/OpenMPT song duration parity, song loop/restart behavior, or `EEx` pattern
delay traversal.
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

The runtime C mixer has its own fixed runtime headroom policy
(`-12 dB` by default) and explicit environment overrides. That runtime policy is
separate from offline export `--auto-headroom`; exact runtime auto-headroom
would be a future preflight/dry-render analysis feature, not part of this simple
fixed-headroom smoke path.

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

Windowed mode is still a developer/offline helper path. It does not change
runtime backend selection and does not implement new XM effects or change C
mixer DSP semantics. It plans the bounded range through the existing adapter, schedules
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
   pattern traversal/timing section for focused `Bxx`, `Dxx`, `E6x`, deferred
   `EEx`, contextual `Fxx`, and nearby `E` subcommands before choosing an
   implementation PR.
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
`CSoftwareMixer`, duplicate parser logic, implement full FT2/OpenMPT traversal
parity, change mixer DSP behavior, or affect runtime playback.

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
  including remaining deferred portamento-family commands, vibrato, tremolo,
  and deferred volume-column vibrato/tone-portamento commands; applied `0xy`
  arpeggio appears in applied command frequency and `arpeggio_effects`
  diagnostics instead
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

## Summarize XM Effect Coverage

After a bounded, windowed, or full-song local diagnostics pass, summarize effect
coverage without comparing audio:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-effect-coverage-candidate.wav \
  --diagnostics-json /tmp/vtx-effect-coverage-diagnostics.json \
  --order 0 \
  --order-count 16 \
  --sample-rate 44100 \
  --seconds 60 \
  --window-rows 64

python3 scripts/summarize-xm-effect-coverage.py \
  /tmp/vtx-effect-coverage-diagnostics.json \
  --json /tmp/vtx-effect-coverage-summary.json \
  --markdown /tmp/vtx-effect-coverage-summary.md
```

For a local-only corpus pass, pass multiple diagnostics JSON files to the same
summary command. The Markdown table includes command, source column, offline or
runtime category, detected/applied/deferred/unsupported/no-op counts, first
coordinates, and recommended implementation priority. Use the recommendation as
triage evidence only; implementation PRs still need synthetic tests and must not
depend on private modules.

When anonymizing a private XM corpus for local reports, preserve
`/tmp/vtx-private-xm-corpus-label-map.json` as the stable local-only label map.
If it exists, reuse its `xm-corpus-###` labels; if new local modules are
discovered later, append new labels without renumbering existing ones. Keep the
map under `/tmp`, do not commit or copy it into fixtures, and publish only the
anonymized labels in docs or PR summaries.

Use the correlation report to choose the next smallest implementation PR. For
example, if high mismatch windows repeatedly line up with Amiga-table neutral
fallbacks, choose Amiga pitch behavior. If they line up with applied or
deferred effect-column events, choose one specific remaining effect such as
portamento, vibrato, arpeggio, or a focused follow-up to
minimal `E1x`/`E2x`/`E9x`/`ECx`/`EDx` or the supported `900`/`4xy`/`6xy` memory
foundation. If mismatch windows repeatedly line up with diagnosed `E90` no-ops
or effect-memory families not covered by the foundation, decide separately
whether another narrow memory PR is justified. If mismatch windows are broad and
steady while events look plausible, remaining resampling details, loop details,
headroom/clipping diagnostics, or reference-render settings may be the better
next investigation.
For pitch-modulation diagnostics, prefer the specific pitch bucket that
dominates the top mismatch windows: arpeggio for dense `0xy`, remaining
portamento-family work for `5xy` or volume-column tone portamento, vibrato for
volume-column vibrato, and tremolo for `7xy`. If counts are
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
Further feature-flagged runtime C mixer backend expansion should wait until
offline confidence is strong enough to justify additional runtime risk.

Bounded render diagnostics now include `set_finetune_effects` plus render-level
`e5x_set_finetune_*` counts. Same-cell note `E5x` cases report the finetune
nibble, effective finetune, linear period/frequency, and playback step when the
linear-frequency path applies. No-note/effect-memory and unsupported frequency
table cases stay visible as deferred diagnostics.
Bounded render diagnostics also include `fine_portamento_down_effects` plus
render-level `e2x_fine_portamento_down_*` counts. Same-cell note `E2x` cases
fold the fine period increase into the note's initial playback step; no-note
rows with an active voice schedule a row-start sample-step update. `E20`,
no-active-voice, and unsupported frequency-table cases stay visible.
Bounded render diagnostics also include `fine_portamento_up_effects` plus
render-level `e1x_fine_portamento_up_*` counts. Same-cell note `E1x` cases fold
the fine period decrease into the note's initial playback step; no-note rows
with an active voice schedule a row-start sample-step update. `E10`,
no-active-voice, and unsupported frequency-table cases stay visible.
Bounded render diagnostics also include render-level
`eax_fine_volume_slide_up_*` and `ebx_fine_volume_slide_down_*` counts. Nonzero
`EAx`/`EBx` rows apply one clamped row-level channel-volume adjustment; same-cell
notes trigger with the adjusted volume, empty-note rows update an active voice
through the gain path, and `EA0`/`EB0` remain visible as no-op/effect-memory
deferred diagnostics.

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
- confirm default runtime playback uses the CoreAudio C mixer
- confirm `VTX_AUDIO_BACKEND=av_audio` falls back to the CoreAudio C mixer with
  `fallbackReason=retired_backend`
- confirm tracker viewport and parser architecture code were not modified
- confirm export gain/headroom, when used, was applied before PCM16 conversion
- confirm generated WAVs and diagnostics JSON remain local and unstaged
