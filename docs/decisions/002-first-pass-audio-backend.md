# ADR 002: First-Pass Audio Backend

## Status

Accepted.

## Context

VoodooTracker X now has the first audible XM playback path:

- the playback subsystem owns transport state and playback position
- the playback song model adapts loaded XM data into traversal-ready rows, patterns, orders, and samples
- silent playback follow advances the tracker UI through rows and orders
- first-pass audible playback triggers decoded XM sample buffers while that visual follow state advances

The current implementation uses `AVAudioEngine` with scheduled `AVAudioPlayerNode` buffers. An earlier lower-level CoreAudio/custom render-callback experiment introduced crash risk on the CoreAudio IO thread. That path was removed from the first audible playback milestone in favor of the safer scheduling backend.

The project still needs a future tracker-accurate mixer. XM effects, envelopes, loops, interpolation, and sample-accurate channel mixing are not implemented yet.

## Decision

Use `AVAudioPlayerNode` as the current first-pass audio backend.

The backend is intentionally scoped to proving:

- audio engine start/stop lifecycle
- basic decoded sample triggering
- channel voice replacement on new note events
- safe Play/Stop behavior
- continued visual tracker follow during audible playback

Lower-level CoreAudio/custom render-callback work is deferred until the playback model, sample model, timing behavior, and effect requirements are mature enough to justify a dedicated tracker mixer.

## Rationale

`AVAudioPlayerNode` is the safer near-term backend because it avoids running Swift playback logic inside a CoreAudio render callback. The first audible playback milestone needs stability more than sample-accurate mixing.

A custom render path will likely be appropriate later, but only behind the playback/audio boundary and only when the project is ready to implement deterministic tracker mixing semantics. Taking that on now would combine too many risks:

- real-time thread safety
- sample-accurate event scheduling
- XM period/pitch behavior
- loop and envelope handling
- effect command processing
- channel mixing and voice lifecycle correctness

Deferring that work keeps this milestone small and reviewable while preserving a clean path toward a stronger backend.

## Current Limitations

The current backend is intentionally incomplete:

- no XM effects are implemented
- playback is not sample-accurate tracker mixing
- sample triggering is limited and first-pass
- pitch handling is approximate
- sample loops are not implemented
- envelopes are not implemented
- interpolation is minimal
- panning and volume/effect command semantics are incomplete
- unsupported XM behavior should fail safely rather than trying to emulate full tracker playback

These limitations are acceptable for first audible playback, but they should not be mistaken for final XM playback compatibility.

## Future Direction

Keep audio isolated behind playback/audio boundaries:

- UI code should call playback transport APIs, not schedule audio directly.
- DSP and audio scheduling logic should not be embedded in AppKit views or window controllers.
- Parser architecture should remain separate from playback and should not be unified opportunistically as part of audio work.
- Future mixer work should be introduced as a focused backend evolution, not as a broad UI or parser refactor.

When tracker accuracy requires it, evolve toward a dedicated custom tracker mixer/render path that can:

- consume deterministic playback positions and row events
- manage channel state explicitly
- apply XM effects and envelopes
- handle loops, interpolation, panning, and volume semantics
- render continuously with predictable timing

That future mixer should replace or sit behind the current `AVAudioPlayerNode` implementation without changing UI-facing transport boundaries.

## Consequences

Positive:

- safer first-pass audible playback
- smaller implementation surface
- no CoreAudio IO-thread Swift callback risk in the current backend
- playback behavior stays isolated from tracker rendering
- future mixer work has a documented architectural target

Tradeoffs:

- current playback is not tracker-accurate
- advanced XM compatibility remains future work
- some scheduling/mixing behavior will need to be redesigned when moving to a custom mixer

This is an intentional stabilization choice, not the final audio architecture.
