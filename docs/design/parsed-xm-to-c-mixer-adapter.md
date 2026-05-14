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
playback, implement XM effects, or add WAV export.

## Implementation Status

PR 2.7.10 added `PlaybackSongSyntheticAdapter`, a Swift-side offline adapter
that converts an explicit bounded order selection from `PlaybackSong` into a
`SyntheticTrackerTimingConfig`, `SyntheticPattern`, and diagnostics. It uses
constant initial speed/BPM only, emits basic note/instrument/sample triggers at
tick 0, copies sample PCM into `MixerSampleBuffer`, maps sample volume to event
gain, maps disabled/forward/ping-pong sample loops into the existing synthetic
loop metadata, and now carries a minimal deterministic note/sample-derived
playback step into the C-backed scheduled voice path.

The follow-up bounded offline render helper now adapts tiny `PlaybackSong`
segments, schedules the adapted synthetic pattern through `CSoftwareMixer`, and
returns the in-memory `MixerRenderBlock` with source-to-synthetic diagnostics.
Those diagnostics record the requested order range, sample rate, initial
speed/BPM, synthetic rows/events, skipped or empty rows, ignored cells, deferred
effect and volume-column fields, source order/pattern/row/channel coordinates,
synthetic row/tick coordinates, selected instrument/sample identifiers, and
mapped loop mode. Oversized frame requests are clamped to a conservative maximum
before rendering.
Pitch diagnostics include the source note, selected sample base sample rate,
sample relative note, finetune status, song linear-frequency flag, frequency
table status, calculated playback step, and whether mapping used the neutral
default step.

The adapter and helper are still intentionally not full pitch parity. Linear
frequency songs use a small deterministic equal-tempered note-to-step mapping
based on sample base rate, note value, relative note, and finetune. Amiga table
behavior is not implemented; non-linear songs are reported as using a deferred
Amiga-table path with the same minimal linear approximation. XM effects are
ignored, volume columns are ignored, and tempo changes after initial timing are
ignored. Parsed `PlaybackInstrument.volumeEnvelope` points are mapped to the
existing frame-based `MixerEnvelope` representation for bounded offline adapted
renders when a playable sample voice is emitted. Sustain, loop, key-off, and
fadeout envelope semantics remain deferred and are reported in diagnostics when
present. Runtime playback still uses `AVAudioPlayerNode` through the existing
playback path; the C mixer is still not used for live playback, and full real XM
playback through the C mixer has not been implemented.

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
| `PlaybackInstrument` | App-side instrument container with samples and a parsed volume envelope. Current sample selection is `firstPlayableSample`. |
| `PlaybackSample` | Decoded mono Float32 PCM plus sample volume, relative note, finetune, base sample rate, sample length, and loop metadata in sample frames. It exposes `isPlayable` and a clamped `loopRegion`. |
| `PlaybackVolumeEnvelope` | Parsed XM volume envelope points, flags, sustain/loop indices, and fadeout. Runtime AVAudio playback has first-pass envelope state; the C-backed bounded offline adapter now consumes the basic enabled volume envelope shape only. |
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
| `MixerCore` C API | Fixed-size C mixer state and voice storage for deterministic offline one-shot, forward-loop, ping-pong-loop, envelope, pan, and absolute-frame scheduled rendering. |

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

- Use constant initial speed/BPM from `PlaybackSong.initialTiming`.
- Accept one order or an explicit bounded order range.
- Flatten decoded `PlaybackPattern` rows into a single `SyntheticPattern`.
- Schedule only basic note + instrument cells.
- Treat notes `1...96` as triggers with a minimal deterministic playback step,
  `0` as empty, `97` as deferred key-off, and other values as ignored.
- Select `PlaybackInstrument.firstPlayableSample`.
- Copy `PlaybackSample.pcm` into `MixerSampleBuffer`.
- Use `PlaybackSample.volume` as event gain.
- Map `PlaybackSample.loopRegion` to `.none`, `.forward`, or `.pingPong`.
- Use a neutral pan default, or the existing tracker default panning only if
  that is trivial and testable without importing effect semantics.
- Schedule triggers at tick `0` of each source row.
- Render only tiny bounded offline segments in tests.
- Use synthetic or redistribution-safe parsed fixtures, or tiny hand-built
  `PlaybackSong` fixtures.

Important limitation: the adapter now makes note values affect source stepping,
but it still should not claim FT2/OpenMPT pitch parity. The current C-backed
scheduled voice path advances by a deterministic fractional source-sample step
per output frame without interpolation.

The current adapter does not:

- switch live playback to the C mixer
- wire the app's Play button into the C mixer
- implement effects or volume-column semantics
- implement tempo/BPM changes after the initial timing
- implement pattern break, position jump, or pattern delay
- implement sample offset
- implement note delay, note cut, retrigger, or key-off behavior
- implement full FT2/OpenMPT period/frequency behavior
- add WAV export
- use `_DARKL.XM` in automated tests

## Data Mapping

| Playback model field | Synthetic/mixer target | First adapter behavior | Deferred behavior |
| --- | --- | --- | --- |
| `PlaybackSong.initialTiming.speed` | `SyntheticTrackerTimingConfig.speed` | Use constant speed for the bounded render. | `Fxx` speed changes later. |
| `PlaybackSong.initialTiming.bpm` | `SyntheticTrackerTimingConfig.bpm` | Use constant BPM for the bounded render. | `Fxx` BPM changes later. |
| `PlaybackSong.usesLinearFrequencyTable` | Adapter diagnostics and pitch-step status | Preserve in diagnostics. Linear songs use the minimal note-to-step mapping; non-linear songs report Amiga-table behavior as deferred while using the same linear approximation. | Full Linear/Amiga period and frequency accuracy pass later. |
| `PlaybackSong.orders` | Bounded flattened synthetic row timeline | Traverse one order or explicit bounded order range in Swift. | Full song traversal, restart behavior, `Bxx`, and `Dxx` later. |
| `PlaybackOrderEntry.patternIndex` | Pattern selection | Resolve each included order to `PlaybackPattern`. Skip or fail safely on missing patterns. | Effect-driven position changes later. |
| `PlaybackPattern.rows` | `SyntheticPattern.rowCount` and flattened events | Sum included pattern row counts into one flat synthetic pattern. | Pattern delay and richer order timeline later. |
| `PlaybackRow.index` | `SyntheticTrackerEvent.row` | Map to flattened row offset plus row index. | Pattern delay and row-repeat semantics later. |
| `PlaybackCell.note` | Trigger decision and playback step | Trigger only for `1...96`, deriving a minimal sample step from note/sample metadata; ignore empty, key-off, and invalid notes. | Full pitch/period accuracy, key-off, note cut/delay, retrigger later. |
| `PlaybackCell.instrument` | Sample lookup | Use `PlaybackSong.sample(forInstrument:)`, currently first playable sample. | Multisample/keymap and instrument fallback semantics later. |
| `PlaybackCell.volumeColumn` | None initially | Ignore. | Volume-column integration PR later. |
| `PlaybackCell.effectType` / `PlaybackCell.effectParam` | None initially | Ignore. | Targeted effect integration PRs later. |
| `PlaybackInstrument.samples` | Sample selection source | Use `firstPlayableSample`. | Keymap, note range, and previous-instrument behavior later. |
| `PlaybackInstrument.volumeEnvelope` | `MixerEnvelope` on `SyntheticTrackerEvent` | Convert enabled, valid volume envelope points to frame-based mixer points using `PlaybackSong.initialTiming` and the render sample rate. Diagnostics record absent, disabled, invalid/empty, and mapped states. | Sustain, loop, key-off, fadeout semantics, and any timing changes after initial speed/BPM. |
| `PlaybackSample.pcm` | `MixerSampleBuffer` / C-owned voice sample storage | Copy mono Float32 PCM through `MixerSampleBuffer` and `CSoftwareMixer`. | Ownership optimization and reuse/caching later. |
| `PlaybackSample.volume` | `SyntheticTrackerEvent.gain` | Use as basic gain. | Combine with channel, global, volume-column, envelope, and fadeout state later. |
| `PlaybackSample.relativeNote` / `finetune` / `baseSampleRate` | Synthetic event playback step and diagnostics | Use base sample rate, relative note, and finetune in the minimal note-to-step calculation; report finetune as applied for valid mappings or deferred on neutral fallback. | Full FT2/OpenMPT note-to-frequency and period behavior later. |
| `PlaybackSample.loopRegion` | `MixerSampleLoop` | Map disabled to `.none`, loop type `1` to `.forward`, and loop type `2` to `.pingPong`. Let C-side sanitization reject unsafe loops. | FT2 loop/sample-offset quirks later. |
| `PlaybackVolumeEnvelope.points` / flags / fadeout | `MixerEnvelope` on `SyntheticTrackerEvent` | Convert enabled, valid volume envelope points to frame-based mixer points using constant initial timing; report sustain, loop, and fadeout as deferred. | Sustain, loop, key-off, fadeout semantics, and timing changes later. |

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Scope expands into full XM playback. | First adapter supports constant timing, bounded orders, note triggers, first playable sample, gain, pan default, and loops only. Everything else is documented as deferred. |
| Accidental runtime backend switch. | Keep adapter under offline/test harness paths. Do not touch `PlaybackEngine`, `PlaybackAudioEngine`, transport wiring, or AppKit controls in the adapter PR. |
| Parser architecture drift. | Adapter consumes `PlaybackSong` only. It must not parse files, change `ModuleCore`, or move Swift parser responsibilities. |
| Incorrect note-to-frequency behavior. | The adapter labels this as a minimal pitch foundation only. Tests cover deterministic relative step behavior, neutral fallback, split/reset determinism, and explicit Amiga-table deferral without claiming FT2/OpenMPT parity. |
| Sample ownership and copying between Swift and C. | Continue using `MixerSampleBuffer` and `CSoftwareMixer` copied storage. Defer caching/ownership optimization. |
| Instrument/sample selection complexity. | Use `firstPlayableSample` exactly like `PlaybackSong.sample(forInstrument:)`. Defer keymaps and multisample selection. |
| Volume-column and effect semantics are deferred but may be mistaken as supported. | Ignore them in code, assert that ignored fields do not change first-adapter output, and document compatibility limits in test names. |
| Tempo changes are deferred. | Use only `PlaybackSong.initialTiming` and add a fixture with an `Fxx` cell that remains ignored in the first adapter. |
| Local `_DARKL.XM` temptation. | Keep `_DARKL.XM` manual-only and outside the repo. Automated tests use hand-built songs or redistribution-safe fixtures. |
| Synthetic tests are confused with real compatibility. | Test names and docs should say "adapter smoke" or "bounded offline render", not "XM parity". Reference comparison remains later. |
| C voice limit is too small for dense rows. | First adapter renders tiny bounded fixtures. Later PRs can schedule in blocks or increase C storage after a focused decision. |

## Test Strategy For Adapter PRs

Adapter implementation PRs use focused tests around adapter output and
bounded offline rendering:

- Use tiny hand-built `PlaybackSong` fixtures when a full parser fixture is not
  needed.
- Use redistribution-safe parser fixtures only when parser integration itself is
  being validated.
- Do not use `_DARKL.XM` in automated tests.
- Do not commit generated audio, WAV files, traces, screenshots, or comparison
  reports.
- Assert adapter timing uses `PlaybackSong.initialTiming.speed` and `.bpm`.
- Assert rows from a bounded order range map to expected synthetic rows.
- Assert silence before expected row-derived trigger frames.
- Assert non-silence begins at expected row-derived frames.
- Assert empty cells, missing instruments, non-playable samples, key-off, and
  invalid notes are ignored safely.
- Assert sample volume maps to gain.
- Assert forward and ping-pong loop metadata reaches the already-tested C loop
  path.
- Assert parsed volume envelope points map to frame-based mixer envelope points
  using constant initial timing.
- Assert disabled, empty, and invalid parsed volume envelopes are ignored safely.
- Assert effects and volume-column fields are ignored in the first adapter.
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
6. Local-only reference render workflow against MikMod/OpenMPT once bounded
   parsed offline renders exist.
7. Targeted timing effect integration, starting with `Fxx` speed/BPM changes.
8. Volume-column integration.
9. Focused pitch/period accuracy pass for full note-to-frequency behavior.
10. Additional targeted effects such as sample offset, note delay/cut,
   retrigger, arpeggio, portamento, vibrato, slides, pattern break, and
   position jump.
11. Feature-flagged runtime C mixer backend switch only after offline parity and
   diagnostics are strong enough to justify runtime risk.

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
- implement XM effects
- implement full FT2/OpenMPT period/frequency behavior
- implement sample offset
- implement note delay, note cut, or retrigger
- implement global volume
- implement volume-column semantics
- implement pattern break or position jump
- implement tempo/BPM changes beyond initial timing
- implement WAV export
- delete or rewrite the Swift `SoftwareMixer`
- refactor parser architecture
- touch tracker viewport/rendering behavior
- commit `_DARKL.XM`
- add generated WAV files, traces, screenshots, or comparison reports
