# Adapter-Safe Pattern Loop Transport

This document records the adapter-safe boundary for pattern-loop playback and
the first implemented user-visible Loop behavior.

## Implemented First Slice

Loop playback is implemented as a current order/pattern loop captured when
Play starts:

- Loop enabled before Play loops the selected/current order/pattern.
- Loop disabled before Play preserves existing normal song progression.
- Stop still stops playback and clears the active loop range.
- Play after Stop resolves Loop state again from the control and current
  start context.
- Toggling Loop while playback is already active is deferred: the control
  state is remembered, but the runtime loop range takes effect on the next
  Play.
- Editable document mutations while active current-pattern Loop playback is
  running rebuild a fresh editable `PlaybackSong` snapshot and
  `RuntimeCMixerAdapterEventPlan` off the realtime callback, then install the
  newest ready plan at a safe loop boundary.
- Loaded-module TIME remains the total adapter-plan song duration, not the
  loop length.

The first slice does not implement loop-range editing, arbitrary loop ranges,
live Loop retargeting, save/export, or editor clear-pattern/clear-song commands.

## Current Boundary

Runtime playback has an adapter-safe event boundary:

1. `PlaybackEngine.play(from:)` prepares or reuses the cached/prewarmed
   `RuntimeCMixerAdapterEventPlan`.
2. `PlaybackEngine.enter(position:)` publishes follow position, prepares row
   state, and calls `consumeRuntimeAdapterEvents(context:patternLoopRange:)`
   when the runtime C mixer adapter plan is available.
3. `RuntimeCMixerAudioEngine` selects the bounded loop range from the existing
   full adapter plan when Loop was enabled at Play start.
4. `RuntimeCMixerRenderCore` consumes scheduled adapter events on the render
   timeline and owns active voices, replacement ramps, envelopes, sample loops,
   pending events, song-end timing, and loop-range event repetition.

That boundary is the line pattern-loop work must preserve. The old
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

## Runtime Model

Pattern-loop playback uses a bounded range over the existing full
`RuntimeCMixerAdapterEventPlan`:

- `PlaybackEngine` resolves a `PlaybackPatternLoopRange` for the current
  order entry and pattern rows after the start position is resolved.
- `RuntimeCMixerAdapterEventPlan` derives the loop frame range from existing
  row-timing diagnostics and selects events whose source positions are inside
  that current order/pattern.
- `RuntimeCMixerAudioEngine` configures the render core with those existing
  adapter events and no planned song-end frame for looped playback.
- `RuntimeCMixerRenderCore` repeats the selected adapter events at the loop
  frame count while preserving active mixer state across wraps.
- The render queue keeps only bounded current/next loop slices instead of
  accumulating completed loop iterations.
- Follow-position sample-time mapping wraps planned frames back into the loop
  range so the UI remains on the looped order/pattern.

The loop path still consumes `RuntimeCMixerAdapterEventPlan` events. It does
not use the older timer-driven note trigger/update path, and it does not clear
or reset active C mixer voices at loop wraps. Scheduled adapter events can
naturally replace voices according to the existing mixer replacement/ramp
rules.

## Considered Strategies

### Bounded Adapter-Plan Range

Use the existing full adapter plan and select the rows/events belonging to the
current order/pattern range. This is the implemented first-slice path because
it keeps event ordering, source positions, and planned frames anchored to the
adapter output already used by normal playback.

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

The first slice adds bounded repeated adapter-event scheduling in the shared
render core. Broader range selection and more complex transport policies remain
future work.

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

## Verification Gates

Before merging pattern-loop playback changes:

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

- live Loop toggle changes to already-active playback
- loop length/TIME display policy
- loop-range editing
- clear current pattern and clear song utilities
- save/export behavior
- arbitrary loop range selection and more complex loop ranges
- pattern-loop effect playback changes
- broader local corpus listening beyond the required public fixture/manual
  smoke gates
- runtime gain/headroom changes
- parser changes
- tracker viewport/editor/control-panel visual changes

Future editor utility work should add separate design and implementation PRs
for clearing the current pattern, clearing song/pattern data while preserving
instruments and samples, optionally resetting the arrangement/order table while
preserving the instrument bank, and a future save/export flow.
