# ADR 012: From-Scratch Instrument And Sample Composition Model

## Status

> Superseded in part by [ADR 013](013-visible-keymap-ownership-projection.md), which replaces only
> the transient full-map graphical-selection and ownership-display direction below. The canonical
> 96-note document map, `applyEdit`, lifecycle, ownership, and persistence decisions remain in force.

Accepted as the product and architecture contract for the from-scratch composition workstream. Empty instruments,
first-sample generation/import, and occupied LOAD with Replace/Add as New/Cancel are now implemented. Add appends
and selects represented S02+ without changing keymap references. Instrument Editor now exposes inclusive
selected-sample keymap range mutation through one manual `applyEdit` sheet; graphical selection,
drag-to-paint/automatic mapping, and broader destructive lifecycle remain future work. Clear represented sample in
place is now the first implemented destructive sample lifecycle action. The post-alpha sparse sample-slot XM
round-trip and loaded-source provenance foundations support that action without changing the file format.
The shared sample-slot presentation/selection foundation is also implemented: editable and supported loaded
sources can expose a canonical empty Sxx identity without fabricating a `PlaybackSample`. Sample Editor LOAD and
SINE can now populate the exact selected canonical empty identity in a stopped editable document. Duplicate now
deep-copies a represented sample to the next tail identity without mapping it or filling a sparse hole.

## Context

VTX 1.0 is a self-contained XM-style sample/instrument tracker. A user must be able to begin with a clean launch,
create playable material, compose and arrange a song, and produce both XM and rendered audio without first opening XM.

The current app provides blank pattern/order composition, isolated note audition when represented PCM exists,
editable metadata, Export XM, and WAV/M4A export. Creation/import/generation and range mutation are implemented;
represented-sample Clear is implemented, while broader destructive lifecycle and graphical/automatic assignment
are not.

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
from represented samples. Missing identities remain absent from the editable model and are projected to ordinary XM
zero-length sample headers only while exporting the supported subset.

### Sparse Sample-Slot XM Round-Trip Boundary

The editable model and Export XM preserve the interior-gap state produced by non-compacting Clear:

- `PlaybackInstrument.samples` contains only represented `PlaybackSample` values. A sample's stable identity is its
  zero-based `sampleIndex`; `availableSampleSlots` projects those identities as one-based S01...S16.
- File New's empty S01 is a represented instrument with `samples == []`, `noteSampleMap == nil`, and document
  selection at S01. It is not a zero-length `PlaybackSample` and owns no fabricated sample metadata.
- S02+ append uses `BlankTrackerDocument.nextAppendSampleIndex`, which chooses one past the highest represented
  index, never fills a gap, preserves the keymap, and refuses indices outside `0..<16`. At most 16 represented
  samples are supported per instrument.
- An instrument with represented indices `[0, 2]` therefore expresses S01 + empty S02 + S03 without renumbering
  S03. A 96-entry keymap may still contain `1`, and `BlankTrackerDocument.selection` may still be S02. No parallel
  empty-sample object is required for that interior case.
- The shared population policy recognizes the exact selected `.emptyDestination` in the editable projection,
  bounded to S01...S16 with valid represented identities, capacity, and keymap structure. It installs one
  `PlaybackSample` at that zero-based identity without filling another gap, compacting later samples, or changing
  selection. Represented LOAD still offers Replace/Add as New/Cancel, and Add still appends after the highest
  represented identity.

Selection is stored in the `BlankTrackerDocument` value even though ordinary row selection is UI state and creates
no edit. Whole-document `applyEdit` snapshots therefore include selection whenever an action does change it.
`SampleSlotPresentationProjection` is the UI-independent distinction between a represented sample and an empty
destination; the empty case carries only a bounded zero-based identity and never a `PlaybackSample`. For editable
instruments it exposes the contiguous S01-through-highest span required by represented indices, a canonical
96-entry keymap, and a valid selected S01...S16 identity, capped at S16. A zero-sample instrument therefore exposes
only empty S01. Dense instruments expose represented rows only; capacity does not create a future append row.
The existing occupied LOAD -> Add as New workflow creates the next represented identity before it appears.
Shared normalization preserves any requested row in that projection, including an interior empty identity, and
otherwise uses the existing first-eligible/S01 fallback once during instrument or document transitions. Selecting
a row changes no revision, keymap, pattern, represented sample data, or undo history.

Loaded/read-only projection is deliberately more conservative: it exposes represented identities and missing
identities only when source provenance proves zero decoded payload plus the exact canonical all-zero 40-byte
header. Exact keymap references become visible when that canonical source identity is proven; a map value alone,
incomplete provenance, or a noncanonical zero-length header does not synthesize an empty row. Loaded lists add no
append destination. Clear is editable-only and therefore never mutates loaded/read-only projection. In the editable
document it retains the exact selected Sxx as an empty destination and restores that same selection through
undo/redo.

`EditableXMWriter` sorts and validates represented identities in `0...15`, validates an explicit map as exactly 96
entries in the same range, and serializes through the highest represented or referenced identity. Missing positions
inside that span receive one canonical 40-byte all-zero sample header and no payload. The placeholder has zero
length/loop coordinates, zero volume/tuning/type/panning/reserved bytes, and an empty name; it is structural XM state,
not a `PlaybackSample`. Map bytes are written directly, so canonical sample index equals XM output index. A true
zero-sample instrument with no explicit map keeps the existing 29-byte header.

On reopen, `PlaybackSongBuilder` omits zero-length headers while retaining later enumerated sample indices and every
map byte. `[0, 2]` therefore reopens as represented S01/S03, an S02 route remains unavailable with no fallback, a
trailing reference to empty S02 remains exact, and a represented instrument with no samples but a map to S01 also
survives with supported instrument metadata. Dense alpha.1 output is pinned byte-identically. Duplicate, malformed,
out-of-capacity, non-finite, and existing payload/loop/envelope errors still fail before atomic replacement.

The normal XM instrument walker records one source-only provenance entry for every parsed sample-header index. Each
entry proves that a header existed, records its decoded payload length, and classifies it as canonical only when the
declared sample-header size is exactly 40 bytes and all 40 bytes are zero. The metadata remains on `PlaybackSong`; it
does not create a `PlaybackSample`, enter editable document state, or retain a source path or raw module blob.

`LoadedModuleEditableCopyCoordinator` now admits a missing identity only when provenance covers the exact writer-
required span in index order and every missing entry has zero payload plus the canonical classification. Existing
Linear-table and writer dry-run requirements still apply. Interior S02, trailing mapped S02, and only-empty mapped
S01 VTX exports can therefore reopen, become untitled editable copies, and re-export byte-identically without
compaction, remapping, or fallback. Shared selection may now retain a provenance-backed canonical empty row;
absent or unsupported rows still use the canonical fallback. A named, metadata-bearing, extended, or
otherwise noncanonical zero-length header remains copy-unavailable. This is not general zero-length-sample support or
an expansion to arbitrary XM editing.

Implementation evidence is in `PlaybackModel.swift` (`PlaybackInstrument` and
`PlaybackInstrumentSampleResolver`), `BlankTrackerDocument.swift` (`makeDefault`, `nextAppendSampleIndex`,
`clearSample`, and selection normalization), `EditableXMWriter.swift` (`exportedInstrument` /
`validatedNoteSampleMap`),
`PlaybackSongBuilder.swift` (`loadXMInstrumentState`), and `LoadedModuleEditableCopyCoordinator.swift`.
Characterization and round-trip coverage is pinned by
`testAppendSampleNeverFillsGapsAndRejectsInvalidOrMaximumSampleWithoutMutation`,
`testInteriorEmptySampleIdentityRetainsSelectionAndKeymapReferenceWithoutFallback`,
`testSparseInteriorGapWritesCanonicalPlaceholderAndReopensExactIdentityAndMap`,
`testOnlyEmptyMappedSlotPreservesInstrumentMetadataMapAndUnavailableRoute`,
`testClearedInteriorSampleReopensCopiesAndReexportsByteIdenticallyWithExactIdentityAndMap`,
`testClearingOnlyMappedSamplePreservesInstrumentMetadataAndMapThroughReopenAndCopy`,
`testClearingHighestUnreferencedSelectedSampleKeepsSessionDestinationButDoesNotExtendSerializedSpan`,
`testTrailingReferencedEmptyCanonicalSlotStillRecoversAsEditableCopy`, and
`testNoncanonicalZeroLengthSourceHeadersRemainUnavailableForEditableCopy`. Existing
`testAddAudioSampleIsOneApplyEditActionWithExactSelectionUndoRedo` proves the whole-snapshot selection behavior for
the shipped append action.

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

Populating neutral File New/New Instrument S01 (`samples == []`, `noteSampleMap == nil`) initializes the all-S01
96-note map. An existing explicit map is meaningful state and remains byte-exact even when the populated destination
is the instrument's first represented sample. S02+ is never auto-mapped. Sample 1 remains the implicit/default
assignment, and all-S01 has a neutral keyboard appearance. Adding S02 or later never changes mappings; later samples
need explicit assignment.

Mapping and transient audition highlight are separate layers. Keymap mutation uses `applyEdit`/undo; read-only
visualization landed first, followed by an explicit selected-represented-sample
C-0...B-7 inclusive range sheet. Selection and notes outside the range remain
unchanged; Instrument Editor/pattern playback follows the map while Sample
Editor audition remains direct-selected-sample. `instrument-envelopes-keymap.xm`
is the split-map public reference fixture.

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

This is the implemented represented-sample Clear contract. Sample Editor CLEAR is enabled only for the represented
current selection in a stopped editable document with no conflicting lifecycle sheet or operation. Confirmation
names the exact Sxx, states that PCM/metadata will be removed and Undo can restore it, and counts exact 96-note-map
references when any exist. Confirmation revalidates document identity/revision, selection, target value, and stopped
transport; stale, cancelled, empty, playing, or read-only requests create no edit. One `Clear Sample` `applyEdit`
removes only that `PlaybackSample`, preserves every remaining `sampleIndex` and all 96 map bytes, retains selected
Sxx as `.emptyDestination`, and provides exact whole-snapshot Undo/Redo. A successful refresh invalidates direct
Sample Editor preview of the removed sample without changing the persistent preview graph or song transport.

The same selected Sxx can then be populated in place by LOAD or deterministic SINE. That creates one undoable edit,
preserves every map byte and later identity, and makes existing routes to Sxx available again without remapping.
Undo returns to the exact sparse empty state; Redo restores the represented sample.

XM persistence remains document-semantic rather than selection-semantic. A cleared interior identity survives when
a later represented sample or map reference requires its span; a mapped cleared route remains unavailable with no
fallback. If the highest cleared identity is neither mapped nor followed by a represented sample, the current
editable session can still show its selected empty Sxx, but Export XM does not serialize a header solely for that UI
selection and reopen may therefore expose only the lower represented span.

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
9. Done: add represented-sample clear in place through Sample Editor CLEAR.
10. Done: populate an explicitly selected canonical empty sample destination in place.
11. Done: duplicate a represented sample; add remaining sample rename/replace lifecycle separately.
12. Polish read-only keymap visualization: neutral S01, visible S02+ mapping,
    and a separate active-note layer.
13. Done: add editable keymap range assignment through `applyEdit`.
14. Done: wire explicit selected-sample inclusive range assignment UI and
    non-mutating full-map graphical selection; paint/automatic mapping remain separate.
15. Add reference-preserving instrument and sample move/swap.
16. Run the complete automated and manual from-scratch acceptance slice.
17. Prepare `v0.3.0-alpha.1` docs, notes, checklist, and tag/build instructions.

The graphical range-selection slice is complete. Select later lifecycle, envelope,
loop, drag-to-paint, and automatic-mapping work as separate focused PRs.

The sparse writer/reopen/editable-copy dependency, interior empty-slot presentation, represented-sample Clear,
selected-empty population, and tail-only Duplicate are complete. Move/Swap remains separate scoped lifecycle work.

## Test And Fixture Plan

Future project-owned tests cover an empty instrument/S01 destination; generated
sine and waveform family; mono WAV; stereo mix/left/right; AIFF and FLAC;
common-rate tuning; filename naming/truncation; first-sample all-note mapping;
instrument/sample duplicate and instrument clear-in-place; represented-sample Clear already covers a keymap
reference to a cleared sample; instrument move plus pattern-reference remap; sample move plus keymap
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
- warning UX for clearing referenced instruments;
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
