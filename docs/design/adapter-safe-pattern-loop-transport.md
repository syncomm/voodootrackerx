# Adapter-Safe Pattern Loop Transport

This design spike documents the safest boundary for future pattern-loop
playback. It does not enable the Loop button to change runtime playback
behavior, and it does not implement pattern-loop playback.

## Current Boundary

Runtime playback already has an adapter-safe event boundary:

1. `PlaybackEngine.play(from:)` prepares or reuses the cached/prewarmed
   `RuntimeCMixerAdapterEventPlan`.
2. `PlaybackEngine.enter(position:)` publishes follow position, prepares row
   state, and calls `consumeRuntimeAdapterEvents(context:)` when the runtime C
   mixer adapter plan is available.
3. `RuntimeCMixerAudioEngine.consumeRuntimeAdapterEvents(context:)` configures
   the adapter event schedule once against the render core frame offset.
4. `RuntimeCMixerRenderCore` consumes scheduled adapter events on the render
   timeline and owns active voices, replacement ramps, envelopes, sample loops,
   pending events, and song-end timing.

That boundary is the line future pattern-loop work must preserve. The old
failed shape, where the transport bypassed adapter planning and drove note
trigger/update work from a separate timer path, is not acceptable.

## Public Fixture

`tests/reference-xm/generated/multi-pattern-loop-boundary.xm` is the public
fixture for this design work. It has three order positions, three patterns,
row-0 notes C-4/E-4/G-4, stable adapter event frames `[0, 48, 96]`, and a
planned song-end frame of `144` at `100 Hz`.

The fixture proves normal traversal and gives tests a deterministic order
range to reason about without private modules, private filenames, local paths,
generated WAVs, traces, logs, or reports.

## Candidate Model

This spike models a pattern-loop transport boundary in tests as a current-order
pattern range plus adapter-plan requirements:

- identify the current order entry and its pattern row range
- select events for that range from the existing full
  `RuntimeCMixerAdapterEventPlan`
- require the runtime adapter plan
- avoid timer-driven note triggers
- avoid clearing active voices at the loop boundary

The current helper lives in test support and is intentionally pure. It does not
schedule audio, seek playback, reconfigure the render core, reset engine state,
or change control-panel behavior.

## Considered Strategies

### Bounded Adapter-Plan Range

Use the existing full adapter plan and select the rows/events belonging to the
current order/pattern range. This is the preferred first implementation path
because it keeps event ordering, source positions, and planned frames anchored
to the adapter output already used by normal playback.

Open issue: the runtime scheduler still needs a safe way to loop or seek within
that range without discarding active voice, ramp, envelope, fadeout,
sample-step, or pending event state.

### Reusable Adapter-Plan Segment

Build a segment from adapter-plan events and row timing for one order/pattern,
then schedule repeated passes through that segment. This may be useful if full
plan selection is not enough, but segment replay still has to preserve active
runtime state across wraps.

Open issue: segment-local event IDs, active event associations, and replacement
state must remain coherent across repeats.

### Scheduler Seek/Rewind Within The Same Plan

Teach the runtime scheduler to move its planned-time cursor within a loop range
while keeping active mixer state. This most directly matches the desired
transport boundary, but it is a runtime scheduler feature and needs careful
metrics and listening gates.

Open issue: pending events before/after the wrap and song-end timers need a
clear policy.

### New Plan Generation Mode For One Order/Pattern

Generate an adapter plan specifically for the looped range. This keeps the
adapter machinery but risks diverging from normal full-song traversal if timing,
effect memory, pattern break, position jump, or future effect support differs.

Open issue: the generated sub-plan would need proof that its row/effect state
matches normal traversal into the selected range.

### Future C Mixer Scheduler Capability

Add explicit loop-range support to the runtime C mixer scheduler. This might
be the cleanest long-term architecture if the scheduler can preserve active
voice state and repeat planned events without a Swift timer path.

Open issue: this is larger than a spike and would require careful render-core
tests, runtime metrics, and manual listening.

## Rejected Designs

The next implementation must explicitly avoid:

- bypassing `RuntimeCMixerAdapterEventPlan`
- switching to a separate timer-driven note trigger/update path
- clearing or resetting active C mixer voices on loop wrap
- resetting `PlaybackEngine` runtime state at the boundary in a way that causes
  output discontinuity
- treating structural tests as proof that playback sounds correct

These designs are rejected because they can break active voice continuity,
replacement ramps, envelopes, fadeout, sample-loop phase, pending events, and
adapter event ordering.

## Required Gates Before Enabling Loop Playback

Before the Loop button changes runtime playback behavior:

- model tests must prove the intended order/pattern range and adapter-plan
  event selection for public fixtures
- runtime tests must prove stable event order, stable planned frames, and clean
  handling of wrap boundaries
- Play/Stop/seek behavior must remain unchanged outside the explicit loop mode
- runtime metrics must remain clean for clipping/overrange and
  `output_discontinuity_count`
- manual listening must cover the public multi-pattern fixture and at least one
  local private smoke module using anonymized labels and no committed outputs

## Deferred Work

This PR intentionally defers:

- user-visible pattern-loop playback
- Loop button runtime wiring
- pattern-loop effect playback changes
- C mixer scheduler changes
- runtime gain/headroom changes
- parser changes
- tracker viewport/editor/control-panel visual changes
- save/export behavior

Future editor utility work should add separate design and implementation PRs
for clearing the current pattern, clearing song/pattern data while preserving
instruments and samples, optionally resetting the arrangement/order table while
preserving the instrument bank, and a future save/export flow.
