# ADR 014: Loaded-XM Editable-Copy Planning

## Status

Accepted for the first of two pre-alpha compatibility slices. This supersedes
ADR 012 only where it treated loaded-XM editable-copy admission as exact or
unavailable; its canonical editable sample/keymap model remains in force.

## Problem

The strict loaded-XM copy gate cannot distinguish an unsafe conversion from a
source that differs only in inert zero-payload sample-header state. Treating both
as unavailable hides a safe compatibility path, while silently admitting both
would weaken source and routing guarantees.

## Decision

Use one authoritative planner with `exact`, `normalized`, and `unavailable`
outcomes. Normalization Profile v1 permits only ordinary 40-byte, zero-payload,
zero-loop/type empty headers. Required sparse slots retain exact Sxx identity and
all 96-note map references without fabricated PCM; unreferenced trailing empty
slots may be dropped. All represented nonempty samples remain under the existing
strict boundary.

Admission is structural and pure apart from the writer's existing in-memory data
preflight. Deterministic guards reject Amiga frequency tables, ambiguous sample
or keymap state, unstable envelope canonicalization, incomplete instrument
identities, invalid represented loops, and other writer failures. The planner
does not write or reopen a temporary file.

PR 1 keeps the existing command strict: only `exact` reaches Make Editable Copy.
`normalized` remains unavailable until a later UI asks for explicit confirmation.
The loaded source remains read-only and the resulting document remains an
untitled value-owned copy.

## Rationale

The three-way result makes intentional normalization explicit and countable
without calling it lossless. It preserves conservative refusal for any source
state whose supported musical or routing semantics cannot be proven stable and
gives the confirmation UI a typed plan and reason model to consume.

## Impact And Tradeoffs

Source sample-slot provenance carries the minimal structural fields needed to
prove Profile v1. The writer and planner share pure envelope canonicalization
rules. No file format, parser architecture, runtime/DSP behavior, source
mutability, Save behavior, or AppKit UI changes in this slice. A second PR is
required before users can accept a normalized copy.
