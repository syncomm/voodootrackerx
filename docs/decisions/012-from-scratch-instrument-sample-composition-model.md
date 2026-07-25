# ADR 012: From-Scratch Instrument And Sample Composition Model

## Status

Accepted as the product and architecture contract for the future from-scratch composition workstream. The behavior
is planned unless explicitly called current. This documentation-only decision adds no importer, generator, mutation
control, format support, or runtime behavior.

## Context

VTX 1.0 is a self-contained XM-style sample/instrument tracker. A user must be able to begin with a clean launch,
create playable material, compose and arrange a song, and produce both XM and rendered audio without first opening XM.

The current app provides blank pattern/order composition, isolated note audition when represented PCM exists,
editable metadata, Export XM, and WAV/M4A export. Instrument/sample creation, import, generation, and keymap
mutation do not yet exist.

There is one important current-versus-target difference. `File > New` creates an untitled editable song with eight
channels, one 64-row pattern at order 0, and I01/S01 selected, but `BlankTrackerDocument.makeDefault()` uses an empty
instrument palette. I01 is not represented, S01 is not a modeled destination, and palette-backed controls show no
instrument/sample. The playback loader also omits sampleless instruments and zero-length samples. The first
implementation must close this gap without fabricating a sample, PCM, or sample metadata.

## Decision

The approved vertical slice is:

```text
Launch or File > New
-> create an instrument
-> create, generate, or import a sample
-> assign/select/map the sample
-> audition the instrument
-> adjust essential metadata
-> enter notes into patterns
-> arrange patterns in song order
-> play the song
-> Export XM
-> reopen and play the export
-> Export WAV/M4A
```

All new document mutations use `EditableDocumentEditCoordinator.applyEdit`. Loaded modules remain read-only, Save
and Save As remain disabled, and exports remain destination-based.

### File > New And Empty Destinations

`File > New` remains recognizable and otherwise keeps its current defaults:

- an editable blank XM-style song;
- eight channels and the current one-order/one-pattern structure;
- I01 selected and represented as an unnamed instrument; and
- S01 selected as an empty destination slot.

A represented instrument and represented sample are different concepts. Empty S01 is slot availability plus
selection only: no `PlaybackSample`, PCM, source-rate claim, name, loop, volume, pan, tuning, bit depth, or other
fabricated metadata. New documents do not have zero instruments, but remain silent until a sample exists.
The selected destination makes import/generation obvious without requiring the user to create lower-level structure.

The editable model must preserve sparse instrument/sample identity well enough to distinguish empty destinations
from represented samples. This adds no on-disk format; current loader/writer compaction remains until focused
compatibility work proves the model change.

### New Instrument

```text
New Instrument
-> allocate and select the next available instrument slot
-> create an unnamed instrument
-> select its empty S01 destination
-> reveal or focus the Instrument Editor
```

“Next available” means the lowest unused supported one-based slot. Creation is one labeled `applyEdit` transaction
and whole-document undo action, creates no sample object/PCM/metadata, and is unavailable for loaded modules or
during playback.

Ixx and Sxx remain one-based UI identities using the existing tracker-style display. Implementations share one
capacity policy with Export XM and reject overflow before mutation. The current writer allows at most 255 instruments
and 16 represented samples per instrument and requires 96 entries for an explicit note map. These subset limits are
not an arbitrary-XM parity claim and may change only through focused format/model evidence.

### Context-Sensitive Sample Import

Import from the Sample Editor or a selected empty sample slot targets that exact Sxx. For an occupied slot, present:

```text
Replace Current Sample
Add as New Sample
Cancel
```

Replace keeps the slot identity/keymap references; Add uses the next available slot; Cancel changes nothing. Work
inside an existing instrument never creates a new instrument implicitly.

A global `File > Import Sample...` action or main-tracker audio drop may use a selected empty destination. With no
usable destination, the beginner path is atomic:

```text
create a new instrument
-> select empty S01
-> import into S01
-> map S01 across all 96 notes
-> focus the Sample Editor
-> make the sample immediately auditionable
```

The resulting document change is one `applyEdit` action. A drop onto a specific occupied row remains open.

### First-Sample Keymap

The first represented sample maps across all 96 XM notes. Sample 1 is the implicit/default assignment, and all-S01
has a neutral keyboard appearance. Adding S02 or later never changes mappings; later samples need explicit assignment.

Mapping and transient audition highlight are separate layers. Keymap mutation uses `applyEdit`/undo; read-only
visualization may land first. `instrument-envelopes-keymap.xm` is the split-map public reference fixture.

### Sample Naming And Ownership

An imported sample defaults to the source filename without its extension:

```text
TR909_Kick_03.wav -> TR909_Kick_03
```

Names follow the writer's printable-ASCII replacement and 22-byte XM field limit. `(unnamed sample)` is a display
fallback only when no usable name remains; `unknown` is not the default. Future VTX-only provenance may retain the
original filename/import properties separately from canonical XM fields.

Decoded PCM is copied into the document. Playback, undo/redo, Export XM, offline rendering, portability, and future
AUv3 state never require the source file. A source path is provenance, not document ownership or an owned save path.

## Import And Generation Architecture

### Format Order

The from-scratch milestone lands lossless formats in this order:

1. WAV.
2. AIFF/AIFC.
3. FLAC.

WAV is the baseline, AIFF/AIFC covers macOS/legacy collections, and FLAC covers modern libraries/archives. One PR
does not promise all three.

The native FLAC foundation accepts only preflighted 16/24-bit mono/stereo sources and decodes bounded Float32
chunks with Apple `ExtAudioFile`. Raw STREAMINFO supplies rate, channels, source depth, and known positive frame
count before allocation under the shared cap. Valid 8-bit FLAC is unsupported by the selected Apple decoder and is
rejected during preflight, as are all untested depths and Ogg-FLAC. Output still becomes canonical mono 16-bit XM
PCM; tags, pictures, cues, seek tables, ReplayGain, embedded names, and loop-like metadata are ignored. This
exact native-FLAC scope is now exposed through the existing Sample Editor LOAD workflow.

Ogg Vorbis, MP3, M4A/AAC, CAF, raw PCM, XI, folders/batch import, and archives are deferred. XI remains a separate
broader VTX 1.0 target; this decision does not remove it from v1 scope.

### Canonical Pipeline

```text
source file
-> decode off UI and audio-render threads
-> canonical Float32 PCM intermediate
-> explicit channel conversion
-> tuning derivation
-> validated document-owned sample snapshot
-> one applyEdit commit
```

No mutation occurs until decode/validation succeed; failure or cancellation leaves the document unchanged. Import
does no audio-render-thread work and implies no runtime-backend, scheduler, or C mixer change.

XM-compatible storage remains mono, and mono input remains mono. Stereo offers `Mix to Mono` (default), `Left`, or
`Right`; VTX never silently chooses a channel. More-than-stereo input is rejected clearly. No stereo-XM extension is implied.

Imports default to 16-bit XM-compatible encoding, with Float32 allowed for decode/intermediate PCM. VTX never
silently reduces to 8-bit; optional 8-bit conversion is later/advanced. Export XM writes the supported encoding.

WAV implementation evidence resolves tuning: C-4 at 8,363 Hz is neutral, the target offset is
`12 × log2(sourceRate / 8363)`, and the existing linear mapping supplies 128 finetune steps per semitone. Import chooses
the representable relative-note/finetune pair with minimum error, preferring the smallest absolute finetune and rounding
half steps away from zero. Error is bounded to 0.390625 cents; rates outside the current C-4 effective-note/signed-byte
range are rejected. PCM is not resampled, and XM still has no authoritative source-rate field.

### Built-In Generation

From-scratch composition must not require a sample library. The Sample Editor will generate sine, square/pulse,
triangle, saw, and noise with original deterministic mono formulas, 16-bit defaults, sensible headroom, and
loop-friendly defaults where practical. Generation fills the selected slot, applies the first-sample map, and becomes
immediately auditionable in one undoable `applyEdit`; it normally targets an empty slot, and overwrite requires confirmation.

## Lifecycle And Reference Integrity

Required instrument operations are Add/New, Duplicate, Rename, Clear/Delete in place, future XI Replace, Move Up,
Move Down, Move To, and Swap. Duplicate deep-copies metadata, PCM, envelopes, keymap, fadeout, and autovibrato to a
new slot; the source is unchanged and the action is one undoable snapshot.

Initial deletion is safe and non-compacting:

```text
Clear Instrument Ixx
-> warn when pattern data references Ixx
-> clear Ixx in place
-> preserve every instrument number and pattern reference
```

Required sample operations are Add Empty Slot, Import, Generate, Duplicate, Replace, Rename, Clear/Delete in place,
Move Up, Move Down, Move To, and Swap. Replace changes PCM/metadata in the selected slot, preserves its instrument
and keymap identity, confirms before overwrite, embeds the replacement, and is one undo action.

Sample deletion is likewise non-compacting:

```text
Clear Sample Sxx
-> warn when the keymap references Sxx
-> clear Sxx in place
-> preserve every sample index
-> leave references to Sxx honestly unavailable
```

Reordering is semantic, not row-only. I08 to I02 remaps every pattern instrument reference; S05 to S02 remaps all 96
keymap entries. Move/swap preserves PCM/metadata, normalizes selection, and undoes to exact prior numbering and
references. It follows basic lifecycle/import work and requires dedicated synthetic tests.

## Product Surface And Content Policy

The Instrument Editor owns instrument identity, its sample palette, keymap
visualization/assignment, envelopes, autovibrato, default sample metadata, and
note audition. Its piano is mapping-first and audition-second.

The Sample Editor owns sample identity, import/generation, waveform and loop
metadata, sample parameters, later PCM operations, replace/clear/duplicate, and
sample selection within the current instrument. Its instrument selector changes
the current instrument but does not create one.

A modeless Performance Keyboard/Pad with dedicated piano/pad audition is post-v1/Pro/AUv3/iPad work and may supply a
contained AUv3/iPad surface later. It does not authorize a main tracker window, logo, or viewport redesign. ADR 011
remains the post-v1 AUv3 direction.

VTX imports files the user lawfully acquired for use subject to the provider license. Direct Loopcloud, Splice,
Loopmasters, or other service integration is outside this milestone and needs separate API, authentication, cache,
licensing, and account-lifecycle design.

“Royalty-free” does not imply permission to redistribute raw samples. Official
VTX packs may use original project PCM, contributor/commissioned recordings
with explicit redistribution rights, verified public-domain material, CC0 with
provenance, or later-approved CC BY material with complete attribution. Prefer
original VTX material or CC0 with recorded provenance. A future pack manifest
records pack/author, source, license, synthesis or recording method, names,
SHA-256 hashes, and a redistribution statement. Legal/license review is
required before publishing a website pack; ordinary commercial-library samples
must never be repackaged without an explicit redistribution license.

## Release Gate

The proposed future release is:

```text
v0.3.0-alpha.1 - From-Scratch Composition Alpha
```

The version is a release identity, not a percent-complete estimate. It is
earned only when this public-safe acceptance path passes:

```text
Launch or File > New
-> create a new instrument
-> import or generate a sample
-> map S01 across all 96 notes
-> audition it
-> adjust essential metadata
-> enter notes into patterns
-> arrange patterns in song order
-> play the song
-> Export XM
-> reopen and play the export
-> Export WAV/M4A
```

Every mutation uses `applyEdit`; imported/generated PCM is document-owned;
Export XM preserves the supported composition; WAV and M4A export succeed.
Loaded modules stay read-only, Save/Save As stay disabled, exports remain
destination-based, and runtime playback plus tracker viewport behavior remain
protected. Acceptance uses only project-owned generated samples and public
fixtures, never private modules.

## Dependency-Ordered PR Plan

This is a sequence of focused PRs, not one large implementation PR:

1. Create an unnamed instrument with empty S01, canonical selection, and one
   `applyEdit`/undo action.
2. Generate sine first; add square, triangle, saw, and noise in focused slices
   as needed, with automatic first-sample mapping.
3. Add WAV decode/validation, channel choice, naming, ownership, and proven
   tuning policy.
4. Add Sample Editor empty-slot Load and occupied-slot Replace/Add/Cancel.
5. Add AIFF/AIFC through the canonical importer output.
6. Add FLAC through the same importer output.
7. Harden the all-96-note S01 default and neutral visualization.
8. Add instrument add/duplicate/clear-in-place/rename.
9. Add sample add/duplicate/clear-in-place/rename/replace.
10. Polish read-only keymap visualization: neutral S01, visible S02+ mapping,
    and a separate active-note layer.
11. Add editable keymap range/paint assignment through `applyEdit`.
12. Add reference-preserving instrument and sample move/swap.
13. Run the complete automated and manual from-scratch acceptance slice.
14. Prepare `v0.3.0-alpha.1` docs, notes, checklist, and tag/build instructions.

The recommended first implementation PR after this ADR merges is:

```text
instrument: create empty instrument with S01 through applyEdit
```

## Test And Fixture Plan

Future project-owned tests cover an empty instrument/S01 destination; generated
sine and waveform family; mono WAV; stereo mix/left/right; AIFF and FLAC;
common-rate tuning; filename naming/truncation; first-sample all-note mapping;
instrument/sample duplicate and clear-in-place; a keymap reference to a cleared
sample; instrument move plus pattern-reference remap; sample move plus keymap
remap; Export XM/reopen from a complete new composition; and WAV/M4A export of
that composition. Tests use synthetic data and the public fixture pack only.

## Explicit Deferrals

The from-scratch alpha does not require third-party plug-in hosting, AUv3,
MIDI pattern recording, batch/folder import, commercial sample-service
integration, lossy import formats, XI import/export, full destructive PCM
editing, third-party consumer-library packs, automatic slot compaction,
multi-output, or tracker viewport redesign.

## Open Questions And Required Proof

Do not resolve these without focused implementation evidence:

- whether optional 8-bit import conversion belongs in v0.3 or later;
- multi-file import UX;
- whether a drop on a specific occupied sample row means Replace or Add New;
- warning UX for clearing referenced instruments or keymap-referenced samples;
- fixed-capacity versus dynamic-looking instrument/sample slot presentation;
- the S02+ keymap visual language;
- whether generated noise is fixed per creation or exposes a seed; and
- whether official packs stay original/CC0-only or later admit reviewed CC BY.

## Consequences

The model gives creation, import, mapping, ownership, deletion, and reordering
one reference-safe contract while preserving existing loaded-module and export
boundaries. It also exposes a prerequisite model gap: editable destinations
must represent empty instrument/sample slots honestly before import or
generation can land. The cost is a dependency-ordered series of small model,
UI, decoder, and compatibility PRs rather than one importer feature.

Related guidance:

- [Whole-document edit/undo](010-whole-document-edit-undo.md)
- [Post-v1 AUv3 direction](011-post-v1-auv3-tracker-instrument-direction.md)
- [Editable document save/export model](../design/editable-document-save-export-model.md)
- [Instrument Editor](../design/instrument-editor-window.md)
- [Sample Editor](../design/sample-editor-window.md)
- [Synthetic XM fixture pack](../design/synthetic-xm-reference-fixture-pack.md)
