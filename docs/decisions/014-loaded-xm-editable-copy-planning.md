# ADR 014: Loaded-XM Editable-Copy Planning

## Status

Accepted and implemented across both pre-alpha compatibility slices. This supersedes
ADR 012 only where it treated loaded-XM editable-copy admission as exact or
unavailable; its canonical editable sample/keymap model remains in force.

The explicit amendment below narrows Profile v1's original inert-header premise.

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

## Amendment: playback state in zero-payload headers

Independent generated-XM observations of pinned ft2-clone revision
`87be42543dac82cf802b5bddad917bda62ace131` falsify the original blanket claim
that ordinary zero-payload header fields are inert. Selecting an exact mapped
empty slot changes cached default volume/pan and period state despite producing
no PCM. A later instrument-only cell restores those cached defaults and resets
the silent channel's envelope/release state. A later playable note-only trigger
can expose the carried volume and pan. Normal note-only routing remains a
separate VTX implementation task; it is not needed to establish this source-state
loss.

Isolated controls establish volume, panning, finetune, and relative note as
playback-significant fields. At C-4 in Linear mode, a canonical empty header
sets period 4608; finetune +64 sets 4576, relative note +12 sets 3840, and both
set 3808. Relative note also changes a subsequent tone-portamento target.
Volume 40 survives an empty selection and silent instrument-only reset; the
all-zero control restores zero. Same-cell volume/pan writers override restored
channel values without rewriting cached defaults. Cosmetic name/padding and
reserved-byte controls leave observed playback state and PCM unchanged.

This amendment **narrows Profile v1**, preserving the same three outcomes:

- `exact`: canonical all-zero required empty headers retain their existing
  sparse identity and routing contract.
- `normalized`: ordinary 40-byte zero-payload, zero-loop/type required headers
  may discard cosmetic name/padding/reserved data only when volume, pan,
  finetune, and relative note are all zero. Structurally eligible unreferenced
  trailing empty slots remain discardable; independent controls with each
  nonzero field produced identical state and PCM when the map never selected
  those slots.
- `unavailable`: any required slot in the represented/keymap sparse span with
  nonzero volume, pan, finetune, or relative note receives the deterministic
  `playbackSignificantEmptySampleMetadata` reason. Conservatively retain this
  refusal even for tuning bytes whose individual quantization is unproven.

Loaded playback retains those four fields as immutable slot metadata, without
raw source buffers/paths, a represented sample, PCM, or an editor palette entry.
Channel envelope/release state survives source absence in the shared semantic
timeline; a C voice is never its storage. Canonical editable playback projects
only the existing all-zero empty-route semantics so playback agrees with
Export XM/reopen. The document acquires no nonrepresented sample metadata.

The canonical editable model and sparse writer remain unchanged. Required
empty writer headers are still all zero; source metadata that they cannot
preserve is refused at copy time. No new normalization profile, confirmation
UI, source mutation, Save/Save As support, or Amiga-to-Linear conversion is
introduced. The public `empty-slot-playback-state.xm` fixture and direct
copy/playback tests pin this clarification.
