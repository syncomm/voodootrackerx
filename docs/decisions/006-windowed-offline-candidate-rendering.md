# ADR 006: Windowed Offline Candidate Rendering

## Status

Accepted for windowed offline rendering, including product WAV export.

## Context

The C-backed mixer started as an offline validation path. Runtime playback now
uses the CoreAudio-hosted C mixer, while the bounded offline helper remains a
separate path that adapts parsed playback-model rows into deterministic
scheduled C mixer voices for local WAV export and diagnostics.

Long local candidate exports can contain far more future note events than the
fixed C scheduled-voice pool can hold at one time. Increasing that fixed pool is
not the right primary answer because the pool is intended to remain small,
deterministic, and appropriate for bounded render work. The failure mode is
scheduling the whole range at once, not necessarily active DSP voice pressure.

## Decision

Add an explicit row-windowed scheduling mode to the developer-only bounded XM
render helper. The helper plans the bounded range through the existing adapter,
schedules one row window into a fresh offline C mixer, carries practical
continuation voice state into later windows where the adapter can compute it,
renders that window, appends deterministic PCM, and aggregates capacity and
carryover diagnostics across windows.

This decision does not switch runtime playback, wire the app Play button to the
C mixer, change parser ownership, implement new XM effects, change C mixer DSP
semantics, or touch tracker viewport rendering.

Windowed offline rendering retains a Swift-owned render-session cache of
immutable C-owned sample payload objects across fresh window mixers. Voices
reference those payloads without borrowing Swift memory; mixer teardown drops
references, and the cache destroys each payload only after every referencing
voice is cleared. Byte-identical parity tests gate the production default. The
defensive and pre-sanitized per-voice copy modes remain available, and runtime
plus immediate/non-windowed rendering remain on copied payloads.

Pre-index construction groups same-channel replacement ramps by old event
identity and preserves the prior last-matching-before-boundary rule without a
full reverse scan for every continuation candidate. Product export reports this
work as an indexing preparation phase before completed-window progress begins.

## Rationale

Windowed scheduling reuses the fixed scheduled-voice pool without changing the
C mixer hot path or requiring a larger static capacity. The carryover refinement
keeps sustained one-shot and looped voices continuous across fresh window mixer
instances by importing caller-computed source position, loop direction,
envelope position, key-off/release, fadeout, gain, and pan state into
continuation voices. It keeps the risky work inside the local offline export
helper, where diagnostics and listening tests can guide later improvements
before any runtime backend work.

## Tradeoffs

The carryover refinement is not a full generic mixer-state serialization system.
It computes deterministic continuation state from the bounded Swift adapter plan
and reschedules practical active voices at each window boundary. If a newer note
event on the same adapted channel reaches the boundary, the older voice is not
carried forward.

Unsupported/deferred effects, deferred volume-column semantics, pattern
traversal effects, note cut/delay/retrigger, and full FT2/OpenMPT voice rules
remain outside this decision. Boundary drops can still occur when too many
continuation voices must be rescheduled into a single window. Future work can
refine carryover further if long local listening shows boundary state is still a
dominant mismatch.
