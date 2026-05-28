# Playback Trace Export

VoodooTracker X can export a developer-only playback trace as JSON Lines
(`.jsonl`). The trace records playback decisions without changing playback
behavior. Use it when comparing VoodooTracker X against MikMod, OpenMPT, or
other reference playback for real XM files.

Do not commit traces from copyrighted modules. Keep local modules and generated
trace files in `/tmp` or another untracked local path.

## Enable Trace Export

Trace export is disabled by default. In Debug builds, set
`VTX_PLAYBACK_TRACE_PATH` to the local JSONL file path before launching the app:

```bash
VTX_PLAYBACK_TRACE_PATH=/tmp/vtx-playback-trace.jsonl \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

For a local/private XM diagnostic target:

```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -derivedDataPath build \
  build

VTX_PLAYBACK_TRACE_PATH=/tmp/vtx-playback-trace.jsonl \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Press Play, let playback run for 10-30 seconds, then press Stop. The trace file
is flushed on stop.

## Trace Fields

Each line is one JSON object. The schema is intentionally flat so it can be
filtered with `jq`, diffed, or imported into a spreadsheet.

Example:

```json
{"audioBufferSampleRate":44100,"bpm":183,"channelIndex":0,"computedFrequency":8363,"computedPanning":-0.4980392,"computedPeriodApproximation":5.273184,"computedPitchSemitones":0,"computedRate":0.189639,"computedVarispeedRate":1,"computedVolume":1,"decision":"triggered","decisionReason":"row_note","effect":"0902","effectCommand":"09","effectParameter":"02","finetune":0,"instrumentIndex":1,"loopEnabled":false,"loopEndFrame":0,"loopLength":0,"loopLengthFrames":0,"loopStart":0,"loopStartFrame":0,"loopType":0,"loopTypeName":"none","noteValue":49,"orderIndex":0,"patternIndex":2,"rateBasis":"targetFrequency/audioBufferSampleRate","relativeNote":0,"rowDuration":0.0273224,"rowIndex":0,"sampleIndex":0,"sampleLength":1024,"sampleOffset":512,"schemaVersion":1,"sourceSampleRate":8363,"speed":2,"targetFrequency":8363,"tickDuration":0.0136612,"tickIndex":0,"tickInRow":0,"usesLinearFrequencyTable":true}
```

Recorded fields include:

- `tickIndex`, `orderIndex`, `patternIndex`, `rowIndex`, `tickInRow`
- `speed`, `bpm`, `tickDuration`, `rowDuration`
- `channelIndex`
- `runtimeAudioBackend`: selected runtime backend name when available
- `usesLinearFrequencyTable`
- `noteValue`, `instrumentIndex`, `sampleIndex`, `relativeNote`, `finetune`
- `effectCommand`, `effectParameter`, `effect`
- `computedVolume`, `finalAppliedVolume`
- `computedPanning` (current playback pan value in the `-1...1` range when known)
- `envelopeEnabled`, `envelopeTick`, `envelopeValue`,
  `envelopeSustainActive`, `envelopeLoopActive`, `fadeoutValue`
- `sourceSampleRate`, `audioBufferSampleRate`, `targetFrequency`,
  `computedPitchSemitones`, `computedFrequency`, `computedVarispeedRate`,
  `computedRate`, `rateBasis`, `computedPeriodApproximation`
- `sampleOffset`, `sampleLength`, `loopStart`, `loopLength`, `loopType`,
  `loopTypeName`, `loopEnabled`, `loopStartFrame`, `loopEndFrame`,
  `loopLengthFrames`, `pingPongLoopApplied`
- `decision`: `observed`, `triggered`, `delayed`, `cut`, `retriggered`,
  `ignored`, or `updated`
- `decisionReason`: short machine-readable context for the decision

For runtime C mixer adapter events, same-cell XM `E5x` set-finetune note
triggers keep the original `effectCommand`/`effectParameter` metadata in the
trace context. The applied sample-step and effective finetune are planned by the
shared adapter diagnostics; no-note `E5x` cases remain diagnosed as deferred
effect-memory/no-note cases instead of being treated as current-voice memory.
Same-cell `E1x` fine portamento up note triggers also keep effect metadata; the
deterministic first-pass policy folds the fine upward pitch adjustment into the
new note's initial sample step. No-note `E1x` rows with an active voice are
emitted as row-start sample-step updates, while `E10` remains an
effect-memory-deferred no-op.
Same-cell `E2x` fine portamento down note triggers also keep effect metadata;
the deterministic first-pass policy folds the fine downward pitch adjustment
into the new note's initial sample step. No-note `E2x` rows with an active
voice are emitted as row-start sample-step updates, while `E20` remains an
effect-memory-deferred no-op.
Same-cell `X1x`/`X2x` extra fine portamento note triggers keep effect metadata
when the supported linear-frequency adjustment is bridged; the first-pass
policy folds the row-level adjustment into the new note's initial sample step.
No-note `X1x`/`X2x` rows with an active voice are emitted as row-start
sample-step updates, `X10`/`X20` remain effect-memory-deferred no-ops, and
other `X` subcommands remain deferred diagnostics.
Same-cell `EAx`/`EBx` fine volume slide note triggers keep effect metadata and
trigger with the row-level adjusted channel volume. Empty-note nonzero
`EAx`/`EBx` rows with an active voice are emitted as row-start gain updates,
while `EA0`/`EB0` remain effect-memory-deferred no-ops.
Same-cell nonzero `Axy` note triggers keep effect metadata and trigger once at
the tick-0 channel volume. The Swift adapter then emits `Axy` gain updates on
ticks `1...(speed - 1)` for the row. Nonzero Axy-style volume slides store
per-channel memory, `A00` replays that memory when available, and missing
memory remains a diagnosed no-op/deferred case. Mixed nibbles keep the
MikMod-observed up-nibble precedence policy.
Same-cell `9xx` note triggers keep effect metadata, and `900` note triggers are
tagged when they reuse prior same-channel nonzero `9xx` sample-offset memory.
Same-cell nonzero `0xy` arpeggio note triggers keep effect metadata and trigger
once at the base note pitch; subsequent arpeggio ticks are emitted as planned
sample-step updates. Empty-note nonzero `0xy` rows with an active voice emit the
deterministic base/x/y tick-cycle sample-step updates at row tick frames. `000`
remains a no-op, and arpeggio effect memory is intentionally not replayed.
`100` and `200` portamento rows replay prior same-channel nonzero `1xx` or
`2xx` slide memory through the shared sample-step update path when available;
missing portamento memory remains diagnosed as effect-memory-deferred/no-op.
`5xy` rows reuse the current `3xx` tone-portamento target/speed for
sample-step updates and the `Axy` tick-level volume-slide policy for gain
updates. Same-cell note `5xy` rows set the tone-portamento target without
retriggering, empty-note rows continue an existing target when available, and
`500` reuses shared Axy-style volume-slide memory when available. Missing
`500` volume-slide memory remains a diagnosed no-op/deferred case.
Same-cell nonzero `6xy` note triggers keep effect metadata and trigger with the
row-level volume-slide adjustment. Empty-note `6xy` rows reuse prior channel
vibrato memory for sample-step updates and use the existing row-start gain
update path for nonzero volume slides. `600` can replay vibrato memory without
volume-slide memory; missing vibrato memory remains effect-memory-deferred.
`Kxx` rows use the existing key-off/release path; same-cell note triggers keep
the `Kxx` effect metadata and then release at the requested row tick.
`Rxy` rows use the shared retrigger path for the active voice. Same-cell note
rows trigger once at tick 0 and schedule generated retriggers on later interval
ticks; `R00` remains an effect-memory-deferred no-op. First-pass volume modes
use the common XM retrigger volume table and clamp channel volume to `0...64`.
XM `E4x` vibrato control rows store per-channel deterministic vibrato
waveform/control state for later `4xy`/`6xy` rows and emit no direct audio
events. Supported first-pass controls cover sine/default, ramp-down, square,
and deterministic random waveforms; unsupported control values remain explicit
deferred diagnostics.

The engine emits an `observed` event with
`decisionReason == "row_timing_before_effects"` before applying row-level timing
commands. This captures header timing from the loaded local XM and
`bpm=183` before a row `Fxx` command changes speed or BPM.

## Inspecting A Trace

Show the first few trigger decisions:

```bash
jq 'select(.decision == "triggered") | {tickIndex, orderIndex, rowIndex, channelIndex, speed, bpm, tickDuration, rowDuration, noteValue, instrumentIndex, relativeNote, finetune, sourceSampleRate, audioBufferSampleRate, targetFrequency, computedRate, rateBasis, computedVolume, envelopeEnabled, envelopeTick, envelopeValue, envelopeSustainActive, envelopeLoopActive, fadeoutValue, finalAppliedVolume, sampleOffset, sampleLength, loopEnabled, loopStartFrame, loopEndFrame, loopLengthFrames, loopType, loopTypeName, pingPongLoopApplied}' \
  /tmp/vtx-playback-trace.jsonl | head -80
```

Find delayed notes, cuts, and retriggers:

```bash
jq 'select(.decision == "delayed" or .decision == "cut" or .decision == "retriggered")' \
  /tmp/vtx-playback-trace.jsonl
```

Compare with an audio report from `docs/audio-comparison.md` by matching the
approximate timestamp from the report to `tickIndex`, `orderIndex`, and
`rowIndex` in the trace.

## Limitations

- Trace export is an observability tool only; it does not make playback more
  compatible.
- Older traces from the retired `AVAudioPlayerNode` / `AVAudioUnitVarispeed`
  backend contain first-pass scheduling approximations. Current runtime traces
  should be interpreted against the CoreAudio C mixer path.
- Volume envelopes are first-pass playback state. Envelope points are linearly
  interpolated per tick, sustain and loop points use deterministic basic
  handling, and volume fadeout advances after XM key-off (`noteValue == 97`).
  Exact FastTracker II envelope quirks and sample-accurate timing remain future
  custom-mixer work.
- The trace records current effect handling. Unsupported XM effects are still
  unsupported.
- Trace files can grow quickly because row decisions and tick updates are
  recorded per channel.

## Runtime C Mixer Trace Notes

The runtime C mixer backend is the default when `VTX_AUDIO_BACKEND` is unset.
`VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` remain
accepted aliases for the same CoreAudio DefaultOutput Audio Unit host. Both
names feed the same C mixer render core and planned adapter event stream into
the CoreAudio host. `VTX_AUDIO_BACKEND=av_audio` is a retired legacy value that
falls back to the CoreAudio C mixer with `fallbackReason=retired_backend`. The
retired AVAudioSourceNode C mixer host is no longer selectable. Unknown backend
values fall back to the CoreAudio default and are reported with
`fallbackReason=unknown_backend`.
The summary helper classifies backend selection as `default`, `explicit`, or
`fallback_default`.
In Debug builds, set
`VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl` to write a
local-only JSONL trace for the runtime C mixer path. Set
`VTX_C_MIXER_RUNTIME_DISABLE_TRACE=1` to keep the C mixer backend running
without runtime C mixer trace writer overhead.

For the runtime C mixer, the runtime render format aligns to
the output graph/device sample rate where practical. The selected rate drives
the C mixer render config, CoreAudio host format, runtime capture, planned
adapter event frames, and sample-time resolver. `VTX_C_MIXER_RUNTIME_SAMPLE_RATE`
can force a finite positive sample rate for local diagnostics. Offline
`vtx_render_bounded_xm` defaults and behavior are unchanged.

The runtime C mixer trace now includes output diagnostics intended to explain
live-only pops, crackle, harsh transitions, and runtime/offline differences
without changing playback semantics. Trace rows can include backend sample rate,
channel count, render callback count, requested frame counts, cumulative
requested/rendered frames, min/max/last callback frame counts, successful and
failed render counts, zero-fill and underrun counters where detected, output
peak/RMS summaries after runtime gain, overrange/clipping counts after runtime
gain, `clippingDetected`, `runtimeClippingRecommendation` when clipping remains,
adjacent-sample output discontinuity counters, the largest same-channel
adjacent-frame jump observed after runtime gain, the last discontinuity frame
when the trace-only threshold is crossed, and the runtime output gain/headroom
policy. The current runtime C path applies no equivalent of the offline
`--auto-headroom` export policy.

Transport trace rows may include `runtimeAction` values `play`, `stop`,
`spacebarPlay`, and `spacebarStop`. These rows report the selected
`runtimeAudioBackend`, the previous order/pattern/row in
`previousOrderIndex`, `previousPatternIndex`, and `previousRowIndex`, and the
position after the transport action in `nextOrderIndex`, `nextPatternIndex`,
and `nextRowIndex`. For stop actions, the `next...` fields are the preserved
position. For play actions, the `next...` fields are the position used to start
playback. The fields are diagnostics only; they do not change backend
selection, mixer DSP, parser behavior, or tracker viewport rendering.

When a C mixer backend is selected, Debug builds can also capture
the actual post-gain PCM handed to the runtime output host to a local WAV:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-capture-trace.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-runtime-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Use `VTX_AUDIO_BACKEND=c_mixer_coreaudio` with the same local-only capture
controls to verify the compatibility alias.

`VTX_C_MIXER_RUNTIME_CAPTURE_PATH` applies to the CoreAudio C mixer path,
including the retired `av_audio` fallback.
`VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS` sets the bounded in-memory capture limit;
the default and maximum local-debug cap is 240 seconds. The capture path may be
absolute locally, but trace rows and summaries report only the output basename.
Generated WAVs, traces, and comparison reports should stay under `/tmp` or
another untracked local path.

Runtime C mixer playback lifetime is planned from the same adapter timeline
used to queue runtime C mixer events. The CoreAudio-hosted runtime C mixer
silences the C mixer and stops transport at the planned song end plus a short
runtime tail. The default tail is 3 seconds and can be changed locally
with `VTX_C_MIXER_RUNTIME_TAIL_SECONDS=N`. Trace rows
report `plannedSongEndFrame`, `plannedSongEndSeconds`, `runtimeTailSeconds`,
`runtimeTailFrames`, `songEndStopFrame`, `songEndStopSeconds`,
`runtimeFrameAtSongEndTailStop`, active/loaded voice counts at planned end and
tail stop, event-queue exhaustion, and normalized `stopReason` values such as
`song_end_tail`, `debug_stop`, `user_stop`, `transport_stop`, and
`capture_cap_only`.

`VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS` is capture-only. A shorter capture cap
may truncate the local WAV buffer while playback continues to the planned song
end plus tail. A longer capture cap does not keep runtime playback alive.
`VTX_DEBUG_STOP_AFTER_SECONDS` remains a playback stop for local automation and
takes precedence when it fires before song end plus tail.

Set `VTX_C_MIXER_RUNTIME_DISABLE_CAPTURE=1` to disable runtime capture even
when `VTX_C_MIXER_RUNTIME_CAPTURE_PATH` is present. Set
`VTX_C_MIXER_RUNTIME_MINIMAL_CALLBACK=1` to run the C mixer with
trace and capture disabled and only minimal callback counters/output delivery
diagnostics enabled. These flags are local diagnostic controls for
the runtime C mixer backend; they do not affect offline rendering.
Set `VTX_C_MIXER_RUNTIME_VERIFY_OUTPUT_COPY=1` only for short local
diagnostic runs that need scratch/capture/output hash comparison; it is
disabled by default to keep the callback smaller. For local
isolation, run the CoreAudio host with trace and capture enabled, trace only,
capture only, both disabled, and minimal-callback mode. Keep any listening
notes, traces, captures, logs, and summaries local and unstaged.

The audio callback does not write the WAV. It captures the same already-gained
interleaved Float32 scratch frames that are handed to the selected runtime host:
copied into DefaultOutput Audio Unit buffers for both accepted C mixer backend
names. WAV writing happens later, outside the callback, when playback stops or
the backend resets. The capture sample rate is the selected runtime C mixer
sample rate. If the buffer fills, trace rows use
`runtimeAction == "capture_truncated"`; otherwise a successful write uses
`runtimeAction == "capture_written"`. Failed writes use
`runtimeAction == "capture_write_failed"`.

The normal no-event callback real-time inventory is intentionally narrow: it renders
through the preallocated C mixer wrapper, applies runtime gain into a reused
interleaved scratch buffer, optionally copies into a bounded in-memory capture
buffer, copies into the selected host's output buffers, and updates
preallocated counters and fixed-capacity diagnostic buffers. It does not
perform file I/O, call AppKit, parse module data, enqueue trace writes, grow
diagnostic arrays, or mutate diagnostic dictionaries. Shared runtime state is
entered with a single non-blocking render-core lock attempt for the normal
CoreAudio render/copy/counter update path; the callback never waits on that
lock. If the callback cannot enter and a previous valid callback output block
exists, it copies that stale block to the host output buffer and reports
`callbackRenderedFromStaleSnapshotCount`. If no previous output is available,
it renders silence, increments
`callbackRenderedSilenceDueToUnavailableStateCount`, leaves
`callbackSkippedAudioDueToLockCount` at zero because the host buffer was still
filled, and reports `callbackLockFailureAudioImpact=true`. Adapter-event diagnostics are drained
outside the callback with a non-blocking attempt; if the drain cannot enter the
render core, `callbackSkippedDiagnosticsDueToLockCount` is incremented instead
of blocking the render thread.
Adapter-event callback diagnostics are written into a fixed-capacity ring
buffer and drained outside the callback; if the ring fills, diagnostics are
dropped and summarized with `callbackDiagnosticDropCount` rather than allocating
more storage. Burst summaries use a small voice/ramp-count state snapshot rather
than a full render snapshot. Top output peak/jump diagnostics use
fixed-capacity slots. The optional output-copy verification hashes/sample
summaries are diagnostic-only and opt-in with
`VTX_C_MIXER_RUNTIME_VERIFY_OUTPUT_COPY=1`.

Capture-related trace fields include `runtimeCaptureEnabled`,
`runtimeCapturePathName`, `runtimeCaptureSampleRate`,
`runtimeCaptureChannelCount`, `runtimeCaptureSeconds`,
`runtimeCaptureFrameLimit`, `runtimeCapturedFrameCount`,
`runtimeCaptureDurationSeconds`, `runtimeCaptureTruncated`,
`runtimeCaptureOutputPeak`, `runtimeCaptureOutputRMS`,
`runtimeCaptureOverrangeSampleCount`, `runtimeCaptureClippingSampleCount`,
`runtimeCaptureWriteSucceeded`, `runtimeCaptureWriteError`, and
`runtimeCaptureConfigurationWarning`. Use these fields with the runtime
gain/headroom fields when comparing `/tmp` runtime captures against offline
`vtx_render_bounded_xm` WAVs.

Runtime host/format trace fields include `runtimeAudioBackend`,
`runtimeOutputHostType`, `runtimeOutputHostRunning`,
`runtimeOutputHostStartCount`, `runtimeOutputHostPrepareStatus`,
`runtimeOutputHostInitializeStatus`, `runtimeOutputHostStartStatus`,
`runtimeOutputHostStopStatus`, `runtimeOutputHostLastErrorStatus`,
`selectedRuntimeSampleRate`,
`cMixerRuntimeSampleRate`, `runtimeSampleRatePolicy`,
`runtimeSampleRateSource`, `runtimeSampleRateConfigurationWarning`,
`cMixerRenderSampleRate`, `cMixerRenderChannelCount`,
`audioHardwareNominalSampleRate`, `runtimeCaptureSampleRate`, and
`audioFormatConversionLikely`. Matching C mixer, capture, output-host, and
hardware rates should make `audioFormatConversionLikely` false or reduce the
remaining conversion evidence; mismatched rates keep the diagnostic true.

Runtime lifecycle trace fields include `debugStopAfterSeconds`,
`cMixerRenderedFramesBeforeClear`, `cMixerPlaybackSecondsBeforeClear`,
`plannedSongEndFrame`, `plannedSongEndSeconds`,
`plannedSongEndRuntimeFrame`, `plannedSongEndRuntimeSeconds`,
`runtimeFrameAtPlannedSongEnd`, `runtimeSecondsAtPlannedSongEnd`,
`eventQueueExhausted`, `eventQueueExhaustedFrame`,
`eventQueueExhaustedSeconds`, `activeVoiceCountAtPlannedSongEnd`,
`loadedVoiceCountAtPlannedSongEnd`, `activeVoiceCountAfterPlannedSongEnd`,
`loadedVoiceCountAfterPlannedSongEnd`, `outputContinuesAfterPlannedSongEnd`,
and `finalSustainedVoicesContinueAfterPlannedSongEnd`. Use these fields with
`runtimeCaptureSeconds`, capture write/truncation rows, and stop-action rows to
distinguish capture duration, debug stop duration, planned song end, and any
continued output after the planned event stream is exhausted.

Runtime output-device diagnostics also report hardware IO buffer duration,
hardware latency and safety offset when CoreAudio exposes them, a hashed default
device UID, optional safe route label, transport type label, output-host
running state, output-host start count, graph format-change count, output
route-change count, and change-event booleans for route/device, sample rate,
channel count, and IO buffer duration. The raw device name and raw device UID
are not written to public docs; local traces use only a hashed device UID,
numeric device id, and any safe label explicitly supplied for the run.

For route matrix runs, set `VTX_C_MIXER_RUNTIME_ROUTE_LABEL` to a generic label
such as `built-in`, `bluetooth`, or `usb-interface`, then run the same
`VTX_AUDIO_BACKEND=c_mixer` smoke on at least two practical routes:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_ROUTE_LABEL=bluetooth \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-route-bluetooth.jsonl \
VTX_C_MIXER_RUNTIME_CAPTURE_PATH=/tmp/vtx-c-route-bluetooth-capture.wav \
VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS=240 \
VTX_DEBUG_AUTOPLAY=1 \
VTX_DEBUG_START_ORDER=0 \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Summarize each route locally:

```bash
python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-route-bluetooth.jsonl \
  --live-artifact-reported unknown \
  --json /tmp/vtx-c-route-bluetooth-summary.json \
  --markdown /tmp/vtx-c-route-bluetooth-summary.md
```

The summary reports route/device fields, route/config change counts, callback
health, output-copy verifier status, runtime-capture cleanliness, and a
`clean_source_dirty_live` route-vs-callback candidate conclusion. Use
`--live-artifact-reported yes` or `no` only for a local run that was actually
listened to. Generated traces, captures, reports, logs, and listening notes
must stay local and unstaged.

The callback isolation fields report whether the runtime render callback ran on
the main thread, the callback thread id,
whether a main-thread callback dependency was detected, whether known diagnostic
allocation risk remains in the callback, whether realtime-safe diagnostic
buffering is active, fixed ring-buffer capacity, diagnostic drop count,
lock attempt count, try-lock failure count, skipped-audio and stale-output
fallback counts, skipped diagnostic drains, lock-wait counters, lifecycle
overlap counters, event-queue producer/consumer thread ids, and playback-follow
publication counts. For a local isolation run,
set
`VTX_C_MIXER_RUNTIME_DISABLE_FOLLOW_PUBLICATION=1` with
either C mixer backend name to suppress tracker follow callbacks without
changing offline rendering.

Transient diagnostics are also included in later snapshot rows. The trace keeps
the existing high adjacent-sample jump threshold and adds cumulative counts for
lower thresholds such as `0.25`, `0.35`, `0.50`, and `0.75`, the max adjacent
same-channel sample jump, bounded top jumps, top output peaks above the warning
threshold, and whether peaks exceed `1.0`. The summary helper maps those frames
back to nearby order/pattern/row/tick context when the runtime adapter timeline
is available.

The runtime C mixer is the default and can also be selected explicitly with
`VTX_AUDIO_BACKEND=c_mixer` or the `VTX_AUDIO_BACKEND=c_mixer_coreaudio` alias.
It applies a conservative default runtime output policy, currently
`default_runtime_headroom_db` with `-12 dB` headroom. This gain is applied only
in the runtime C mixer handoff to the selected live host; it does not change
`vtx_render_bounded_xm`.

Trace rows report `runtimeOutputGain`, `runtimeHeadroomPolicy`,
`runtimeGainPolicyLabel`, `runtimeDefaultHeadroomDB`,
`runtimeGainPolicySource`, and `runtimeGainPolicyIsEnvironmentOverride` so local
smoke runs can distinguish the fixed default policy from an explicit
environment override. `runtimeAutoHeadroomEnabled` remains `false` for this live
runtime path.

For local C-mixer-only diagnostics, use exactly one of:

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_GAIN=0.5 \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

```bash
VTX_AUDIO_BACKEND=c_mixer \
VTX_C_MIXER_RUNTIME_HEADROOM_DB=-9 \
VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl \
VTX_OPEN_PATH=/path/to/local-reference-module.xm \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

`VTX_C_MIXER_RUNTIME_GAIN` must be finite, greater than `0`, and at most `1`.
`VTX_C_MIXER_RUNTIME_HEADROOM_DB` must be finite and no greater than `0`. If
both are set, or an invalid value is supplied, the runtime C mixer falls back to
the default conservative policy and writes `runtimeGainConfigurationWarning` in
the runtime C trace.

Exact offline-style `--auto-headroom` for live runtime playback is intentionally
not implemented here. Matching the offline export policy for runtime playback
would require a future pre-playback preflight or dry-render peak-analysis pass,
or equivalent lookahead, rather than dynamic limiting. A future scoped PR could
use that approach under a title such as Runtime C Mixer Preflight Auto-Headroom.

For epsilon hypothesis testing only, Debug builds accept
`VTX_C_MIXER_RUNTIME_UPDATE_EPSILON`. The default remains `1e-5`; setting `0`
or another finite value between `0` and `0.01` changes only the runtime C
mixer update guard and records `runtimeUpdateEpsilon`,
`runtimeUpdateEpsilonPolicy`, and any configuration warning in the trace. This
is not a mitigation and should be used only for local diagnostics.

Render callback diagnostics are collected in memory and surfaced on later
main-side trace events. The audio callback does not write trace files, call
AppKit, parse module data, or allocate large diagnostic structures. Lock
contention that prevents the render callback from entering the mixer may still
produce silence before all counters can be updated, so treat the counters as
diagnostic evidence rather than a complete real-time profiler.
Runtime live output capture follows the same rule: the callback only performs a
bounded copy into preallocated storage, and disk writes are deferred outside the
real-time path.

Row transition breadcrumbs use `runtimeAction == "row_transition"` and include
the current order, pattern, row, tick, active/loaded voice counts, render
counters, and output-level snapshot. Backend lifecycle breadcrumbs such as
`backend_initialized`, `backend_prepared`, `backend_start`,
`backend_start_failed`, and `backend_reset` help identify whether a harsh
transition coincides with a runtime backend rebuild or fallback.

Immediate channel-scoped stop diagnostics use `c_mixer_stop_channel`. Those
events include the channel context when available, `stoppedVoiceCount`,
`activeVoiceCountBefore`, `activeVoiceCountAfter`, `loadedVoiceCountBefore`,
and `loadedVoiceCountAfter` when available. Runtime same-channel note
replacement in the runtime C mixer uses `c_mixer_stop_channel_ramped`
instead of a hard stop: the replaced tagged voice is faded out over
`replacementRampFrames` frames, currently `32`, while the new replacement voice
starts at the intended time. Ramped replacement rows include `rampedVoiceCount`,
`replacementRampFrames`, `replacementVoicesOverlap`, active/loaded voice
snapshots when available, and the cumulative `replacementRampCount`. Dense
same-frame replacement bursts also include the outgoing voice id/tag and
pre-replacement state (`replacementOldVoiceIndex`,
`replacementOldVoiceChannelTag`, gain/pan/sample-step, key-on, and fadeout
fields), the replacement ramp start/target state
(`replacementRampStartVoiceIndex`, `replacementRampStartGain`,
`replacementRampTargetGain`, `replacementRampStartPan`,
`replacementRampStartSampleStep`), the new voice id/tag when known, and
booleans showing whether same-frame gain/pan, sample-step, key-off, or fadeout
state was already reflected before the replacement ramp began. True
transport-wide stop/reset actions use `c_mixer_clear_all` and
`targetScope == "all_channels"`.

Runtime C mixer trace rows include CoreAudio host and route diagnostics for
downstream output investigation: `runtimeOutputHostType`,
`runtimeOutputHostRunning`, `runtimeOutputHostStartCount`,
`runtimeOutputHostPrepareStatus`, `runtimeOutputHostInitializeStatus`,
`runtimeOutputHostStartStatus`, `runtimeOutputHostStopStatus`,
`cMixerRenderSampleRate`, `cMixerRenderChannelCount`,
`audioHardwareNominalSampleRate`, `audioHardwareIOBufferFrameSize`,
`audioHardwareIOBufferDuration`, `audioFormatConversionLikely`, and
`runtimeCaptureMatchesHardwareSampleRate`. These fields are diagnostic only and
do not change runtime backend behavior.

Callback timing/output-copy rows can also include
`runtimeMinimalCallbackMode`, `callbackDurationMinMS`,
`callbackDurationMaxMS`, `callbackDurationAverageMS`, `callbackMaxDurationMS`,
`callbackAvgDurationMS`,
`callbackDurationWarningCount`, `callbackRenderQuantumDurationMS`,
`callbackOverRenderQuantumBudgetCount`, `callbackNearBudgetWarningCount`,
`callbackIntervalMinMS`, `callbackIntervalMaxMS`, `callbackRealtimeSafeDiagnostics`,
`callbackDiagnosticDropCount`, `callbackRingBufferCapacity`,
`callbackLockAttemptCount`, `callbackTryLockFailureCount`,
`callbackLockFailureCount`, `callbackLockFailureAudioImpact`,
`callbackRenderedFromStaleSnapshotCount`,
`callbackRenderedSilenceDueToUnavailableStateCount`,
`callbackSkippedDiagnosticsDueToLockCount`, `callbackSkippedAudioDueToLockCount`,
`lifecycleChangeWhileRenderingCount`,
`audioUnitLifecycleCallWhileCallbackActiveCount`, `outputBufferCopyAttemptCount`,
`outputBufferCopyFailureCount`, `outputBufferCopyLastSucceeded`,
`outputBufferCopyLayout`, requested/copied frame and sample counts, channel
counts, partial-copy flags, and, when explicitly enabled, scratch/capture/output
hashes. A matching scratch-capture hash plus matching scratch-output hash means
the output buffer received the same samples that runtime capture recorded; any
mismatch points past C mixer DSP and toward callback/output delivery.

When the CoreAudio C mixer host is running, tracker-follow and row-transition
trace breadcrumbs use the callback-published sample-time frame instead of taking
a render-core snapshot. This keeps long-run follow diagnostics available without
letting main-thread UI/trace publication contend with the render callback lock.
The summary reports published follow event count, approximate publication rate,
frame span, and published-follow-vs-C-mixer deltas for long-run drift checks.

Supported runtime C mixer control updates now classify the remaining update
handoff cases instead of treating no-op refreshes and missing targets as one
deferred bucket. Applied update rows remain
`c_mixer_update_gain_pan_applied`, `c_mixer_update_step_applied`, or
`c_mixer_update_gain_pan_step_applied`. Non-applied rows use
`c_mixer_update_suppressed_no_change`,
`c_mixer_update_stored_channel_state`,
`c_mixer_update_deferred_no_active_voice`,
`c_mixer_update_deferred_stale_after_stop`,
`c_mixer_update_deferred_missing_data`, or
`c_mixer_update_deferred_unsupported`.

Update trace rows include `updateDisposition` values such as `update_applied`,
`update_suppressed_no_change`, `update_stored_channel_state`,
`update_deferred_no_active_voice`, `update_deferred_stale_after_stop`,
`update_deferred_missing_data`, and `update_deferred_unsupported`, plus
`updateType` values such as `gain`, `pan`, `step`, `combined`, or `none`.
Runtime C mixer updates use a strict `1e-5` epsilon for gain, pan, and
sample-step deltas before scheduling C mixer update events. Per-field deltas at
or below that threshold are suppressed, combined updates apply only fields that
exceed it, and all-fields-below-epsilon updates are reported as
`update_suppressed_no_change` without restarting gain/pan ramps or sample-step
updates. Rows may include `updateEpsilon`, `gainRequested`, `panRequested`,
`sampleStepRequested`, `gainDelta`, `panDelta`, `sampleStepDelta`,
`gainUpdateStatus`, `panUpdateStatus`, and `sampleStepUpdateStatus` with
statuses such as `applied`, `suppressed_epsilon`, or `unchanged`.
When the local epsilon override is supplied, `updateEpsilon` records the active
threshold for each update row so default and tightened/disabled runs can be
compared without changing the default backend or offline rendering.

Reasons further distinguish harmless no-active refreshes, stale updates after a
channel stop, update-before-note cases, missing runtime channel state, unknown
no-active cases, missing sample-step target data, and unsupported values.
Gain/pan changes without an active target voice may be retained as channel state
for a later note trigger; step/pitch changes without an active sample/note
target remain deferred. Update rows include the target channel via
`channelIndex`, `targetVoiceIndex` when available, active/loaded voice counts
before and after when available, and `gainBefore`/`gainAfter`,
`panBefore`/`panAfter`, and `sampleStepBefore`/`sampleStepAfter` when
available. Gain/pan updates keep the C mixer's fixed micro-ramp; sample-step
updates apply at the scheduled runtime mixer frame.

Trace events also carry cumulative event counters for C mixer add-voice calls,
gain/pan update attempts, sample-step update attempts,
`updateSuppressedEpsilonGainCount`, `updateSuppressedEpsilonPanCount`,
`updateSuppressedEpsilonStepCount`, `updateSuppressedNoChangeCount`,
`updateAppliedAfterEpsilonFilterCount`, channel stops, replacement ramps, and
global clear-all calls. These counters correspond to the runtime diagnostics categories
`update_suppressed_epsilon_gain`, `update_suppressed_epsilon_pan`,
`update_suppressed_epsilon_step`, `update_suppressed_no_change`, and
`update_applied_after_epsilon_filter`. Runtime C mixer snapshots also report
`eventQueueBacklogCount`; when the offline-adapter plan is active this is the
count of planned events still waiting for their render callback frame.

Replacement-ramp cleanup diagnostics are cumulative in the same snapshots:
`rampingOutVoiceCount`, `rampDownStartCount`, `rampDownCompletionCount`, and
`abruptRampDownStopCount` distinguish voices still fading out, completed ramp
cleanup, and any unexpected removal while a ramp was active.

### Runtime Adapter Event Bridge Diagnostics

When a runtime C mixer backend is selected, the
runtime now attempts to precompute a `PlaybackSong` adapter event plan from the
same offline-adapter semantics used by bounded C mixer renders. These fields
are only for the C mixer path.

Runtime C mixer trace rows may include:

- `runtimeEventSource`: `offline_adapter_plan`, `playback_engine_simple`, or
  `hybrid`
- `adapterPlanGenerated`: whether a runtime adapter plan was available
- `adapterPlanGenerationMS`: load-time adapter plan generation duration in
  milliseconds, emitted on the `adapter_plan_configured` row
- `plannedEventCount`, `consumedPlannedEventCount`,
  `skippedUnmatchedPlannedEventCount`
- `runtimeRowOrderMapping`: the order/pattern/row/tick key used to match
  planned events
- `adapterEventCategory` and `adapterEventCategoriesConsumed`
- `fallbackToSimpleRuntimeEventCount` and `runtimeEventFallbackReason`

Adapter-sourced rows cover only event categories already supported by the
offline adapter, such as note triggers, gain/pan updates, sample-step updates,
`Hxy` global-volume updates, `ECx` note cuts, `EDx` note delays, `E9x`
retriggers, `Rxy` multi-retriggers, `0xy` arpeggio updates,
`1xx`/`2xx`/`3xx` portamento updates,
including `100`/`200` memory-replayed sample-step updates, minimal `E1x` fine
portamento up updates, minimal `E2x` fine portamento down updates, minimal
`X1x`/`X2x` extra fine portamento updates, minimal `E4x` vibrato-control
state, `4xy` vibrato sample-step updates, sample
offsets including `900` memory replay metadata, minimal `EAx`/`EBx` fine
volume slide gain updates, minimal `5xy` tone-portamento + volume-slide
sample-step/gain updates, minimal `6xy` vibrato + volume slide
sample-step/gain updates, minimal `Lxx` volume-envelope-position updates, and volume-column set
volume/panning for empty-note rows and same-cell valid-note `3xx`
no-retrigger rows that keep the carried voice active. Adapter diagnostics
include `E4x` state rows; adapter-sourced `0xy`,
`1xx`/`2xx`, `E1x`, `E2x`, `4xy`,
`5xy`, `Rxy`, `EAx`/`EBx`, `6xy`, and `Lxx` rows carry the effect type/parameter on the
runtime update row so coverage summaries can count applied updates. Memory-replayed
sample-offset, portamento-slide, and vibrato updates carry
`effect_memory_reused` categories plus effect-specific memory-applied tags in
the planned adapter event stream. Volume-column vibrato and broader
effect-memory families remain unsupported/deferred.
Repeated same-channel note triggers in the runtime adapter event plan are also
tagged with the `replacement` category, matching the C mixer runtime
same-channel replacement path and the bounded/offline replacement-ramp
diagnostics.
Unsupported XM effects remain unsupported.
If the plan is unavailable, the runtime trace reports the fallback and the C
mixer continues through the simpler runtime event bridge.

### Runtime Sample-Time Alignment Diagnostics

The runtime C mixer queues planned offline-adapter events by
their intended runtime frame and applies them inside the selected runtime host
callback. When an event falls within a callback range, the runtime C mixer
renders up to the event offset, applies the event, then continues the callback
render. These fields are diagnostic-only outside the C mixer backend; they do
not add a UI toggle or change offline render semantics.

Runtime snapshot rows may include:

- `runtimeRenderedFrameCount`: cumulative C mixer frames rendered by the
  runtime backend
- `cMixerRenderedFrames`: the C mixer sample-time frame cursor used for
  diagnostics at the trace point
- `cMixerPlaybackSeconds`: `cMixerRenderedFrames / sampleRate`
- `callbackIndex`, `callbackRequestedFrameCount`, `callbackStartFrame`, and
  `callbackEndFrame`: the most recent runtime host callback range known to the
  runtime C mixer diagnostics
- `currentFrame`: the current C mixer frame cursor when the trace row was
  recorded

Offline-adapter event rows may include:

- `plannedSourceOrderIndex`, `plannedSourcePatternIndex`,
  `plannedSourceRowIndex`, `plannedSourceTickInRow`, and
  `plannedSourceChannelIndex`
- `plannedEventFrame`: the absolute frame from the offline adapter plan
- `plannedRuntimeFrame`: the planned frame after applying the runtime start
  offset, when the offset is computable
- `runtimeApplicationFrame`: the runtime C mixer frame when the event was
  applied
- `eventAppliedFrame`: the exact runtime C mixer frame at which the render
  queue applied the event
- `inCallbackOffset`: the event offset inside the callback range
- `eventFrameDelta`: `runtimeApplicationFrame - plannedRuntimeFrame`, when
  both are computable
- `plannedVsAppliedDelta`: `eventAppliedFrame - plannedRuntimeFrame`, when
  both are computable
- `sameFrameBurstSize`: number of planned events applied at the same runtime
  frame
- `sameFrameBurstID` and `sameFrameBurstEventOrdinal`: deterministic burst key
  and application order within that frame
- `sameFrameBurstCategories`, `sameFrameBurstAffectedChannels`, and per-burst
  category counters for note triggers, replacement ramps, gain/pan updates,
  sample-step updates, note cuts, key-off/fadeout, and global-volume updates
- `sameFrameBurstActiveVoiceCountBefore`,
  `sameFrameBurstActiveVoiceCountAfter`,
  `sameFrameBurstLoadedVoiceCountBefore`, and
  `sameFrameBurstLoadedVoiceCountAfter`
- `sameFrameBurstVoicesEnteringRampDown`,
  `sameFrameBurstVoicesCompletingRampDown`,
  `sameFrameBurstNewVoicesStarted`, and
  `sameFrameBurstSustainedVoicesCarried`
- `sameFrameBurstAtOrderStart` and `sameFrameBurstAtRowTransition`
- `adapterActiveEventIndex`, `adapterCurrentEventIndexBefore`,
  `adapterCurrentEventIndexAfter`, `adapterChannelAssociationRetained`, and
  `adapterSustainedVoiceUpdate`, which help identify no-note update cells that
  target a carried channel voice at order boundaries
- `runtimeEventCategory`: normalized categories such as `note_trigger`,
  `replacement_stop_ramp`, `gain_pan_update`, `step_pitch_update`,
  `lxx_set_envelope_position`, `ecx_edx_e9x`, `hxy_global_volume`,
  `key_off_fadeout`, and
  `row_transition`
- `eventApplicationTiming`: `exact_frame`, `callback_start`, `late`,
  `tick_boundary`, `row_boundary`, or `unknown`

Within the runtime C mixer render queue, same-frame planned events are
applied in a deterministic order that matches the offline C mixer frame
boundary: gain/pan and sample-step voice-state updates first, note cuts next,
note triggers next, and same-frame envelope-position updates after note triggers
so same-cell note+`Lxx` targets the newly triggered voice. Same-channel replacement ramps remain part of the note
trigger path and are traced with the burst diagnostics above.

When a precomputed adapter plan is available, runtime trace rows also resolve
the C mixer sample-time cursor back to the planned order/pattern/row/tick
timeline:

- `cMixerSampleTimeFrame`
- `cMixerSampleTimePositionStatus`
- `cMixerSampleTimeOrderIndex`, `cMixerSampleTimePatternIndex`,
  `cMixerSampleTimeRowIndex`, and `cMixerSampleTimeTickInRow`
- `playbackEngineOrderIndex`, `playbackEnginePatternIndex`,
  `playbackEngineRowIndex`, and `playbackEngineTickInRow`
- `playbackEngineToCMixerFrameDelta`
- `playbackEngineToCMixerPositionMismatch`
- `rowTransitionDeltaCategory`
- `publishedPlaybackFollowPositionSource`: `playback_timer` or
  `c_mixer_sample_time`
- `publishedPlaybackFollowOrderIndex`,
  `publishedPlaybackFollowPatternIndex`,
  `publishedPlaybackFollowRowIndex`, and
  `publishedPlaybackFollowTickInRow`
- `publishedPlaybackFollowSampleTimeFrame`,
  `publishedPlaybackFollowToCMixerFrameDelta`, and
  `publishedPlaybackFollowToCMixerRowDelta`
- `playbackEngineToPublishedPlaybackFollowFrameDelta` and
  `playbackEngineToPublishedPlaybackFollowRowDelta`

These fields compare the `PlaybackEngine` timer/order-row-tick clock with the
C mixer sample-time clock at the same trace point. For the runtime C mixer
backend, the published playback-follow position uses the sample-time-derived C
mixer position when the planned adapter timeline is available. This does not
change tracker viewport math, static highlight-row behavior, audio event
timing, or offline rendering.

The expected interpretation is:

- `PlaybackEngine` order/row/tick is advanced by the app-side playback timer.
  Generic non-C-mixer test outputs publish this timer position to UI/follow
  code.
- That timer is a `Foundation.Timer(timeInterval: timing.tickDuration,
  repeats: true)` scheduled on `RunLoop.main` in `.common` mode. It is a
  main-run-loop wall-clock timer, not an audio-device sample clock.
- Each timer fire calls `advanceOneTick()`, advances `PlaybackTickState`,
  applies tick effects until the row boundary, then advances `currentPosition`
  and publishes row changes through `positionDidChange`. With a C mixer
  backend, that published value is selected from the
  C mixer sample-time resolver when possible while the timer position remains
  separately traced as `playbackEngine...`.
- C mixer sample-time position is resolved from the runtime C mixer's rendered
  frame cursor, the backend sample rate, and the planned adapter row/tick
  timeline.
- For the runtime C mixer, the rendered-frame cursor comes from the selected
  runtime host callback via the narrow Swift `CSoftwareMixer` wrapper. Planned
  adapter events are queued by runtime frame, applied at exact in-callback
  sample offsets when possible, and the same adapter timeline resolves a
  sample-time frame back to order/pattern/row/tick.
- A nonzero `playbackEngineToCMixerFrameDelta` means those clocks are not at
  the same planned adapter frame when the trace row was recorded. Positive
  deltas indicate the C mixer render cursor is ahead of the `PlaybackEngine`
  timer position; negative deltas indicate it is behind.
- A nonzero `publishedPlaybackFollowToCMixerFrameDelta` means the position
  published to tracker follow differs from the C mixer sample-time position.
  In the C mixer backend this should normally be much closer to
  zero than `playbackEngineToCMixerFrameDelta`.

Runtime snapshots also include cumulative `appliedPlannedEventCount`,
`exactFrameAppliedEventCount`, `callbackBoundaryAppliedEventCount`,
`latePlannedEventCount`, and `maxPlannedVsAppliedDelta`. Late events are traced
and applied at the start of the current callback rather than silently dropped.

Row transitions are traced with a before-event `row_transition` breadcrumb and
an after-event `row_transition_after_events` breadcrumb. These rows may include
previous and next order/pattern/row fields, `transitionRuntimeFrame`,
active/loaded voice counts before and after the row-entry work, and per-row
`transitionReplacementRampCount` / `transitionUpdateCount` deltas.
Summary diagnostics keep transport stop/reset cursor jumps separate from
in-playback drift. Exact in-callback planned-event timestamps may appear after
a callback-end breadcrumb in JSONL order; the summary reports that ordering
case separately instead of treating it as the C mixer render cursor moving
backward during playback.

Runtime C mixer traces are diagnostic artifacts. Keep them under `/tmp` or
another ignored local path, and do not commit traces derived from private/local
modules.

## Runtime C Mixer Trace Summaries

Use the local summary helper when a trace is too large to inspect directly:

```bash
python3 scripts/summarize-runtime-c-mixer-trace.py \
  /tmp/vtx-c-runtime-trace.jsonl \
  --json /tmp/vtx-c-runtime-summary.json \
  --markdown /tmp/vtx-c-runtime-summary.md
```

The helper reads runtime JSONL traces and emits deterministic JSON and Markdown
summaries. It is local/offline tooling only and is tested with synthetic traces,
not private modules.

To audit effect coverage across runtime traces and bounded offline diagnostics
with one local-only table, use `scripts/summarize-xm-effect-coverage.py`:

```bash
python3 scripts/summarize-xm-effect-coverage.py \
  /tmp/vtx-c-runtime-trace.jsonl \
  /tmp/vtx-offline-c-mixer-diagnostics.json \
  --json /tmp/vtx-effect-coverage-summary.json \
  --markdown /tmp/vtx-effect-coverage-summary.md
```

The effect coverage summary reports detected, applied, deferred, unsupported,
and no-op/effect-memory command counts, first source coordinates, runtime versus
offline category, unresolved key-off/no-active buckets, and a conservative
next-effect recommendation. Bounded offline diagnostics also include
`traversal_summary` and `traversal_effects` for focused `Dxx` pattern break,
`Bxx` position jump, and `E6x` pattern loop planning. Those records report
source coordinates, target order/pattern/row, stop reason, guard hits, applied
counts, invalid/out-of-range targets, missing loop starts, and loop-limit hits.
It does not change runtime playback or offline rendering behavior.

When a full or near-full runtime live-output capture is compared with a full
offline C mixer WAV, use the window correlation helper to connect the
whole-song `scripts/audio-compare.py` worst windows back to runtime trace rows:

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
  --json /tmp/vtx-runtime-offline-window-correlation.json \
  --markdown /tmp/vtx-runtime-offline-window-correlation.md
```

The helper reports window-level audio metrics, best local alignment shift,
scalar normalization evidence, nearby note triggers, replacement ramps, ramp
cleanup, key-off/fadeout, gain/pan and sample-step updates, global-volume
updates, same-frame bursts, sustained voice association fields, active/loaded
voice ranges, optional offline diagnostics counts, and a conservative runtime
follow-up recommendation. It is diagnostic-only and does not change playback or
rendering behavior. Keep captures, traces, WAVs, JSON reports, and Markdown
reports from private/local modules under `/tmp` or another ignored local path.

The summary focuses on runtime-only artifact evidence:

- peak, clipping, underrun, zero-fill, unexpected-silent, failed-render, and
  adjacent-sample output discontinuity counters
- callback timing: requested frame-count range, callback start/end frame range,
  min/max/average callback duration, conservative duration warnings, estimated
  render quantum duration, callbacks over the render quantum budget, and
  callback-to-callback interval range
- output buffer copy verification: buffer layout, requested/copied
  frames/samples, channel-count match, partial-copy evidence, and
  scratch/capture/output hash comparison
- runtime gain/headroom policy, including default `-12 dB` headroom,
  default-vs-environment source, fixed headroom dB, and configuration warnings
- lower-threshold discontinuity counts, top adjacent same-channel jumps, top
  peaks, and likely transient correlation (`event burst`,
  `replacement ramp burst`, `peak/clip`, `voice cleanup`, or `unknown`)
- `c_mixer_add_voice`, `c_mixer_stop_channel`,
  `c_mixer_stop_channel_ramped`, and `c_mixer_clear_all` counts
- whether observed replacement stops were ramped or immediate hard stops
- applied gain/pan and step updates, suppressed no-change updates, stored
  channel-state updates, and remaining deferred update categories
- epsilon-suppressed gain/pan/sample-step field counts, top epsilon-suppressed
  updates, whether suppressed fields were fully no-op refreshes or partial
  updates after filtering, and whether suppressed updates were near top transient
  frames
- active/loaded voice ranges and largest same-row/tick event bursts
- largest planned-vs-applied event timing deltas, exact-frame/callback-boundary
  application counts, late planned-event counts, same-frame event bursts,
  order/row transition bursts, and top suspicious order/row/tick positions
- same-frame burst IDs, event ordinals, affected channels, event categories,
  active/loaded voice counts before and after, ramp-down starts/completions,
  new voices, sustained carried voices, and order-start/row-transition flags
- sustained-voice transition counts for order-start update cells, retained or
  lost channel associations, update-without-note applications, and missed or
  stored update events
- max, average, and median row-transition frame deltas
- max, average, and median PlaybackEngine-vs-C-mixer position frame deltas
  from row-transition breadcrumbs, plus millisecond deltas where a sample rate
  is present
- published playback-follow position source counts and max, average, and
  median published-follow-vs-C-mixer frame deltas
- the first PlaybackEngine-vs-C-mixer position divergence above the summary
  threshold
- whether the position drift looks like an accumulating drift, a mostly
  constant offset, or mixed evidence
- largest PlaybackEngine-vs-C-mixer sample-time position mismatches, first
  suspicious mismatch, monotonic sample-time cursor status, transport/reset
  cursor jumps, in-callback timestamp ordering cases, unexpected backward
  cursor movement, and order/row ranges where mismatch is largest
- selected order-transition samples showing both the PlaybackEngine position
  and the C mixer sample-time-derived position
- runtime evidence for categories that the richer offline adapter can emit:
  gain/pan state updates, step/pitch updates, `Hxy`, `ECx`, `EDx`, `E9x`,
  `Rxy`, and `0xy`/`1xx`/`2xx`/`3xx` updates

The helper also records the current architectural interpretation: live runtime
C mixer traces should now show whether events came from the precomputed
`offline_adapter_plan`, from the simpler `playback_engine_simple` fallback, or
from a hybrid path. When offline C-backed WAV renders sound cleaner than
runtime C mixer playback, inspect `plannedEventCount`,
`consumedPlannedEventCount`, `skippedUnmatchedPlannedEventCount`,
`adapterEventCategoriesConsumed`, and `runtimeEventFallbackReason` before
choosing the next runtime stabilization or sample-time alignment PR.

## Manual Verification

- Launch the Debug app with `VTX_PLAYBACK_TRACE_PATH` set.
- Load `/path/to/local.xm` or another local XM file.
- Press Play for 10-30 seconds.
- Press Stop.
- Confirm the JSONL file exists and contains order, pattern, row, tick,
  speed, BPM, tick and row duration, channel, note, instrument, effect, volume,
  panning, pitch/rate/frequency, rate basis, envelope/fadeout fields, sample
  offset, sample loop metadata, loop scheduling fields including
  `pingPongLoopApplied`, and decision fields.
- Launch without `VTX_PLAYBACK_TRACE_PATH` and confirm normal playback still
  works.
- Confirm tracker viewport behavior was not modified or regressed.
