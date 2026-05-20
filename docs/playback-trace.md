# Playback Trace Export

VoodooTracker X can export a developer-only playback trace as JSON Lines
(`.jsonl`). The trace records playback decisions without changing playback
behavior. Use it when comparing VoodooTracker X against MikMod, OpenMPT, or
other reference playback for real XM files.

Do not commit traces from copyrighted modules. Keep local modules and generated
trace files in `/tmp`, `~/Desktop`, or another untracked location.

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
- `computedPanning` (current AVAudio pan value in the `-1...1` range when known)
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
- The current backend uses `AVAudioPlayerNode` and `AVAudioUnitVarispeed`, so
  pitch and period fields are approximations of current scheduling decisions.
  Linear-frequency modules use note/relative-note/finetune frequency
  calculations, but the backend is still not a FastTracker II mixer.
- The current backend pre-renders scheduled sample buffers at
  `audioBufferSampleRate` and traces `computedRate` as
  `targetFrequency/audioBufferSampleRate`.
- Forward sample loops are supported by scheduling the pre-loop/first-loop
  region once and then scheduling the loop region with AVAudio's buffer loop
  option. Ping-pong loops are supported as a first-pass approximation by
  scheduling pre-loop audio once and then looping a derived buffer containing
  the forward loop frames plus the reversed loop interior. This keeps loop
  handling inside the current AVAudio backend, avoids duplicate endpoint frames
  at turnarounds, and does not emulate every FT2 sample-offset or loop-position
  edge case.
- Panning is first-pass only: XM `0...255` channel state maps to the current
  AVAudio `-1...1` pan control, not a tracker-accurate custom mixer.
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

The experimental runtime C mixer backend remains opt-in with
`VTX_AUDIO_BACKEND=c_mixer`; unset or unknown values keep the default
`AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend. In Debug builds, set
`VTX_C_MIXER_RUNTIME_TRACE_PATH=/tmp/vtx-c-runtime-trace.jsonl` to write a
local-only JSONL trace for the runtime C mixer path.

The runtime C mixer trace now includes output diagnostics intended to explain
live-only pops, crackle, harsh transitions, and runtime/offline differences
without changing playback semantics. Trace rows can include backend sample rate,
channel count, render callback count, requested frame counts, cumulative
requested/rendered frames, min/max/last callback frame counts, successful and
failed render counts, zero-fill and underrun counters where detected, output
peak/RMS summaries after runtime gain, overrange/clipping counts after runtime
gain, `clippingDetected`, `runtimeClippingRecommendation` when clipping remains,
and the runtime output gain/headroom policy. The current runtime C path applies
no equivalent of the offline `--auto-headroom` export policy.

The experimental runtime C mixer is still selected only with
`VTX_AUDIO_BACKEND=c_mixer`. When selected, it applies a conservative default
runtime output policy, currently `default_runtime_headroom_db` with `-10 dB`
headroom. This gain is applied only in the runtime C mixer handoff to the
AVAudio source-node buffer; it does not affect the default AVAudio backend and
does not change `vtx_render_bounded_xm`.

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
the runtime C trace. These gain/headroom variables are ignored unless the
experimental C mixer backend is selected.

Render callback diagnostics are collected in memory and surfaced on later
main-side trace events. The audio callback does not write trace files, call
AppKit, parse module data, or allocate large diagnostic structures. Lock
contention that prevents the render callback from entering the mixer may still
produce silence before all counters can be updated, so treat the counters as
diagnostic evidence rather than a complete real-time profiler.

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
replacement in the experimental C mixer uses `c_mixer_stop_channel_ramped`
instead of a hard stop: the replaced tagged voice is faded out over
`replacementRampFrames` frames, currently `32`, while the new replacement voice
starts at the intended time. Ramped replacement rows include `rampedVoiceCount`,
`replacementRampFrames`, `replacementVoicesOverlap`, active/loaded voice
snapshots when available, and the cumulative `replacementRampCount`. True
transport-wide stop/reset actions use `c_mixer_clear_all` and
`targetScope == "all_channels"`.
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
`update_applied_after_epsilon_filter`. The current runtime path has no separate
event queue, so `eventQueueBacklogCount` is reported as `0` when a runtime C
mixer snapshot is available.

### Runtime Adapter Event Bridge Diagnostics

When `VTX_AUDIO_BACKEND=c_mixer` selects the experimental runtime C mixer, the
runtime now attempts to precompute a `PlaybackSong` adapter event plan from the
same offline-adapter semantics used by bounded C mixer renders. The default
runtime backend remains `AVAudioPlayerNode` / `AVAudioUnitVarispeed`; these
fields are only for the opt-in C mixer path.

Runtime C mixer trace rows may include:

- `runtimeEventSource`: `offline_adapter_plan`, `playback_engine_simple`, or
  `hybrid`
- `adapterPlanGenerated`: whether a runtime adapter plan was available
- `plannedEventCount`, `consumedPlannedEventCount`,
  `skippedUnmatchedPlannedEventCount`
- `runtimeRowOrderMapping`: the order/pattern/row/tick key used to match
  planned events
- `adapterEventCategory` and `adapterEventCategoriesConsumed`
- `fallbackToSimpleRuntimeEventCount` and `runtimeEventFallbackReason`

Adapter-sourced rows cover only event categories already supported by the
offline adapter, such as note triggers, gain/pan updates, sample-step updates,
`Hxy` global-volume updates, `ECx` note cuts, `EDx` note delays, `E9x`
retriggers, `1xx`/`2xx`/`3xx` portamento updates, sample offsets, and
volume-column set volume/panning. Unsupported XM effects remain unsupported.
If the plan is unavailable, the runtime trace reports the fallback and the C
mixer continues through the simpler runtime event bridge.

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

The summary focuses on runtime-only artifact evidence:

- peak, clipping, underrun, zero-fill, and failed-render counters
- `c_mixer_add_voice`, `c_mixer_stop_channel`,
  `c_mixer_stop_channel_ramped`, and `c_mixer_clear_all` counts
- whether observed replacement stops were ramped or immediate hard stops
- applied gain/pan and step updates, suppressed no-change updates, stored
  channel-state updates, and remaining deferred update categories
- active/loaded voice ranges and largest same-row/tick event bursts
- runtime evidence for categories that the richer offline adapter can emit:
  gain/pan state updates, step/pitch updates, `Hxy`, `ECx`, `EDx`, `E9x`, and
  `1xx`/`2xx`/`3xx` updates

The helper also records the current architectural interpretation: live runtime
C mixer traces should now show whether events came from the precomputed
`offline_adapter_plan`, from the simpler `playback_engine_simple` fallback, or
from a hybrid path. When offline C-backed WAV renders sound cleaner than
opt-in runtime C mixer playback, inspect `plannedEventCount`,
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
