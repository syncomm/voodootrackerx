# VoodooTracker X Roadmap

This is the single canonical phase/milestone roadmap: completed foundations,
current work, remaining outcomes, and the gates between phases. Read
[agent-current-state.md](agent-current-state.md) for present product/runtime
facts and [AGENTS.md](../AGENTS.md) for permanent rules. Accepted ADRs and
specialized docs own their domains; release notes and git preserve detailed
history.

VTX 1.0 is a self-contained, native macOS XM-style sample/instrument tracker
for creating complete songs from scratch. The current priority is XM/backend
closure. The native editable Amiga decision follows that gate, then the
remaining composition/editor, persistence, visualization, settings/accessibility,
and beta/v1 outcomes. Standalone MIDI is later pre-v1 planning after XM/backend
closure; AUv3 remains post-v1. Shipped portions of later phases remain complete
while their remaining scope waits its turn.

## Project Overview

| Phase / milestone | Progress | Remaining completion boundary |
| --- | --- | --- |
| Foundation and Phase 1 — Core Tracker | Shipped | Preserve the parser, tracker navigation, and audio foundations as later work extends them. |
| Phase 2 — XM Playback, Effects & Backend Freeze | Active | Close in-scope semantics/output gaps, timing and edit authority, callback safety, and the integrated gate; earn the freeze. |
| Native editable Amiga mode | Deferred until Phase 2 closes | Decide the document/writer/UI compatibility scope; delivery requires an approved contract without silent conversion. |
| Phase 3 — Pattern and Song Editing | Composition and live-loop editing shipped; narrow editor gaps deferred | Direct instrument/volume/effect field editing, structured selection/clipboard, and existing-pattern length adjustment; resolve edit/Undo authority without reopening arrangement or loop playback. |
| Phase 4 — Instruments, Samples and Interchange | Creation/import, essential metadata and sample lifecycle shipped; editor/interchange remainder deferred | Instrument Duplicate/Clear/Reorder, envelope/autovibrato controls, manual sample Rename, loop/PCM editing, additional generators, XI and selective transfer. |
| Owned-path persistence and export | XM/audio export shipped; Save / Save As deferred | Approve explicit editable ownership and a tested save/reopen lifecycle; scope advanced export separately. |
| Standalone MIDI | Later pre-v1 product milestone, after Phase 2 | Approve a bounded standalone MIDI v1 contract, implement it, and verify it before Beta/v1; AU-host MIDI remains post-v1 under ADR 011. |
| Phase 5 — Visualization and Analysis UI | Display/follow/diagnostic foundations shipped; live visualization deferred | Live scopes, channel/output activity meters, and focused synchronized analysis UI. |
| Phase 6 — Module Management, Settings, UI and Accessibility | Readouts, theme, navigation and accessibility foundations shipped; remainder deferred | Editable song metadata/module information, user preferences, custom-control keyboard/assistive operation, and focused usability verification. |
| Phase 7 — Beta / v1 Hardening | Alpha verification/distribution established; beta/v1 gate deferred | Revalidate the integrated release scope, performance, compatibility and existing distribution pipeline; close identified release blockers. |
| Post-v1 | Direction accepted; implementation separately gated | Native macOS AUv3 tracker instrument first; general hosting and iPadOS later under their approved boundaries. |

An implemented foundation closes only its stated milestone. Phase completion
requires its remaining outcomes and exit gate; later foundations already in the
product do not move outstanding work ahead of the current phase. Deferred work
below identifies actual gaps or explicit planning decisions. Separately scoped
enhancements need an approved release scope before becoming acceptance criteria.

## Baseline / shipped foundation

The shipped baseline is **v0.3.0-alpha.2 — Sample Lifecycle Alpha**. Its release
gate is closed. These completion boundaries anchor the project:

| Milestone | Completed boundary |
| --- | --- |
| Foundation / CI | Repository hygiene, native AppKit app, parser harness, public synthetic fixtures, golden snapshots, and basic CI. |
| Core parsing | Supported classic MOD/XM read-only loading, isolated from UI, playback, and editable mutation. |
| Phase 1 — Core Tracker foundation | Blank startup/New, static highlight row, shared gutter/body geometry, wraparound navigation, pattern selection, keyboard note entry, and isolated audition. Narrow editor additions remain in Phase 3. |
| Audio bring-up / deterministic C mixer | CoreAudio-hosted C mixer runtime, shared offline render core, transport/pattern-loop foundation, reference comparison, and runtime diagnostics. Full XM closure remains in Phase 2. |
| Pattern/song and export foundation | Song / Order composition alpha (`v0.2.0-alpha.3`), supported-subset XM export (`v0.2.0-alpha.4`), and whole-song WAV/AAC-M4A export (`v0.2.0-alpha.5`). |
| From-Scratch Composition Alpha | [v0.3.0-alpha.1](release-notes/v0.3.0-alpha.1.md): instrument creation, sample generation/import, essential metadata, manual keymap assignment, and compose/play/export/reopen workflow. |
| Sample Lifecycle Alpha | [v0.3.0-alpha.2](release-notes/v0.3.0-alpha.2.md): sparse sample identities; Clear, exact-slot population, Duplicate, Move/Swap; canonical navigation; explicit editable-copy planning; document-replacement/export safety. |

## Phase 2 — XM Playback, Effects & Backend Freeze (ACTIVE)

Goal: trustworthy FT2/XM semantics, C-engine output, host delivery, and usable
composition playback before freezing the effects/backend surface.
**XM/backend closure is not finished.** Completed foundations close their
bounded contracts; they do not establish full command or audible parity.

### Completed milestones

- Documentation/context authority and diagnostic-tool consolidation are
  complete. The six-family `tools/vtx_diag` surface and compatibility wrappers
  are established; [diagnostic-tools.md](diagnostic-tools.md) owns the inventory.
- Nonzero Fxx timing and supported Linear/Amiga portamento scaling are corrected
  with public regression coverage.
- Shared channel-volume/effect-memory foundations, tremolo `7xy`/`E7x`, and
  shared vibrato including the Amiga vibrato foundation are implemented.
- Envelope/release/integer-fadeout semantics and shared final-L/R output
  foundations are established, including silent channel clocks and resets.
- Instrument-only default restoration and ordinary note-only exact-keymap
  routing/state carry are implemented without fabricated sources or fallback.
- First-Play performance stabilization covers history indexing, runtime queue
  reuse, compact cold-plan ordering/materialization, semantic row/control
  sharing, and the empty-cell construction fast path.
- Causal release-result extraction establishes the architecture seam for causal
  finalization; the remaining whole-song projection is still present.
- [XM support classification](xm-effect-support.md) separates implementation,
  FT2 closure, memory and mode coverage and agrees with the closure matrix.
  The support-status documentation cleanup is complete; compatibility closure
  remains open.

### Outstanding milestones

- Resolve **G01 sample-header/channel-volume gain ownership**, consuming the
  channel output once while preserving cached defaults and existing routing.
- Close remaining evidence-backed FT2/XM commands and cross-cutting output,
  pitch, memory, envelope, trigger/retrigger/cut, and traversal obligations.
  Known families include panning slide, tremor, pattern delay, relevant
  E-commands, volume-column gaps, and remaining loaded-Amiga pitch coverage.
  Audible pan envelopes, instrument autovibrato, onset/replacement/cut behavior,
  and remaining envelope/pitch arithmetic must be resolved or explicitly
  justified within that same compatibility target.
- Deliver live Speed/BPM readouts and stopped-editable timing controls using
  the shared timing authority.
- Reconcile live pattern-entry mutation and Undo authority with the canonical
  edit path while preserving the shipped loop-and-edit composition workflow.
  Related legacy pattern/order value replacements that discard history need
  the same authority reconciliation; their editing capabilities remain shipped.
- Extend private-corpus metadata/inventory tooling for useful prioritization,
  with explicit local inputs and public-safe reporting.
- Close remaining CoreAudio callback real-time safety debt (`VTX-D1-001`) after
  effect-semantic closure, as a separate focused contract preserving playback
  and the current host.
- Rerun the final closure matrix and pass the composition, playback, listening,
  and performance release gate; then establish the effects/backend freeze.

### Current target / exit gate

Every FT2/XM command in the chosen v1 compatibility scope must be implemented
and tested, or explicitly deferred with an accepted, evidence-backed technical
or product reason. Known reference differences and absent fixture coverage
remain open obligations until resolved or justified. The
[closure matrix](ft2-xm-closure-matrix.md) owns detailed gap/dependency evidence;
[xm-effect-support.md](xm-effect-support.md) owns command support status.

Each behavior family requires a public synthetic regression and matched
runtime/offline/window evidence where applicable. Use ft2-clone renders of the
same fixture as the primary FT2 comparison, with other renderers for
triangulation. Private evidence can prioritize work but cannot become a
committed test or release dependency. See [audio-comparison.md](audio-comparison.md).

Exit requires closure of all outstanding milestones above, including the
metadata/tooling work, timing/edit authority, callback-safety verification,
and final integrated gate. Semantic/output closure precedes callback hardening;
both precede the freeze and later product phases. Effects, DSP, host, real-time
safety, and editor contracts remain separate PRs.

## Next milestone — Native Editable Amiga Mode

The native editable Amiga-frequency decision follows Phase 2's correctness and
real-time-safety gate. Loaded Amiga playback is already supported; editable
admission remains deferred. Decide the document, writer/export, UI, and
compatibility scope against trustworthy Linear/Amiga playback before committing
implementation and release requirements. Preserve
[ADR 014](decisions/014-loaded-xm-editable-copy-planning.md)'s current refusal
boundary until an approved change exists; never silently convert Amiga to Linear.

The decision precedes further composition sequencing. It does not, by itself,
make delivery of every Amiga editor feature a new prerequisite for those phases.

## Phase 3 — Pattern And Song Editing

Goal: extend the working small-song composition workflow with the specific
editing capabilities still absent, while preserving its navigation and playback.

### Completed milestones

- Note entry with the selected instrument, key-off, field clearing, and isolated
  note audition are shipped. Tracker cursor navigation includes row/page
  movement, wraparound, field movement, and Tab/Shift-Tab channel movement.
- Pattern Bank viewing and explicit order assignment are shipped, together
  with pattern New, Duplicate, and Clear. Viewing a pattern remains separate
  from assigning it to the arrangement.
- Order Insert, Delete, Duplicate, Move Up/Down, and `PTN -/+` are shipped.
  These operations already support composing multi-pattern arrangements.
- Canonical stopped POS/PTN navigation, Song / Order selection, live playback
  follow, and stop reconciliation are shipped in alpha.2.
- Normal Play/Stop, Play Current Pattern, and Loop-at-Play-start are shipped.
  Editable pattern changes refresh an active loop at its boundary; repeated
  refreshes coalesce, and Stop cancels pending work.

The composition foundation shipped in
[v0.2.0-alpha.3](release-notes/v0.2.0-alpha.3.md); alpha.1 and alpha.2 extend and
validate that workflow. It remains complete within its released scope.

### Remaining milestones

- **Direct field editing:** connect instrument-number, volume-column, and
  effect-column input to actual editable-document mutation. The app currently
  writes notes with the selected instrument and clears fields, but hexadecimal
  input does not commit through its handler. A field-edit helper and helper
  tests do not establish complete app wiring. Use the canonical edit/Undo
  authority resolved in Phase 2.
- **Structured selection and clipboard:** add row/block selection and document
  Cut/Copy/Paste/Select All. The tracker has cursor and display-text selection;
  structural clipboard menu actions remain disabled. Preserve loaded read-only
  behavior, document identity, field boundaries, and one Undo action per edit.
- **Pattern length:** add adjustment of an existing pattern's row count with
  explicit handling of preserved/removed rows, exact Undo, and stable order
  references. New and Duplicate currently retain the existing pattern length.

Live edit/Undo authority remains a Phase 2 obligation. Broader loop ranges or
live retargeting remain separately scoped transport enhancements; the supported
loop-and-edit workflow already works. Additional arrangement utilities or
shortcuts require a concrete gap and scope rather than a generic completion
milestone.

Exit: the approved field/selection/length editing scope works over the shipped
arrangement workflow, with coherent navigation, one edit/Undo authority, and
verified playback and supported export of the resulting composition.

## Phase 4 — Instruments, Samples & Interchange

Goal: complete sound shaping and selective interchange over the shipped
value-owned instrument/sample model.

### Completed milestones

- Instrument/Sample Editor windows, shared selection, real PCM waveform and
  loop displays, and read-only volume/panning-envelope displays are shipped.
- New Instrument and Rename Instrument are shipped. Selected-sample volume,
  panning, relative note, and finetune are editable through exact single-edit
  Undo/Redo; essential metadata editing remains complete.
- SINE generation and WAV/AIFF/AIFC/native-FLAC import are shipped through the
  shared validation and document-ownership path. Imported names derive from the
  filename; occupied LOAD offers Replace/Add as New/Cancel.
- Sparse sample Clear, exact-slot population, tail Duplicate, Move To, and Swap
  are shipped. They preserve or atomically remap exact sample/keymap identities
  through the alpha.2 lifecycle contract.
- Manual `MAP RANGE…`, the visible ownership projection, computer/on-screen
  instrument audition, and direct selected-sample audition are shipped.
  Persistent preview remains isolated from song transport.
- Supported whole-document loaded-XM editable-copy planning is shipped with
  exact, approved normalized, and unavailable outcomes under ADR 014.

### Remaining milestones

- **Instrument lifecycle:** add instrument Duplicate, confirmed Clear in place,
  and reference-preserving reorder. New/Rename Instrument and the sample
  lifecycle above are already implemented. Instrument moves must preserve
  pattern references and the complete sample/keymap value.
- **Envelope and autovibrato controls:** make represented envelope points,
  enable/sustain/loop/fadeout state, and autovibrato parameters editable through
  `applyEdit`. Current displays/selectors work, while mutation controls remain
  disabled. Playback semantics and audible compatibility close in Phase 2.
- **Sample loop editing:** enable loop mode and start/end adjustment over the
  real sample display. Current loop controls are read-only; reuse document
  validation, preview, and exact Undo rather than adding an audition path.
- **Basic PCM editing:** add waveform-region selection and separately scoped
  trim/crop, cut/copy/paste, normalization, reverse, and fades. The edit bank
  remains disabled. Preserve unaffected PCM, loop bounds, identities, and
  reversible document state for each operation.
- **Manual sample naming:** add Rename Sample. Filename-derived import naming
  and existing sample selection/lifecycle behavior remain complete.
- **Additional generators:** add deterministic square, triangle, saw, and noise
  through the existing generation/edit path. SINE remains the implemented
  generator; the other controls are disabled.
- **XI and selective transfer:** add XI instrument import and selective
  instrument/sample transfer between instruments or from existing modules into
  value-owned songs. These need explicit compatibility/ownership contracts.
  Same-instrument sample Duplicate, audio import/Replace, and supported
  whole-document Make Editable Copy remain shipped.

Graphical range selection, drag painting, and automatic mapping remain later
focused editor work under ADR 013. Move Up/Down sample convenience controls
remain deferred over the existing Move/Swap transaction. Scope these additions
separately without reopening manual mapping or the completed sample lifecycle.

Exit: usable instrument/sample creation, editing, and interchange with exact
routing, Undo/Redo, and supported XM round-trip preservation for the approved
phase scope. [ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md)
owns composition/sample semantics; [ADR 013](decisions/013-visible-keymap-ownership-projection.md)
owns the current display-only ownership projection and supersedes the older
graphical-selection direction. Editor design notes own the bounded control
contracts; they do not change the playback or loaded-source boundary.

## Pre-v1 milestone — Owned-Path Persistence And Export

Supported-subset XM export/reopen and whole-song WAV/M4A export are shipped.
Document replacement confirmation, undoable Clear Song Data, and export
re-entry protection are also shipped. Save / Save As remain disabled, and an
exported file reopens as a loaded read-only module. The owned-path lifecycle
contract is still to be designed and approved.

Remaining work follows the composition/editor phases:

- Approve the owned editable-document path, format, and lifecycle contract
  before enabling Save / Save As, building on existing replacement safety and
  defining unsaved-work and future owned-path behavior explicitly.
- Deliver saving and reopening supported compositions without acquiring or
  overwriting a loaded source path implicitly.
- Scope advanced audio-export options separately: ranges, stems/channels,
  encoding/quality choices, and user-facing gain controls. Current whole-song
  Float32 WAV and fixed AAC/M4A export remain complete; the chosen advanced
  options need a release-scope decision.

Exit: explicit ownership and tested save/reopen behavior. The
[save/export model](design/editable-document-save-export-model.md) owns the
current boundary. This milestone does not select or expand a native format.

## Pre-v1 Milestone — Standalone MIDI

Standalone MIDI keyboard/pad input is a later pre-v1 product milestone after
Phase 2's XM/effects/backend closure gate. Computer-keyboard and on-screen
audition are shipped; hardware MIDI input is not implemented. AUv3 and AU-host
MIDI remain post-v1 under ADR 011.

Delivery sequence:

1. Approve a bounded standalone MIDI v1 contract covering supported hardware/
   input paths, instrument/note routing, audition versus pattern-entry behavior,
   the approved velocity/controller policy, and acceptance criteria.
2. Implement only that approved standalone MIDI v1 subset.
3. Verify the implemented contract before the Beta/v1 gate, using deterministic
   checks where applicable and appropriate hardware/input validation.

Full MIDI recording, sample capture, broad controller automation, and workflows
beyond the approved v1 subset require separate scope approval.

## Phase 5 — Visualization And Analysis UI

### Completed foundations

- Sample Editor real PCM waveform/loop overview and Instrument Editor
  read-only envelope graphs are shipped.
- Tracker cursor/viewport behavior and live POS/PTN playback follow are shipped.
- Runtime/export diagnostics already expose useful audio evidence, including
  RMS/peak data. A diagnostic value is a foundation for product visualization.

### Remaining milestones

After core composition and compatibility behavior are stable, deliver live
playback waveform scopes, channel/output activity meters, and focused
tracker-friendly analysis/feedback surfaces. Dedicated live scope/meter product
views remain absent; existing sample displays and playback follow stay complete.

Exit: useful, synchronized playback feedback built on the existing audio and
follow authorities, preserving tracker geometry and callback safety.

## Phase 6 — Module Management, Settings, UI & Accessibility

### Completed foundations

- Module/control-panel readouts, instrument/sample metadata surfaces, editor
  windows, shared controls, and the initial visual theme are shipped.
- Tracker keyboard navigation and focused computer-key/on-screen audition are
  implemented. Existing editor controls expose accessibility roles, labels,
  values, and selected actions with focused test coverage.
- The tracker reads a stored beat-accent interval. This small preference
  foundation does not provide a user settings window.

### Remaining milestones

- Add editable song-title and focused module-information surfaces over current
  readouts. Preserve loaded read-only behavior and canonical edit authority.
- Add a user preferences/configuration surface for approved playback, export,
  and display settings. Share the timing authority from Phase 2 and the approved
  export options above rather than defining duplicate settings contracts.
- Extend mouse-driven editor knobs/panning controls with verified keyboard and
  assistive value adjustment, then complete focused keyboard/VoiceOver and
  usability verification across editors. Existing accessibility work remains
  complete within its tested scope.

Broader typography, spacing, theme, and workflow polish remains deferred until
behavior is stable. Review actual usability issues against the established
editor design rather than treating every UI surface as unimplemented.

Exit: coherent settings and metadata behavior plus verified keyboard and
accessible operation. Broad UI/nostalgia polish waits for these earlier gates.

## Phase 7 — Beta / v1 Hardening And Release Gate

Enter after the preceding pre-v1 outcomes are complete or explicitly scoped by
an approved release decision. The alpha composition/lifecycle gates, automated
build/test/hygiene checks, and universal signed/notarized DMG release pipeline
are established foundations. Beta/v1 work validates them against the final
product scope and resolves identified blockers.

Beta/v1 acceptance requires:

- Revalidation of the from-scratch create/import/map/audition/edit/arrange/play/
  reopen/XM-export/WAV-M4A-export workflow, extended with approved editor,
  owned-path Save/Save As, and input outcomes. Verify exact Undo and ownership
  safety across the integrated workflow; preserve closed alpha milestones.
- In-scope FT2/XM closure, protected MOD/XM reading, stable tracker viewport,
  runtime/offline delivery, callback health, and listening/performance gates.
- Passing applicable automated and manual verification, performance/lifecycle
  review, file/privacy hygiene, and verification of the actual beta/v1 app/DMG
  through the existing distribution pipeline. Document compatibility limits
  and resolve demonstrated toolchain, packaging, or release blockers.

Beta validates this integrated scope; v1 requires its release blockers to be
closed and the final release gate to pass.

## Post-v1 Direction

Prioritize a narrow native **macOS AUv3 tracker instrument first**, then consider
general Audio Unit hosting separately. **iPadOS follows macOS** after the
headless engine and contained UI are proven. [ADR 011](decisions/011-post-v1-auv3-tracker-instrument-direction.md)
owns this direction and the separate approval gate for implementation.

Existing later possibilities remain recording/sample capture, richer resampling,
and plug-in/audio-input-to-sample experiments. Each needs separate scope approval;
none is a beta/v1 requirement. Standalone MIDI input planning belongs to the
pre-v1 milestone above; AU-host MIDI follows ADR 011's post-v1 boundary.

## Continuous Architectural Guardrails

- Preserve classic MOD/XM read-only compatibility, loaded-source ownership,
  exact sparse sample identities/keymaps, and accepted ADR boundaries.
- Keep AppKit/Swift orchestration, parser isolation, the CoreAudio C-mixer
  runtime, deterministic offline rendering, and isolated preview responsibilities.
- Route content mutation through `EditableDocumentEditCoordinator.applyEdit`;
  one user action creates at most one labeled Undo edit.
- Keep MIDI, Save / Save As, graphical keymap redesign, broad UI polish, and
  AUv3 behind their gates. One branch/PR owns one focused behavioral contract.
- Maintain this roadmap when milestone scope/order/gates change; keep present
  facts in `agent-current-state.md` and chronology in release notes/git. Effect
  status changes update the canonical support table. Private inputs and generated
  diagnostics remain outside git; public regressions use redistribution-safe fixtures.
