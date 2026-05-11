# ADR 004: Software Mixer Transition

## Status

Accepted as the target architecture for the next playback accuracy phase.

## Context

VoodooTracker X currently has useful audible XM playback. Timing, speed/BPM,
pattern/order traversal, forward and ping-pong loop approximations, panning,
volume envelopes, fadeout, volume-column behavior, debug seeking, trace export,
and many effects are implemented well enough to make real modules playable.

The accepted first-pass backend decision is documented in
`docs/decisions/002-first-pass-audio-backend.md`. The accepted accuracy model
for current playback is documented in
`docs/decisions/003-first-pass-playback-accuracy.md`. Parser responsibilities
remain governed by `docs/decisions/001-xm-parsing-responsibilities.md`; this
decision does not change parser ownership or refactor the module loader.

The current backend uses `AVAudioEngine`, `AVAudioPlayerNode`, and
`AVAudioUnitVarispeed`. That was the correct choice for the first audible
milestone because it:

- avoided running Swift tracker state logic on the CoreAudio render thread
- gave the project stable Play/Stop behavior quickly
- proved decoded sample triggering through the existing app boundary
- kept tracker follow and playback transport behavior observable
- limited the initial audio scope while parsing and UI code were still moving

That backend has now reached its practical accuracy limit. Real XM playback,
especially for modules such as the local `_DARKL.XM` test module, still differs
audibly from MikMod/OpenMPT around dense transitions such as pattern/order 10
and decimal pattern/order 30. The remaining gap is no longer just missing effect
coverage; it is also caused by the backend model. Scheduled player nodes and
varispeed units do not give VoodooTracker X direct, deterministic ownership of
sample stepping, loop turnarounds, envelope timing, panning math, interpolation,
and tick-to-sample scheduling.

## Decision

Move future playback accuracy work toward a deterministic pull-based software
mixer behind the existing playback/audio boundary.

The `AVAudioPlayerNode` backend remains available until the software mixer is
proven. This decision does not switch runtime playback, remove the first-pass
backend, change playback behavior, touch tracker viewport rendering, or refactor
parser architecture.

## Target Architecture

The mixer should be a deterministic renderer that can run both offline and, once
proven, as the runtime audio source.

Core properties:

- Pull-based rendering: callers request a fixed number of output frames, and
  the mixer fills an output buffer from explicit playback state.
- Fixed output sample rate: start with 44.1 kHz unless a later focused decision
  documents a different default.
- Block-based rendering with sample-accurate internal scheduling: render in
  practical blocks for efficiency, but split blocks at tick, row, note-delay,
  retrigger, note-cut, loop, or other scheduling boundaries when needed.
- Deterministic state: given the same module data, starting position, mixer
  settings, and frame count, offline output and trace events should be
  reproducible.
- Existing boundaries: the mixer belongs behind the current `AudioEngine` /
  playback boundary. UI code should continue to use transport APIs rather than
  owning DSP or scheduling details.

Per-channel voice state should be explicit. Each active channel needs enough
state to describe:

- current instrument/sample and whether the voice is active
- source sample position accumulator, including fractional position
- effective playback step derived from XM period/frequency state
- loop mode, loop start, loop length, and loop direction
- ping-pong turnaround state without duplicated endpoint samples
- channel volume, global volume, fadeout, panning, and envelope position
- effect memory and tick-level modulation that affects rendering
- key-on/key-off, note delay, note cut, retrigger, and replacement behavior

Sample rendering should own the mechanics currently approximated by scheduled
buffers:

- advance sample position with a fractional accumulator
- support no-loop, forward-loop, and ping-pong-loop samples
- clamp or stop safely at sample ends according to XM semantics
- apply a documented interpolation strategy
- initially prefer a simple deterministic interpolation mode, then add
  configurable or reference-matching interpolation only after baseline behavior
  is testable
- apply volume, panning, envelopes, fadeout, and global volume inside the mixer
  rather than through AVAudio node parameters

Timing integration should connect the existing row/tick playback model to the
mixer without duplicating parser responsibilities:

- the playback scheduler remains responsible for order, pattern, row, and tick
  progression
- the mixer receives deterministic events derived from that scheduler
- tick duration is converted to output frames at the fixed render sample rate
- row and tick effects must be applied at the correct sample boundary inside the
  render stream
- trace/debug export should be extended so mixer decisions can be compared
  against audible output and reference renderers

## Migration Plan

Keep the transition incremental and reviewable:

- PR 1: add a mixer skeleton behind the existing `AudioEngine` boundary, with no
  runtime behavior change.
- PR 2: add an offline render test harness that can render a bounded frame count
  to PCM/WAV outside the app UI path.
- PR 3: implement one-shot sample rendering with deterministic sample-position
  accumulators and basic interpolation.
- PR 4: add forward and ping-pong loop rendering, including edge cases around
  loop start, loop length, sample offset, and turnaround frames.
- PR 5: apply channel volume, panning, volume envelopes, fadeout, and global
  volume in the software mixer.
- PR 6: integrate effect state with mixer-owned rendering decisions, starting
  with already-supported effects before adding broad new coverage.
- PR 7: switch runtime playback to the mixer behind a feature flag while keeping
  the `AVAudioPlayerNode` backend available as a fallback.

Each PR should be small enough to review on its own, include focused tests, and
avoid unrelated tracker UI, parser, or format changes.

## Validation Workflow

The mixer should support offline validation before it is used for runtime
playback:

- render the first N seconds of a local module such as `_DARKL.XM` to WAV
- render a reference WAV with OpenMPT/libopenmpt or MikMod using documented
  renderer settings
- compare the candidate and reference WAVs with `scripts/audio-compare.py`
- capture playback trace output for the same segment when debugging differences
- keep local modules, generated WAV files, comparison reports, and traces out of
  the repository

See `docs/audio-comparison.md` for the current comparison workflow.

## Success Criteria

The transition is successful when:

- the software mixer can render the first N seconds of `_DARKL.XM` to WAV from a
  local, uncommitted module file
- candidate renders can be compared against MikMod/OpenMPT with the existing
  `scripts/audio-compare.py` workflow
- trace/debug output can explain important row, tick, channel, voice, loop,
  envelope, pitch, and panning decisions
- the existing `AVAudioPlayerNode` backend remains usable until the mixer is
  demonstrably better
- no tracker viewport regressions are introduced
- parser architecture remains unchanged unless a future parser-specific ADR
  approves a separate migration

## Non-Goals

This ADR does not:

- implement the software mixer
- change runtime playback behavior
- remove or deprecate the `AVAudioPlayerNode` backend immediately
- change on-disk module formats
- refactor XM parsing responsibilities
- touch tracker viewport/rendering behavior

## Consequences

Positive:

- gives playback accuracy work a clear backend target
- allows offline audio comparison before runtime risk is introduced
- makes loop, envelope, panning, interpolation, and sample stepping behavior
  directly testable
- preserves the stable first-pass backend while the mixer matures
- keeps parser, UI, and DSP responsibilities separate

Tradeoffs:

- some current playback code will need to move behind or adapt to mixer-owned
  voice state
- future PRs must be careful about real-time safety once the mixer is used at
  runtime
- exact reference parity will still require iterative comparison against
  MikMod/OpenMPT and focused effect tests

This is the architectural handoff from first audible playback to deterministic
tracker playback accuracy.
