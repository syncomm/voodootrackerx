# Parsed XM to C Mixer Adapter Plan

## Purpose

This note documents the bridge from the parsed playback model to the synthetic
scheduling layer that already drives the C-backed offline mixer:

```text
PlaybackSong / PlaybackSongBuilder
-> Swift adapter
-> SyntheticPattern / SyntheticTrackerEvent
-> SyntheticPatternScheduler / SyntheticTrackerScheduler
-> CSoftwareMixer
-> MixerCore C renderer
```

This began as a planning document. The minimal bounded adapter now exists, but
it still does not connect real parsed XM playback to the C mixer, change runtime
playback, implement broad XM effect parity, or provide a full public
module-rendering CLI.

## Implementation Status

PR 2.7.10 added `PlaybackSongSyntheticAdapter`, a Swift-side offline adapter
that converts an explicit bounded order selection from `PlaybackSong` into a
`SyntheticTrackerTimingConfig`, `SyntheticPattern`, and diagnostics. It uses
the song's initial speed/BPM plus minimal `Fxx` timing changes inside the
bounded row selection, emits basic note/instrument/sample triggers at tick 0,
copies sample PCM into `MixerSampleBuffer`, maps sample volume to event gain,
maps disabled/forward/ping-pong sample loops into the existing synthetic loop
metadata, and now carries a minimal deterministic note/sample-derived playback
step into the C-backed scheduled voice path.

The follow-up bounded offline render helper now adapts tiny `PlaybackSong`
segments, schedules the adapted synthetic pattern through `CSoftwareMixer`, and
returns the in-memory `MixerRenderBlock` with source-to-synthetic diagnostics.
Those diagnostics record the requested order range, sample rate, initial
speed/BPM, synthetic rows/events, skipped or empty rows, ignored cells, deferred
effect and volume-column fields, applied volume-column state changes,
source order/pattern/row/channel coordinates, synthetic row/tick coordinates,
selected instrument/sample identifiers, and mapped loop mode. They also record
row start frames, effective speed/BPM per adapted row, and any `Fxx` timing
cells encountered. Oversized frame requests are clamped to a conservative
maximum before rendering.
The bounded adapter diagnostics now include an event-coverage summary for
missing-note investigations. It counts total visited cells, empty cells, normal
note cells, note-off cells, invalid notes, instrument-only cells, note cells
with and without an instrument, scheduled note events, skipped note events,
note-off cells that had no active adapted voice, and ignored/deferred cells. It
also classifies skip reasons such as missing instrument, unknown instrument,
empty sample PCM, no playable sample, sample offset out of range, deferred
effect interaction, and C mixer scheduled voice capacity rejection.
Bounded offline note triggers now use parsed XM instrument note-sample maps
when the selected instrument has a usable multi-sample mapping. Diagnostics
record whether a map is present, the mapped sample index, whether that mapped
sample is playable, the selected sample index, and the selection method:
`sample_map`, `first_playable_fallback`, `fallback_after_invalid_map`, or
`skipped_no_valid_sample`.
Pitch diagnostics include the source note, selected sample base sample rate,
output sample rate, sample relative note, raw/effective finetune, effective
note value/index, song linear-frequency flag, frequency-table status, XM linear
period/frequency intermediates when used, calculated playback step, whether the
linear-frequency path was applied, whether Amiga behavior was deferred, and
whether mapping used the neutral default step.

The adapter and helper are still intentionally not full pitch parity.
Linear-frequency songs now use the explicit XM linear-period calculation:
`period = 7680 - zeroBasedNote * 64 - finetune / 2`, with C-4 at period 4608.
That period is converted into a deterministic frequency from the sample base
rate, then into the C mixer's source-sample step by dividing by the output
sample rate. Effective note values are clamped to the valid XM note range and
finetune is clamped to the signed XM byte range before this calculation. Amiga
table behavior is not implemented; non-linear songs are reported as a deferred
Amiga-table path and use a neutral step fallback. The bounded adapter handles
only two regular effect-column cases. Minimal `Fxx` timing support treats
`F01...F1F` as speed changes, `F20...FFF` as represented by byte parameters
`0x20...0xFF` as BPM changes, and `F00` as an ignored no-op. The change affects
rows after the source row where the `Fxx` cell appears; events on the same row
use the timing that was active at row start. Minimal nonzero `9xx` sample offset
support applies only to a note/sample trigger in the same cell and starts that
adapted voice at `xx * 256` source sample frames. `900` is diagnosed as an
ignored/deferred no-op; effect memory is not implemented. Offsets at or beyond
the selected sample length are diagnosed as out-of-range and the voice is
skipped, producing deterministic silence for that trigger. Other XM
effect-column commands remain deferred. The bounded adapter applies only these
conservative XM volume-column commands to bounded offline adapted event gain/pan:
set-volume (`0x10...0x50`), volume slide down/up (`0x60...0x7F`), fine volume
slide down/up (`0x80...0x9F`), set-panning (`0xC0...0xCF`), and panning slide
left/right (`0xD0...0xEF`). Slides are row-level approximations: the adapter
updates Swift-owned per-channel volume or panning state once while planning the
source row, and events emitted for that row use the post-command state. No
tick-by-tick volume or panning ramp is modeled. Volume-column vibrato,
tone-portamento, undefined ranges, and zero-amount effect memory remain
deferred or no-op as diagnosed. Parsed
`PlaybackInstrument.volumeEnvelope` points are mapped to the existing
frame-based `MixerEnvelope` representation for bounded offline adapted renders
when a playable sample voice is emitted. The bounded offline path now includes
a conservative first pass for volume-envelope sustain frames, envelope loop
frames, note value `97` key-off release, and instrument fadeout after key-off.
These semantics are deterministic and diagnosed, but they are still
approximations rather than full FT2/OpenMPT envelope parity.
Runtime playback still uses `AVAudioPlayerNode` through the existing playback
path; the C mixer is still not used for live playback, and full real XM playback
through the C mixer has not been implemented.

The bounded offline C mixer uses fixed deterministic voice storage. Scheduled
and active voices currently share one preallocated C pool with capacity 256;
there is no separate active-voice stealing policy, and render calls do not
allocate additional voice storage. Event-coverage diagnostics distinguish the
configured scheduled capacity, active capacity, accepted scheduled voices,
scheduled-capacity rejects, active-capacity rejects, invalid scheduled voice
rejects, and rejected event coordinates. Scheduled events also report the
current sample-selection method, fallback usage, missing/deferred keymap state,
and capacity rejections so later PRs can target remaining audible gaps with
evidence.
For long/full-song candidate exports, `scheduled_voice_capacity` rejects are
diagnosed separately from active voice pressure because they can indicate that
the helper attempted to schedule too much of the future song into the fixed C
scheduled-event pool at once. That is the chunked/windowed offline scheduling
problem, not a reason to keep increasing C capacity or change audio behavior.
The developer-only bounded XM render helper now has an explicit
`--window-rows` mode for long local candidate WAV exports. That mode keeps the
C mixer offline-only, plans the bounded range through the existing Swift
adapter, schedules one row window into a fresh C mixer at a time, renders that
window, appends deterministic PCM, and aggregates scheduled-capacity diagnostics
across windows.

Windowed rendering is not full runtime playback or full XM traversal parity.
Runtime playback remains `AVAudioPlayerNode` / `AVAudioUnitVarispeed`, and the
app Play button is not wired to the C mixer. The first-pass windowed helper does
not serialize active C mixer voices, sample playback position, envelope
position, or fadeout state across window boundaries, so sustained voices may be
cut at a boundary. Rows and note events contained wholly within a window retain
the existing bounded adapter behavior.

Bounded adapter diagnostics now also identify pattern traversal and timing
hazards without changing render behavior. The diagnostics count `Bxx` position
jump, `Dxx` pattern break, `EEx` pattern delay, `Fxx` speed/BPM timing changes
for context, and other observed `E` subcommands. Each reported command includes
source order/pattern/row/channel coordinates, raw effect type/parameter, a
friendly decoded label, and a status such as applied, ignored/no-op,
deferred/unsupported, or unknown. `Bxx`, `Dxx`, and `EEx` remain
diagnostic/deferred only in this PR; bounded renders still flatten the requested
order range and do not perform effect-driven traversal, pattern breaks, or
pattern delays.

The C-backed offline mixer now renders fractional source-sample positions with
simple deterministic linear interpolation. Integer source positions still read
the exact source sample, no-loop samples clamp safely at the final frame before
stopping, forward loops interpolate across the exclusive loop-end wrap, and
ping-pong loops interpolate safely through turnarounds. This is a bounded
offline resampling foundation only; it is not full OpenMPT/MikMod resampler
parity and does not add runtime playback settings.

## Current Parsed Playback Model

`PlaybackSongBuilder` is the current app-side bridge from
`ParsedModuleMetadata` into playback-ready Swift structures. It accepts XM
metadata only, requires decoded XM patterns, filters the order table to entries
that reference decoded patterns, loads XM sample PCM from the module path when
available, and copies the XM header's default tempo/BPM into
`PlaybackSong.initialTiming`.

The parsed playback model owns XM-shaped song structure and runtime playback
decisions:

| Type | Current responsibility |
| --- | --- |
| `PlaybackSong` | Playback-facing XM song model: title, order list, pattern lookup, instrument lookup, restart/end behavior, initial timing, and linear-frequency-table flag. It can resolve start positions, rows, samples, instruments, and simple next-row/order stepping. |
| `PlaybackOrderEntry` | One playable order entry after builder filtering. It maps an order index to a decoded pattern index. |
| `PlaybackPattern` | One decoded pattern with a stable pattern index and ordered rows. |
| `PlaybackRow` | One row index plus per-channel `PlaybackCell` values. |
| `PlaybackCell` | Raw XM cell fields: note, instrument, volume column, effect type, and effect parameter. Empty note is `0`; note-off is `97`; normal note triggers are `1...96`. |
| `PlaybackInstrument` | App-side instrument container with samples, a parsed XM 96-note sample map when present, and a parsed volume envelope. The bounded offline adapter uses the map for valid multi-sample triggers and falls back safely otherwise. |
| `PlaybackSample` | Decoded mono Float32 PCM plus sample volume, relative note, finetune, base sample rate, sample length, and loop metadata in sample frames. It exposes `isPlayable` and a clamped `loopRegion`. |
| `PlaybackVolumeEnvelope` | Parsed XM volume envelope points, flags, sustain/loop indices, and fadeout. Runtime AVAudio playback has first-pass envelope state; the C-backed bounded offline adapter consumes enabled volume-envelope point shapes plus first-pass sustain, loop, key-off, and fadeout metadata for bounded offline renders only. |
| `PlaybackTiming` | XM-style timing values. Tick duration is `2.5 / bpm`; row duration is tick duration times clamped speed. |
| `PlaybackEffect` types | Runtime playback effect decoding and channel/global state for the current AVAudio path. These are not part of the first adapter scope. |
| `PlaybackEngine` | Current live playback orchestrator. It advances rows/ticks on a timer, applies first-pass effects and volume-column behavior, triggers `PlaybackAudioOutput`, and writes playback traces. It still uses the AVAudio backend for live playback. |

Layer ownership today:

- `ModuleCore` and the existing Swift loader parse module metadata/patterns
  under ADR 001's hybrid parser policy.
- `PlaybackSongBuilder` shapes decoded XM metadata into a playback-facing Swift
  model.
- `PlaybackEngine` owns current live order/row/tick traversal, effect state, and
  AVAudio triggering.
- The C mixer owns only offline hot-path sample rendering for explicitly
  scheduled synthetic voices.

## Current Synthetic Timing and Mixer Model

The synthetic layer is deliberately smaller than the parsed playback model. It
does not know about XM orders, instruments, effects, volume columns, note
periods, or parser structures.

| Type | Current responsibility |
| --- | --- |
| `SyntheticTrackerTimingConfig` | Constant speed/BPM/sample-rate configuration for offline row/tick scheduling. Values are sanitized like `PlaybackTiming`; invalid sample rates fall back to the mixer default. |
| `SyntheticTrackerTiming` | Deterministic row/tick-to-absolute-frame conversion using `PlaybackTiming`'s XM-style tick formula and floor rounding. |
| `SyntheticTrackerEvent` | One flat synthetic event: row, tick, mono sample buffer, gain, pan, playback step, loop metadata, and optional synthetic volume/pan envelopes. |
| `SyntheticTrackerScheduler` | Stateless Swift helper that converts synthetic events to absolute frames and calls `CSoftwareMixer.addScheduledVoice`. |
| `SyntheticPattern` | Tiny flat pattern container with a row count and synthetic events. It filters events outside the row range. It is intentionally not an XM pattern model. |
| `SyntheticPatternScheduler` | Swift helper that schedules a `SyntheticPattern` through `SyntheticTrackerScheduler`. |
| `MixerSampleBuffer` | Sanitized mono Float32 sample buffer used by Swift and C-backed mixer tests. |
| `MixerSampleLoop` | Synthetic loop mode and exclusive start/end frames. Invalid loops sanitize to no loop. |
| `MixerEnvelope` | Synthetic frame-based envelope copied into C voice storage. Parsed XM volume envelope points are mapped into this shape for bounded offline adapted renders only. |
| `CSoftwareMixer` | Thin Swift wrapper around MixerCore. It copies sample PCM and envelopes into C-owned voice storage, schedules voices at absolute frames, renders deterministic interleaved Float32 offline blocks, and supports reset/clear operations. It is not connected to live playback. |
| `MixerCore` C API | Fixed-size C mixer state and voice storage for deterministic offline one-shot, forward-loop, ping-pong-loop, simple linear interpolation, envelope, pan, and absolute-frame scheduled rendering. |

Layer ownership in the synthetic path:

- Swift owns row/tick scheduling and any future parsed-song traversal.
- `CSoftwareMixer` owns Swift-to-C copying and narrow render calls.
- MixerCore owns only low-level deterministic sample/voice rendering.

## Adapter Boundary

`PlaybackSongSyntheticAdapter` converts from the existing `PlaybackSong` model
into the existing synthetic scheduling model without claiming full XM
compatibility.

The adapter produces an offline render plan rather than rendering directly:

```text
PlaybackSongSyntheticAdapter
  input: PlaybackSong, bounded order range, output sample rate
  output: SyntheticTrackerTimingConfig, SyntheticPattern, diagnostics
```

The synthetic pattern should flatten the requested order range into one
bounded row timeline. For each included playback row, the adapter can map:

```text
flattenedSyntheticRow = rowsBeforeCurrentOrder + PlaybackRow.index
```

Diagnostics should preserve enough source mapping for tests and debugging, for
example:

```text
synthetic row -> PlaybackPosition(orderIndex, patternIndex, rowIndex)
```

Boundary rules:

- The adapter remains Swift orchestration.
- Parser logic stays out of the adapter and out of C.
- Pattern/order traversal stays in Swift and does not move into MixerCore.
- MixerCore receives only copied PCM, gain, pan, playback step, loop metadata,
  optional synthetic envelopes, and absolute scheduled start frames.
- Runtime playback remains on the existing `PlaybackEngine` and AVAudio backend.
- The adapter is an offline planning/render input path only until a later
  feature-flagged backend switch is explicitly approved.

## Minimal Adapter Scope

The current adapter implementation is intentionally small:

- Use `PlaybackSong.initialTiming` as the first bounded timing state.
- Apply only minimal `Fxx` speed/BPM timing changes from included rows, with
  those changes taking effect on following rows.
- Accept one order or an explicit bounded order range.
- Flatten decoded `PlaybackPattern` rows into a single `SyntheticPattern`.
- Schedule only basic note + instrument cells.
- Treat notes `1...96` as triggers with a minimal deterministic playback step,
  `0` as empty, `97` as a channel-local key-off for the most recently adapted
  active voice on that channel when one is tracked, and other values as ignored.
- Select a sample from `PlaybackInstrument.noteSampleMap` for normal notes
  `1...96` when a valid multi-sample map is present; otherwise use the existing
  first-playable-sample fallback.
- Copy `PlaybackSample.pcm` into `MixerSampleBuffer`.
- Use `PlaybackSample.volume` as base event gain, multiplying it by the current
  Swift-side adapter channel volume. Supported set-volume and volume slide
  commands update that channel volume at row-planning time and clamp it to
  `0...64`.
- Map `PlaybackSample.loopRegion` to `.none`, `.forward`, or `.pingPong`.
- Use a neutral pan default, or update Swift-side adapter channel panning from
  supported set-panning and panning slide commands at row-planning time. The
  resulting pan is clamped to the existing `-1.0...1.0` C mixer convention.
- Schedule triggers at tick `0` of each source row.
- Render only tiny bounded offline segments in tests.
- Use synthetic or redistribution-safe parsed fixtures, or tiny hand-built
  `PlaybackSong` fixtures.

Sample selection fallback policy:

- Single-sample instruments preserve the previous first-playable behavior.
- Missing sample maps fall back to the first playable sample and are diagnosed
  as `first_playable_fallback`.
- Valid mapped playable samples are diagnosed as `sample_map`.
- Mapped sample indices that are out of bounds or refer to non-playable/empty
  samples fall back to the first playable sample when one exists and are
  diagnosed as `fallback_after_invalid_map`.
- If no valid sample exists after map lookup and fallback, the trigger is
  skipped safely and diagnosed as `skipped_no_valid_sample`.
- Selected mapped samples keep their own PCM, volume, relative note, finetune,
  base sample rate, loop metadata, and volume envelope behavior.

Important limitation: the adapter now makes note values affect source stepping
for linear-frequency songs, but it still should not claim full FT2/OpenMPT
parity. The current C-backed scheduled voice path advances by a deterministic
fractional source-sample step per output frame and uses simple deterministic
linear interpolation for fractional source positions. This improves bounded
offline render quality for non-integer steps, but it is still not a full
reference-matching resampler architecture.

The current adapter does not:

- switch live playback to the C mixer
- wire the app's Play button into the C mixer
- implement effect-column commands other than minimal `Fxx` speed/BPM timing
  and minimal nonzero `9xx` sample offset
- implement full XM volume-column parity
- implement tick-level volume-column slide ramps
- implement full tempo/BPM or tick-level timing effect parity
- implement pattern break, position jump, or pattern delay
- implement `9xx` effect memory for `900`
- implement note delay, note cut, or retrigger behavior
- implement Amiga-table period/frequency behavior or pitch-changing effects
- implement full OpenMPT/MikMod resampler parity or configurable interpolation modes
- provide full runtime playback, full-song traversal parity, or a public
  module-rendering CLI; `vtx_render_bounded_xm --window-rows` remains a
  developer/offline long candidate helper
- use private/local XM modules in automated tests

## Data Mapping

| Playback model field | Synthetic/mixer target | First adapter behavior | Deferred behavior |
| --- | --- | --- | --- |
| `PlaybackSong.initialTiming.speed` | Swift timing plan and initial `SyntheticTrackerTimingConfig.speed` | Use as the initial bounded speed; `F01...F1F` updates speed for following rows. | Full tick-level speed semantics later. |
| `PlaybackSong.initialTiming.bpm` | Swift timing plan and initial `SyntheticTrackerTimingConfig.bpm` | Use as the initial bounded BPM; `F20...FFF` as byte parameters `0x20...0xFF` updates BPM for following rows. | Full tempo/BPM effect parity later. |
| `PlaybackSong.usesLinearFrequencyTable` | Adapter diagnostics and pitch-step status | Preserve in diagnostics. Linear songs use explicit XM linear-period to frequency to sample-step conversion. Non-linear songs report Amiga-table behavior as deferred and use a neutral step fallback. | Full Amiga period/frequency behavior later. |
| `PlaybackSong.orders` | Bounded flattened synthetic row timeline | Traverse one order or explicit bounded order range in Swift. | Full song traversal, restart behavior, `Bxx`, and `Dxx` later. |
| `PlaybackOrderEntry.patternIndex` | Pattern selection | Resolve each included order to `PlaybackPattern`. Skip or fail safely on missing patterns. | Effect-driven position changes later. |
| `PlaybackPattern.rows` | `SyntheticPattern.rowCount` and flattened events | Sum included pattern row counts into one flat synthetic pattern. | Pattern delay and richer order timeline later. |
| `PlaybackRow.index` | `SyntheticTrackerEvent.row` | Map to flattened row offset plus row index. | Pattern delay and row-repeat semantics later. |
| `PlaybackCell.note` | Trigger/release decision and playback step | Trigger only for `1...96`, deriving a linear-frequency sample step from note/sample metadata when the song uses the linear frequency table. Note value `97` schedules a key-off/release frame for the active adapted voice on that channel when one is tracked. Empty and invalid notes are ignored safely. | Amiga pitch behavior, note cut/delay, retrigger, and broader effect-triggered release behavior later. |
| `PlaybackCell.instrument` | Sample lookup and event coverage diagnostics | Resolve the selected instrument, then choose a mapped sample from the parsed XM 96-note sample map for normal notes `1...96` when a valid multi-sample mapping exists. Fall back safely to the first playable sample when no useful mapping exists, or skip when no valid sample can be selected. Diagnostics distinguish missing zero instruments, unknown instruments, empty sample PCM, invalid/non-playable map targets, selected sample index/length/loop mode, sample-map selection, fallback-after-invalid-map, first-playable fallback, and skipped-no-valid-sample cases. | Previous-instrument semantics and richer FT2/OpenMPT edge cases later. |
| `PlaybackCell.volumeColumn` | Event gain/pan and diagnostics | Apply set-volume (`0x10...0x50`), volume slide down/up (`0x60...0x7F`), fine volume slide down/up (`0x80...0x9F`), set-panning (`0xC0...0xCF`), and panning slide left/right (`0xD0...0xEF`) as row-level Swift adapter state updates. Events emitted on that row use the post-command state. Diagnostics report raw value, decoded command, applied/deferred state, slide amount/direction, effective volume/pan before/after when applicable, source order/pattern/row/channel, and synthetic row/tick. | Tick-level ramps, effect memory, vibrato, tone portamento, undefined ranges, and full volume-column parity later. |
| `PlaybackCell.effectType` / `PlaybackCell.effectParam` | Swift timing plan for `Fxx` and event source offset for nonzero `9xx` | Apply minimal `Fxx` speed/BPM changes to following bounded rows; diagnose `F00` as ignored/no-op. Apply nonzero `9xx` only when a same-cell note/sample trigger emits a bounded offline event, using `xx * 256` source sample frames as the initial source position. Diagnose `900` as ignored/deferred/no-op. Diagnose out-of-range offsets and skip that voice deterministically. Keep other effect-column commands deferred. | Targeted effect integration PRs later, including `9xx` memory if needed. |
| `Bxx` / `Dxx` / `EEx` effect commands | Traversal hazard diagnostics | Count and report coordinates/status only. These commands are classified as deferred/unsupported and summarized as traversal hazards when present in the bounded range. | Minimal bounded traversal implementation for position jump, pattern break, and pattern delay later. |
| `PlaybackInstrument.samples` / `noteSampleMap` | Sample selection source | Use `noteSampleMap[note - 1]` for normal XM notes when the instrument has a usable multi-sample map and the mapped sample is playable; otherwise apply the documented first-playable fallback/skip policy. | Previous-instrument behavior and richer instrument edge cases later. |
| `PlaybackInstrument.volumeEnvelope` | `MixerEnvelope` and voice key-off/fadeout metadata on `SyntheticTrackerEvent` | Convert enabled, valid volume envelope points to frame-based mixer points using the timing active for the event row and the render sample rate. If valid parsed sustain/loop flags and point indices are present, pass mapped sustain and loop frames to the C mixer. If note value `97` later appears on the same adapted channel, pass an absolute release frame and a simple fadeout decrement. Diagnostics record absent, disabled, invalid/empty, mapped, applied, deferred, and approximated states. | Full FT2/OpenMPT envelope parity, panning envelopes, and dynamic envelope retiming after later tempo changes. |
| `PlaybackSample.pcm` | `MixerSampleBuffer` / C-owned voice sample storage | Copy mono Float32 PCM through `MixerSampleBuffer` and `CSoftwareMixer`. | Ownership optimization and reuse/caching later. |
| `PlaybackSample.volume` | `SyntheticTrackerEvent.gain` | Use as base gain and multiply by the current adapter channel volume after supported row-level volume-column commands. Parsed volume envelopes and post-key-off fadeout remain separate mixer multipliers at render time. | Global volume state and full effect integration later. |
| `PlaybackSample.relativeNote` / `finetune` / `baseSampleRate` | Synthetic event playback step and diagnostics | Use base sample rate, relative note, and clamped finetune in the XM linear-period calculation for linear-frequency songs. Diagnostics include output sample rate, effective note/finetune, linear period/frequency, and neutral fallback status. | Amiga table behavior and pitch-changing effects later. |
| `PlaybackSample.loopRegion` | `MixerSampleLoop` | Map disabled to `.none`, loop type `1` to `.forward`, and loop type `2` to `.pingPong`. Let C-side sanitization reject unsafe loops. A valid nonzero `9xx` starts the C voice at the requested source sample frame before normal stepping/loop behavior continues. | FT2 loop quirks and richer sample-offset memory/interactions later. |
| `PlaybackVolumeEnvelope.points` / flags / fadeout | `MixerEnvelope` and voice release/fadeout state | Convert enabled, valid volume envelope points to frame-based mixer points using the timing active for the event row. Sustain holds at the mapped sustain frame while keyed-on. Envelope loops repeat between mapped loop start/end frames while keyed-on. Note value `97` releases the tracked adapted voice and allows envelope advance/fadeout. Fadeout uses a linear per-frame decrement derived from the parsed fadeout value as a first-pass approximation. | Full FT2/OpenMPT envelope parity, panning envelopes, effect-column note cut/delay/retrigger, and dynamic envelope retiming after later tempo changes. |

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Scope expands into full XM playback. | The bounded adapter supports initial timing plus minimal `Fxx`, minimal nonzero `9xx`, bounded orders, note triggers, sample-map/keymap selection with fallback, gain, pan default, row-level volume/panning state, and loops only. Everything else is documented as deferred. |
| Accidental runtime backend switch. | Keep adapter under offline/test harness paths. Do not touch `PlaybackEngine`, `PlaybackAudioEngine`, transport wiring, or AppKit controls in the adapter PR. |
| Parser architecture drift. | Adapter consumes `PlaybackSong` only. It must not parse files, change `ModuleCore`, or move Swift parser responsibilities. |
| Incorrect note-to-frequency behavior. | The adapter labels linear-frequency support explicitly and keeps Amiga behavior deferred. Tests cover monotonic linear steps, octave sanity, relative note, finetune, base/output sample rates, neutral fallback, split/reset determinism, and explicit Amiga-table deferral without claiming full FT2/OpenMPT parity. |
| Sample ownership and copying between Swift and C. | Continue using `MixerSampleBuffer` and `CSoftwareMixer` copied storage. Defer caching/ownership optimization. |
| Instrument/sample selection complexity. | Keep selection inside the bounded adapter and `PlaybackInstrument` model. Use parsed XM note-sample maps only when already carried by `PlaybackSong`; validate mapped indices and fall back or skip deterministically. Do not move parser ownership or implement broader instrument fallback semantics. |
| Full volume-column and effect semantics may be mistaken as supported. | Apply only set-volume, set-panning, volume slides, fine volume slides, and panning slides in the bounded adapter. Keep these as row-level approximations, defer vibrato/tone-portamento/effect-column behavior in diagnostics except the explicitly documented `Fxx` and nonzero `9xx` cases, and document compatibility limits in test names. |
| Timing or sample-offset support is mistaken for full effect parity. | Apply only minimal `Fxx` speed/BPM timing changes to following bounded rows and minimal nonzero `9xx` source starts on same-cell note triggers. Diagnose `F00`, `900`, out-of-range offsets, and all other effect-column commands without adding broad effect state. |
| Local/private module temptation. | Keep private/local XM modules manual-only and outside the repo. Automated tests use hand-built songs or redistribution-safe fixtures. |
| Synthetic tests are confused with real compatibility. | Test names and docs should say "adapter smoke" or "bounded offline render", not "XM parity". Reference comparison remains later. |
| C voice limit is too small for dense rows. | The offline C mixer now uses a 256-voice fixed pool for scheduled/active voices. Treat scheduled-event pool exhaustion separately from active voice pressure, especially in long renders that schedule too much future material up front. Keep any later increases or chunked/windowed scheduling focused and deterministic, with no heap allocation in the render hot path. |
| Local listening suggests missing notes before the C mixer. | Event-coverage diagnostics compare parsed normal note cells with scheduled C-backed events, report skipped coordinates and reasons, and expose scheduled/active capacity values plus rejected event coordinates without changing runtime playback. |

## Test Strategy For Adapter PRs

Adapter implementation PRs use focused tests around adapter output and
bounded offline rendering:

- Use tiny hand-built `PlaybackSong` fixtures when a full parser fixture is not
  needed.
- Use redistribution-safe parser fixtures only when parser integration itself is
  being validated.
- Do not use private/local XM modules in automated tests.
- Do not commit generated audio, WAV files, traces, screenshots, or comparison
  reports.
- Assert adapter timing uses `PlaybackSong.initialTiming.speed` and `.bpm`.
- Assert rows from a bounded order range map to expected synthetic rows.
- Assert silence before expected row-derived trigger frames.
- Assert non-silence begins at expected row-derived frames.
- Assert empty cells, missing instruments, non-playable samples, invalid notes,
  and key-off-without-active-voice cases are ignored or deferred safely.
- Assert sample volume maps to gain.
- Assert forward and ping-pong loop metadata reaches the already-tested C loop
  path.
- Assert parsed volume envelope points map to frame-based mixer envelope points
  using the timing active at the event row.
- Assert disabled, empty, and invalid parsed volume envelopes are ignored safely.
- Assert parsed volume envelope sustain points hold while keyed-on.
- Assert parsed volume envelope loops repeat while keyed-on.
- Assert note value `97` releases the tracked adapted channel voice and reports
  applied/deferred key-off diagnostics.
- Assert parsed instrument fadeout reduces output after key-off.
- Assert supported set-volume, set-panning, volume slide, fine volume slide, and
  panning slide volume-column fields affect bounded offline output and
  diagnostics.
- Assert unsupported volume-column commands and effect-column fields remain
  deferred/ignored in the adapter.
- Assert minimal `Fxx` speed/BPM changes affect following row start frames and
  diagnostics, while `F00` is ignored safely.
- Assert nonzero `9xx` starts same-cell note/sample triggers at `xx * 256`
  source sample frames, preserving pitch step, interpolation, loops,
  volume-column state, and parsed volume-envelope behavior.
- Assert `900` is diagnosed as ignored/deferred/no-op and that out-of-range
  `9xx` offsets skip the voice safely with deterministic silence.
- Assert single-sample instruments preserve first-playable behavior.
- Assert multi-sample instruments with note-sample maps select different
  samples for different notes.
- Assert mapped sample volume, relative note, finetune, base sample rate, loop
  metadata, parsed envelope behavior, volume-column state, `Fxx` timing, and
  nonzero `9xx` offsets are applied using the selected mapped sample.
- Assert invalid mapped indices and mapped empty PCM are diagnosed and fall back
  or skip according to the documented policy.
- Assert missing sample maps fall back to first playable samples without losing
  normal notes unexpectedly.
- Assert event coverage counts visited cells, normal notes, note-offs, scheduled
  notes, skipped notes, and skip reasons without changing render output.
- Assert scheduled and skipped note diagnostics include source
  order/pattern/row/channel coordinates and sample-selection metadata.
- Assert capacity diagnostics report scheduled and active capacity values.
- Assert C mixer scheduled voice capacity rejections and rejected coordinates
  are reported when a synthetic fixture exceeds the fixed voice limit.
- Assert dense synthetic fixtures above the former 32-voice limit and below the
  current 256-voice limit schedule without capacity rejects.
- Assert traversal hazard diagnostics count `Bxx`, `Dxx`, and `EEx`, preserve
  source coordinates, classify them as deferred/unsupported, and keep `Fxx`
  classified as applied or ignored/no-op according to the existing timing
  support.
- Assert traversal diagnostics do not change rendered PCM output.
- Assert windowed long candidate renders reuse scheduled-event capacity across
  deterministic row windows and aggregate per-window accepted/rejected counts.
- Assert windowed single-window renders match the existing non-windowed bounded
  output where practical.
- Assert note/sample metadata produces deterministic playback steps while a
  neutral step preserves one-source-frame-per-output-frame behavior.
- Assert split render determinism for the scheduled output.
- Assert reset determinism for the scheduled output.
- Keep any WAV comparison local and ignored until a later WAV/export workflow
  exists.

## Proposed PR Sequence After This Planning PR

1. Done: minimal `PlaybackSong` to synthetic adapter: constant initial speed/BPM,
   bounded order range, basic note/instrument/sample triggers, sample volume,
   loop metadata, no effects, offline tests only.
2. Done: adapter diagnostics and bounded offline render helper for parsed
   `PlaybackSong` segments, still using redistribution-safe fixtures only.
3. Done: parsed volume envelope point mapping for bounded offline adapted
   `PlaybackSong` renders, using the existing C-backed frame-based envelope
   behavior and reporting sustain/loop/fadeout as deferred.
4. Done: minimal note-to-sample-step pitch foundation for bounded offline
   adapted renders, still without full FT2/OpenMPT parity.
5. Deep project handoff checkpoint covering the software mixer transition,
   C-backed mixer path, synthetic scheduling, adapter bridge, and next roadmap.
6. Done: local-only reference render workflow against MikMod/OpenMPT once
   bounded parsed offline renders exist.
7. Done: targeted minimal `Fxx` speed/BPM timing changes for bounded offline
   adapted renders.
8. Done: conservative volume-column set-volume/set-panning integration for
   bounded offline adapted renders.
9. Done: conservative row-level volume-column volume/panning slide integration
   for bounded offline adapted renders.
10. Done: focused pitch/period accuracy pass for bounded linear-frequency
    sample-step behavior and diagnostics, with Amiga behavior still deferred.
11. Done: simple deterministic linear interpolation for fractional C-backed
    offline mixer sample steps, without runtime backend changes or full
    resampler parity.
12. Done: first-pass volume-envelope sustain/loop/key-off/fadeout semantics for
    bounded offline adapted renders, with deterministic diagnostics and
    documented approximations.
13. Done: minimal nonzero `9xx` sample offset for bounded offline adapted
    renders, with `900` diagnosed as ignored/deferred/no-op and out-of-range
    offsets skipped safely.
14. Done: bounded adapter event coverage and missing-note trigger diagnostics,
    reporting parsed normal notes, scheduled events, skipped notes, skip
    reasons, sample-selection fallback, and C mixer capacity rejections without
    changing audio behavior.
15. Done: bounded offline instrument sample-map/keymap selection, reporting
    sample-map selections, first-playable fallbacks, invalid-map fallbacks, and
    skipped-no-valid-sample cases without runtime backend changes.
16. Done: C mixer scheduled voice capacity / diagnostics hardening, increasing
    the fixed offline scheduled/active voice pool to 256 and reporting capacity
    values plus rejected event coordinates without runtime backend changes.
17. Done: pattern traversal and timing hazard diagnostics for bounded offline
    renders, counting `Bxx`, `Dxx`, `EEx`, contextual `Fxx`, and other observed
    `E` subcommands without implementing traversal behavior.
18. Done: chunked/windowed offline render scheduling for long developer
    candidate WAV exports, reusing fixed C scheduled-event capacity across
    deterministic row windows with aggregate diagnostics and documented
    window-boundary state limitations.
19. Additional targeted effects such as note delay/cut, retrigger, arpeggio,
   portamento, vibrato, pattern break, and position jump.
20. Feature-flagged runtime C mixer backend switch only after offline parity and
   diagnostics are strong enough to justify runtime risk.

## Envelope Semantics First Pass

This bounded offline adapter pass supports only volume-envelope semantics:

- Enabled parsed volume envelope point shapes are still mapped to frame-based C
  mixer points using the timing active at the note event row.
- If the parsed sustain flag and sustain point index are valid, the C mixer holds
  the envelope at the mapped sustain frame while the adapted voice remains
  keyed-on.
- If the parsed envelope loop flag and loop point indices are valid, the C mixer
  loops between mapped loop start/end frames while the adapted voice remains
  keyed-on.
- XM note value `97` schedules a key-off/release frame for the currently tracked
  adapted voice on the same channel. If no active adapted voice is tracked, the
  key-off is diagnosed as deferred/no-active-voice.
- Parsed instrument fadeout is applied after key-off with a simple deterministic
  linear per-output-frame decrement. This is intentionally documented as a
  first-pass approximation, not exact FT2/OpenMPT fadeout parity.

Panning envelopes remain deferred. Effect-column note cut (`ECx`), note delay
(`EDx`), retrigger (`E9x`), global volume, pattern break, position jump,
pattern delay, `9xx` effect memory, and runtime playback integration remain out
of scope. Runtime playback remains on `AVAudioPlayerNode` /
`AVAudioUnitVarispeed`, and the C mixer remains offline-only.

## Manual Verification Strategy

For the original planning PR:

- Review this document against the listed source files and ADRs.
- Run `./scripts/check-files.sh`.
- Run `git diff --check`.
- Confirm no Swift, C, project, fixture, generated audio, trace, screenshot, or
  tracker viewport files changed.

For the first adapter implementation PR:

- Run focused adapter and C mixer tests.
- Render a tiny bounded segment from a hand-built or redistribution-safe
  `PlaybackSong` fixture through the C-backed offline mixer.
- Confirm the render is silent before the first row-derived trigger and
  non-silent at the expected trigger frame.
- Confirm split renders and reset renders are deterministic.
- Manually inspect adapter diagnostics that map synthetic rows back to
  `PlaybackPosition`.
- Keep local module experiments, WAVs, traces, and comparison reports outside
  the repository.

## Explicit Non-Goals

This adapter bridge work does not:

- change runtime playback behavior
- switch runtime playback to the C mixer
- wire real parsed XM modules into live C mixer playback
- implement full XM playback
- implement XM effect-column commands other than minimal `Fxx` speed/BPM timing
  and minimal nonzero `9xx` sample offset
- implement full Amiga period/frequency behavior
- implement full OpenMPT/MikMod resampler parity or runtime interpolation controls
- implement `9xx` effect memory for `900`
- implement note delay, note cut, or retrigger
- implement global volume
- add dynamic/unbounded mixer allocation or voice stealing
- implement full volume-column semantics beyond set-volume, set-panning, and
  the supported row-level volume/panning slide subset
- implement pattern break or position jump
- implement full tempo/BPM timing semantics beyond minimal bounded `Fxx`
- provide full-song WAV export or a public module-rendering CLI
- provide window-state serialization across row-window boundaries in the
  first-pass developer helper
- delete or rewrite the Swift `SoftwareMixer`
- refactor parser architecture
- touch tracker viewport/rendering behavior
- commit private/local XM modules
- add generated WAV files, traces, screenshots, or comparison reports
