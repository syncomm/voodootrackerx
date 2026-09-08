# ADR 014: Loaded-XM Editable-Copy Planning

## Status

Accepted and implemented across both pre-alpha compatibility slices. This supersedes
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

`File > Make Editable Copy` is enabled for a loaded XM when transport is
stopped and no top-level presentation conflicts. The action consumes the planner
result directly: `exact` and Profile-v1 `normalized` create the planner-provided
untitled value-owned document immediately, while `unavailable` presents its typed,
user-facing reason. Profile v1 is proven safe/inert and requires no confirmation.
The action revalidates source identity, complete context, transport, presentation,
and a fresh planner result immediately before transition. The loaded source always
remains read-only and untouched.

## Rationale

The three-way result makes intentional normalization explicit and countable
without calling it lossless. It preserves conservative refusal for any source
state whose supported musical or routing semantics cannot be proven stable and
gives the UI one typed plan and reason model to consume without duplicating
compatibility rules.

## Impact And Tradeoffs

Source sample-slot provenance carries the minimal structural fields needed to
prove Profile v1. The writer and planner share pure envelope canonicalization
rules. A normalized copy may later export canonical VTX XM structure that differs
structurally from its source; it never overwrites or claims that source. Any future
normalization that changes represented musical or source state requires its own
approved profile plus explicit explanation and confirmation before conversion; it
must not use the silent Profile-v1 path. No file format, parser architecture,
runtime/DSP behavior, source mutability, Save behavior, or writer semantics change.
