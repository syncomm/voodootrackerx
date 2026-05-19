# ADR 006: Windowed Offline Candidate Rendering

## Status

Accepted for developer-only bounded XM candidate WAV exports.

## Context

The C-backed mixer is currently an offline validation path. Runtime playback
still uses `AVAudioPlayerNode` and `AVAudioUnitVarispeed`, while the bounded
offline helper adapts parsed playback-model rows into deterministic scheduled
C mixer voices for local WAV export and diagnostics.

Long local candidate exports can contain far more future note events than the
fixed C scheduled-voice pool can hold at one time. Increasing that fixed pool is
not the right primary answer because the pool is intended to remain small,
deterministic, and appropriate for bounded render work. The failure mode is
scheduling the whole range at once, not necessarily active DSP voice pressure.

## Decision

Add an explicit row-windowed scheduling mode to the developer-only bounded XM
render helper. The helper plans the bounded range through the existing adapter,
schedules one row window into a fresh offline C mixer, renders that window,
appends deterministic PCM, and aggregates capacity diagnostics across windows.

This decision does not switch runtime playback, wire the app Play button to the
C mixer, change parser ownership, implement new XM effects, change C mixer DSP
semantics, or touch tracker viewport rendering.

## Rationale

Windowed scheduling reuses the fixed scheduled-voice pool without changing the
C mixer hot path or requiring a larger static capacity. It keeps the risky work
inside the local offline export helper, where diagnostics and listening tests can
guide later improvements before any runtime backend work.

## Tradeoffs

The first pass does not serialize active C mixer state across window boundaries.
Sustained voices, source sample position, envelope position, and fadeout state
may be cut when a window ends. Rows and note events contained wholly inside one
window retain the existing bounded adapter behavior.

Future work can refine window-state carryover if long local listening shows that
boundary cuts dominate the remaining mismatch.
