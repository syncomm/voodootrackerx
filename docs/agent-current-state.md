# Agent Current State

This is the concise present-tense snapshot for a new development session. Read
`AGENTS.md` for permanent rules and `docs/roadmap.md` for sequencing. Load
specialized docs only for the domain being changed.

The historical VoodooTracker source is not a repository dependency or canonical
implementation authority. Current decisions come from accepted VTX ADRs,
current design documents, tests, and redistribution-safe project fixtures.

## Shipped baseline

The shipped baseline is `v0.3.0-alpha.2 — Sample Lifecycle Alpha`. Its scope and
verification are closed; do not reopen the release or reconstruct its PR
history in active context. See the
[release notes](release-notes/v0.3.0-alpha.2.md) for historical release detail.

VTX remains an alpha-quality, native AppKit XM-style tracker. The VTX 1.0 goal is
a self-contained sample/instrument composition workflow, not a DAW or plug-in
host.

## Runtime and audio

- Runtime playback uses the CoreAudio DefaultOutput Audio Unit host and the C
  mixer render core. `VTX_AUDIO_BACKEND=c_mixer` and
  `VTX_AUDIO_BACKEND=c_mixer_coreaudio` name the same path.
- The retired `av_audio` value falls back to the CoreAudio C mixer with a
  diagnostic reason; retired AVAudio runtime paths are not supported.
- Swift playback/adapter code plans module events. The C mixer renders runtime
  playback and bounded offline work.
- Offline C-mixer render/export is the deterministic comparison context. Runtime
  capture and smoke checks validate the app host and delivery path; they do not
  create a second playback authority.
- Editor audition uses the existing persistent preview stream, isolated from
  song transport and normal runtime playback.

Use `docs/audio-comparison.md` for reference-render work,
`docs/playback-trace.md` for runtime traces/captures, and
`docs/xm-effect-support.md` for the canonical effect-support table.

## Document and persistence boundary

- Opened modules remain loaded, read-only sources. Audition and audio export do
  not make them editable or grant source ownership.
- Blank documents and editable copies are value-owned. Editable content changes
  flow through `EditableDocumentEditCoordinator.applyEdit`; one user action
  creates at most one labeled Undo edit, while cancelled, stale, invalid,
  read-only, playing, conflicting, and no-op paths create none.
- [ADR 014](decisions/014-loaded-xm-editable-copy-planning.md) owns loaded-XM
  editable-copy planning. Its results are `exact`,
  Profile-v1 `normalized`, or `unavailable`. Exact and approved normalized plans
  create untitled documents; the loaded source remains read-only and untouched.
  A normalized later export may differ structurally. Amiga frequency mode is
  never silently converted to Linear.
- Save and Save As are disabled. `File > Export XM...` is the persistence
  boundary for the supported editable subset; exported files reopen as loaded,
  read-only modules.
- `File > Export Audio` provides non-mutating whole-song 48 kHz Float32 WAV and
  fixed 192 kbps AAC/M4A export for stopped loaded or editable documents. WAV is
  the high-quality/diagnostic format; M4A is the sharing format. Export uses the
  windowed offline C-mixer path, writes only to the selected destination, and
  keeps source ownership and Save state unchanged.

See [ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md)
for the editable composition model and
[ADR 014](decisions/014-loaded-xm-editable-copy-planning.md) for copy admission
and normalization details.

## Sample and keymap lifecycle

- When an instrument has routing, its canonical XM keymap is exactly 96 notes
  from C-0 at index `0` through B-7 at index `95`, and every entry retains its
  exact Sxx identity. A nil map is honest routing absence, not implicit S01.
- Represented and canonical empty S01...S16 identities are stable. Sparse
  identity and routing survive the supported Export XM/reopen and editable-copy
  paths without compaction, fabricated PCM, or fallback redirection.
- Clear removes the exact represented selection in place; SINE or LOAD can
  repopulate that destination. Duplicate appends at the next tail identity.
  Move and Swap transform sample identity, all keymap references, and selection
  together. Successful operations are exact single-edit Undo/Redo transactions.
- Only neutral first-S01 population establishes an all-S01 map when routing was
  absent. Other population, replacement, clear, and duplicate operations
  preserve the existing map.
- The Instrument Editor's manual `MAP RANGE…` action is the current explicit
  assignment surface. The visible ownership strip is only a projection of the
  canonical map; graphical selection/painting is not implemented.
- Instrument Editor, tracker audition/entry, song playback, and product audio
  export resolve instrument + note through the keymap. Selected sample remains
  editing focus and cannot redirect those routes. Sample Editor audition alone
  resolves the represented selected sample directly.
- Sample import accepts the currently supported WAV/WAVE, AIFF/AIF, AIFC, and
  native FLAC subset through one validation/decode/normalization path. A
  successful import owns canonical mono 16-bit PCM in the document, retains no
  source path, revalidates asynchronous state, and commits once through
  `applyEdit`.
- Current stopped-editable metadata includes instrument name and selected-sample
  panning, volume, relative note, and finetune. Preserved envelope/autovibrato
  fields remain read-only or runtime-inert where the specialized design docs say
  so.

## Editor and transport boundaries

- The tracker highlight row is static; the gutter and pattern body share the
  viewport slot model and rendered row geometry.
- For stopped editable documents, `BlankTrackerDocument.currentPosition` and
  `currentPatternIndex` are the song/order navigation authority shared by the
  main window and Song / Order editor. Empty allocated patterns remain visible
  and selectable.
- Pattern-bank viewing is distinct from order assignment. Normal Play follows
  the selected order, Play Current Pattern follows the viewed pattern, and live
  POS/PTN follow is transient rather than an editable document mutation.
- Meaningful editable work is confirmed before New or Open replacement. Clear
  Song Data is stopped-only, confirmed, and undoable. WAV and M4A export share a
  re-entry gate.

## Diagnostic tooling

- Diagnostic-tool consolidation is complete. The package-authoritative
  `tools/vtx_diag` surface has exactly six command families: `audio_compare`,
  `reference_triage`, `effect_coverage`, `residual_scan`, `runtime_trace`, and
  `corpus_map`.
- Migrated script paths remain compatibility wrappers. Tested reference-triage
  archive candidates remain standalone, as do cross-family local corpus
  orchestration, `mc_dump`, `vtx_render_bounded_xm`, fixture generation,
  benchmarking, hygiene, privacy, golden, and release-packaging helpers.
- `docs/diagnostic-tools.md` owns detailed command and helper boundaries. No
  archive or deletion work is required for consolidation to remain complete.

## Accepted post-alpha debt

These confirmed items are unresolved and remain separate focused work:

- `VTX-CS-001` — Fxx timing (accepted HIGH): the frame-domain planner applies
  speed/BPM one synthetic row late and disagrees with current-row timing
  semantics.
- `VTX-CS-002` — Linear/Amiga portamento scaling: the two frequency-table paths
  use inconsistent slide scales, including incorrect fine versus extra-fine
  relationships.
- `VTX-D1-001` — CoreAudio callback real-time safety: the render callback still
  performs allocation/copy and other work that must move outside the real-time
  boundary.

These are post-alpha correctness debts, not reasons to reopen alpha.2.
Documentation/context authority and diagnostic-tool consolidation are complete.
The immediate next behavioral PR is focused Fxx timing correction, followed by
separate Linear/Amiga portamento scaling correction, fixture-backed FT2/XM
effect closure and C-engine correctness, focused callback RT safety, and later
native editable Amiga-frequency mode. `docs/roadmap.md` is the sole sequencing
authority.

## Focused context pointers

- Diagnostic inventory and authoritative command surface:
  `docs/diagnostic-tools.md`.
- Effect status and frequency-table coverage: `docs/xm-effect-support.md`.
- Editable-copy outcomes:
  [ADR 014](decisions/014-loaded-xm-editable-copy-planning.md).
- Tracker viewport behavior: `docs/tracker-behavior-spec.md`.
- Build, fixture, and verification commands: `docs/testing.md`.
- Historical audits and release gates: `docs/reports/`; consult only for the
  specific evidence thread being investigated.
