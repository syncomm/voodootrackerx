# ADR 001: XM Parsing Responsibilities

## Status

Accepted as guidance for near-term development.

## Problem

The codebase currently uses both `ModuleCore` (C) and Swift-side parsing logic for XM files.

This creates an obvious architecture question:

- Should `ModuleCore` eventually become the full source of truth for XM parsing?
- Should the hybrid model remain?
- Or should responsibilities be split more explicitly?

This needs a documented answer so future cleanup work does not remove one side opportunistically and introduce regressions.

## Current State

Current parsing flow:

- `ModuleCore` exposes `mc_parse_file(...)` and returns `mc_module_info`.
- For XM files, `mc_module_info` currently contains:
  - module/header metadata
  - order table
  - pattern row counts
  - pattern packed sizes
  - first instrument name
  - a bounded list of decoded non-empty XM events
- The bounded event list is capped by `MC_MAX_XM_EVENTS`.
- The AppKit app calls `mc_parse_file(...)` first through `ModuleMetadataLoader`.
- The Swift app layer then reparses the XM file from disk to build the full `XMPatternData` grid used by the tracker UI.
- If the full Swift reparse fails, the app falls back to reconstructing patterns from the bounded `ModuleCore` event summary.

Current usage split:

- `ModuleCore` is used by:
  - the Swift app for top-level module metadata
  - `mc_dump`
  - `tests/core/ModuleCoreTests.swift`
- Swift-side XM parsing is used by:
  - the tracker app UI path that needs a complete in-memory pattern model

Current overlap:

- both layers decode XM pattern/event data
- both layers read pattern row counts and packed event data semantics

Current gaps:

- `ModuleCore` does not currently expose a complete canonical XM module structure suitable for the tracker UI
- `ModuleCore` event capture is intentionally bounded, which makes it unsuitable as the sole UI source of truth without further work
- the Swift layer is currently carrying UI-facing full-load responsibilities that are not yet modeled in the C interface

## Why The Hybrid Model Exists Today

Likely reasons, based on the current code:

- staged implementation during iterative development
- keeping `ModuleCore` small and useful early for metadata/tests/CLI
- faster experimentation in Swift while the UI and tracker model are changing
- app-layer convenience when constructing `XMPatternData`
- avoiding premature commitment to a large cross-language canonical C structure
- preserving a fallback when one decoding path is incomplete

## Options

### Option A: Make ModuleCore the full source of truth

Advantages:

- one canonical XM parser
- fewer duplicated decode rules over time
- better consistency between CLI/tests/app once migration is complete
- likely better long-term maintainability if the C interface becomes complete and stable

Risks:

- high migration risk because the current UI depends on richer Swift-side structures
- the C API would need to expand substantially to expose complete pattern/instrument/sample data safely
- mistakes during migration could cause subtle tracker regressions
- cross-language ownership, allocation, and lifetime rules would need careful design

Migration difficulty:

- medium to high

Likely effects:

- performance could improve or remain neutral
- maintenance gets better only after the migration is fully complete
- short-term development speed likely slows during the transition

### Option B: Keep the hybrid architecture intentionally

Advantages:

- minimal immediate risk
- keeps Swift-side UI iteration fast
- preserves the existing app workflow without re-architecting `ModuleCore`

Risks:

- duplicated parsing logic continues to drift
- bugs may be fixed in one parser but not the other
- future contributors may misread the duplication as accidental and “clean it up” incorrectly

Maintenance burden:

- medium and rising over time unless boundaries are documented tightly

Documentation needs:

- high; the split must stay explicit

### Option C: Formalize a split-responsibility architecture

Definition:

- `ModuleCore` parses canonical raw module data and shared metadata
- Swift transforms that canonical data into UI/app-layer structures
- Swift should stop doing independent file-format decoding once `ModuleCore` exposes enough raw data

Advantages:

- preserves a strong boundary between parsing and UI transformation
- reduces duplication more safely than a hard immediate unification
- keeps app-specific shaping logic in Swift where it is easier to evolve

Risks:

- still requires deliberate API design in `ModuleCore`
- partial migrations can leave the boundary muddy if not finished

Migration difficulty:

- medium

Likely effects:

- best balance of maintainability and regression control
- supports future development without forcing a rewrite up front

## Recommendation

Recommended direction:

- formalize a split-responsibility architecture

Near-term policy:

- keep the hybrid model for now
- move toward `ModuleCore` as the canonical parser only when it can expose complete, regression-safe raw XM structures
- keep Swift responsible for app/UI transformation rather than low-level XM decoding long term

Rationale:

- correctness is more important than removing duplication immediately
- the current `ModuleCore` interface is not yet sufficient to replace the Swift UI-facing loader safely
- a direct “ModuleCore only” migration now would create unnecessary regression risk
- a documented split gives the project a path toward consolidation without forcing a parser rewrite during unrelated work

## Required Future Work

Before `ModuleCore` can become the sole parsing source for the app, the project would need:

- a deliberate design for canonical raw XM data structures exposed across the C/Swift boundary
- explicit handling for full pattern/event data without the current bounded-event limitation
- compatibility tests that compare app-visible behavior before and after migration
- a migration plan for instrument/sample/pattern loading responsibilities
- a decision about which transformations belong in C and which remain Swift-only

Until that work is approved, future agents should preserve both parsing layers and avoid opportunistic parser unification.
