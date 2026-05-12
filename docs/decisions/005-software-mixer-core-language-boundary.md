# ADR 005: Software Mixer Core Language Boundary

## Status

Accepted as guidance for the long-term deterministic software mixer boundary.

## Context

ADR 004 accepted the transition toward a deterministic pull-based software
mixer behind the existing playback/audio boundary. Since then, the Swift
`SoftwareMixer` has become useful as an offline prototype and test harness. It
can render deterministic silence, synthetic one-shot sample voices, synthetic
forward loops, synthetic ping-pong loops, gain, and simple stereo panning.

Runtime playback still uses the `AVAudioEngine` / `AVAudioPlayerNode` /
`AVAudioUnitVarispeed` backend. The Swift software mixer is not used for live
playback.

The project also already has a C `ModuleCore` parser layer. Parser ownership is
still governed by `docs/decisions/001-xm-parsing-responsibilities.md`; this ADR
does not move parsing responsibilities or couple parser work to mixer work.

The open architecture question is whether the final mixer hot path should
remain Swift or migrate toward a small C or C-compatible core wrapped by Swift.

## Decision

Keep Swift/AppKit responsible for UI, transport orchestration, editor state,
diagnostics, offline harness wiring, and high-level integration.

Treat the current Swift `SoftwareMixer` as a deterministic reference prototype
and behavior specification harness. It should remain useful for tests and for
describing expected mixer behavior while the lower-level implementation matures.

Move the eventual mixer/DSP hot path toward a small C or C-compatible engine
behind a thin Swift wrapper. The boundary should stay narrow and
buffer-oriented:

- no AppKit, `AVAudioPlayerNode`, or UI types in the mixer core
- caller-owned input and output buffers at the language boundary
- explicit render configuration and state handles
- deterministic fixed-frame render calls
- no broad Swift object graph or parser structures crossing the hot path
- no requirement to move all playback, scheduling, diagnostics, or UI code to C

This is not an immediate rewrite. Future PRs should port mixer primitives
incrementally while preserving behavior with the existing Swift tests.

## Rationale

Swift has been the right place to prototype the mixer behavior so far:

- fast iteration
- memory safety
- easy AppKit and test integration
- readable deterministic tests
- good ergonomics for orchestration and diagnostics
- low friction while the playback model is still changing

The final tracker mixer hot path has different constraints. A small
C-compatible core is a better long-term fit for low-level sample rendering
because it offers:

- predictable memory layout
- lower allocation and ARC risk in render loops
- a stable Swift interop boundary
- portability outside macOS/AppKit
- clearer real-time-audio discipline
- a closer fit for low-level tracker DSP, sample stepping, loop handling,
  interpolation, and legacy compatibility work

Moving too early would be harmful. It could create a premature rewrite,
duplicate implementations, extra interop complexity, and slower feature
progress before the behavior is fully specified.

Staying Swift-only too long also has risks. As envelope, timing, and effect
logic grows, the render loop may accumulate accidental allocations or ARC
traffic, hot-path performance uncertainty may increase, the core may become
less portable, and migration will get harder once more behavior depends on
Swift-only implementation details.

The compromise is to keep Swift as the reference and orchestration layer while
moving only proven hot-path primitives across a narrow C-compatible boundary.

## Consequences

Positive:

- the existing Swift mixer and tests remain valuable instead of being thrown
  away
- the project gets a clear target boundary before adding more complex mixer
  behavior
- future runtime audio work can be made more portable and real-time disciplined
- Swift remains the right layer for UI, transport, diagnostics, and integration
- the `AVAudioPlayerNode` backend remains available while the C-backed mixer is
  proven offline

Tradeoffs:

- the project will temporarily carry both Swift reference behavior and
  C-backed implementation work
- wrapper and memory-ownership rules must be designed carefully
- porting behavior incrementally will require tests that compare C-backed
  output against the Swift reference expectations
- contributors must avoid broad parser, UI, or playback backend refactors while
  introducing the mixer core

This decision narrows the language boundary. It does not require moving the
whole audio subsystem, parser, app model, or tracker UI into C.

## Migration Plan

1. Keep the current Swift `SoftwareMixer` and deterministic tests as the
   reference/specification harness.
2. Add a minimal C mixer core skeleton in a later PR, not in this PR.
3. Add a thin Swift wrapper around the C mixer.
4. Port one-shot synthetic rendering behavior from the Swift reference to the
   C-backed implementation.
5. Port forward-loop and ping-pong-loop behavior.
6. Continue envelope, timing, and effect integration on the C-backed core after
   the primitive rendering behavior is covered.
7. Keep the `AVAudioPlayerNode` runtime backend active until the C-backed
   software mixer is proven through offline deterministic renders.
8. Only later add a feature-flagged runtime backend switch.

The recommended next implementation PR is a minimal C software mixer core
skeleton with a Swift wrapper that can render deterministic silence through the
existing offline test path. It should not port all Swift mixer behavior, switch
runtime playback, or use local copyrighted modules in automated tests.

## Non-goals

This ADR does not:

- rewrite the Swift `SoftwareMixer`
- delete the Swift `SoftwareMixer`
- implement the C mixer core
- change runtime playback behavior
- switch runtime playback to the software mixer
- remove or deprecate the `AVAudioPlayerNode` backend
- refactor parser architecture or `ModuleCore`
- change on-disk module formats
- touch tracker viewport/rendering behavior
- add generated audio, traces, screenshots, or local copyrighted modules
