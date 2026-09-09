# VoodooTracker X Roadmap

This is the single canonical sequencing roadmap. Read
`docs/agent-current-state.md` for present behavior, `AGENTS.md` for permanent
rules, and specialized docs/ADRs for domain detail. Release notes, reports, and
git history preserve completed chronology; do not copy it back into this file.

## Baseline and sequencing rule

Shipped baseline: `v0.3.0-alpha.2 — Sample Lifecycle Alpha`.

The baseline is closed. Current work proceeds in this order:

```text
NOW      documentation authority/context consolidation
NEXT     diagnostic-tool consolidation
THEN     focused Fxx timing correction
         focused Linear/Amiga portamento correction
         residual effects/C-engine correctness
         focused CoreAudio callback RT safety
LATER    native editable Amiga-frequency mode
         remaining pre-v1 product milestones
```

Each line is a separate behavioral contract unless a later approved task says
otherwise. Do not combine playback fixes, real-time architecture, editor work,
or product polish merely because they are adjacent here.

## NOW — Documentation authority and context

Consolidate active authority so that:

- `AGENTS.md` contains durable repository and agent contracts;
- `docs/agent-current-state.md` contains a concise present-tense snapshot;
- this file alone owns milestone order;
- `docs/dev-roadmap.md` remains only a compatibility pointer while references
  migrate;
- accepted ADRs and specialized docs remain authoritative only in their owned
  domains; and
- release notes, reports, and git preserve history without becoming required
  current context.

This documentation task does not reopen alpha.2 and does not change product,
playback, parser, editor, diagnostic-tool, or file-format behavior.

## NEXT — Diagnostic-tool consolidation

Create a minimal unified diagnostic CLI/package skeleton, then migrate one
surface at a time. The planned command families are:

```text
audio_compare
reference_triage
effect_coverage
residual_scan
runtime_trace
corpus_map
```

The organization may be a Python package or `tools/vtx_diag/`; choose the
smallest layout that supplies stable subcommands and testable entrypoints.
`docs/diagnostic-tools.md` owns the inventory, group membership, and detailed
migration plan.

Consolidation constraints:

- Existing script paths remain compatibility wrappers until callers, docs,
  prompts, tests, and maintained local workflows migrate.
- Preserve report schemas, deterministic output, recommendation wording,
  redaction guarantees, and output-confinement behavior.
- Private modules and corpus maps remain local and explicitly supplied. The CLI
  must not add a hardcoded maintainer-local map path.
- `mc_dump` remains the parser/golden inspection tool and
  `vtx_render_bounded_xm` remains the bounded render/export tool unless a later
  explicit design changes either boundary.
- Consolidation changes tool organization, not playback, render PCM, effect
  semantics, parser behavior, or runtime hosting.
- Do not archive or remove a script until its compatibility path and every known
  caller have migrated and its focused tests cover the replacement.

Recommended first PR after this documentation change:

```text
tools: add minimal unified diagnostic CLI/package skeleton with compatibility wrappers
```

## THEN — Focused playback and engine correctness

### 1. Fxx timing (`VTX-CS-001`)

Correct the frame-domain Fxx planner so speed/BPM takes effect on the Fxx row
and agrees with the intended current-row timing model. Keep this a focused
behavioral PR with reference-derived timing tests and updates to
`docs/xm-effect-support.md`.

Do not include portamento, unrelated effect memory, C-mixer DSP, callback
architecture, parser, editor, or viewport changes.

### 2. Linear/Amiga portamento scaling (`VTX-CS-002`)

Correct regular, fine, and extra-fine portamento units across Linear and Amiga
frequency tables using explicit reference-derived expectations. Keep it
separate from Fxx so pitch-rate changes and timing changes can be reviewed and
compared independently.

Do not silently broaden editable Amiga admission or combine this with native
Amiga document creation. Update `docs/xm-effect-support.md` for any support or
parity status that changes.

### 3. Residual effects and C-engine correctness

Use the consolidated diagnostic surface and the canonical effect table to rank
remaining supported-command residuals, effect-memory gaps, and C-engine
correctness issues. Promote one evidence-backed family at a time with focused
runtime/offline and public-fixture tests.

Do not infer behavior from corpus frequency alone, publish private corpus
details, reintroduce a retired runtime backend, or fold parser/viewport changes
into effect work.

### 4. CoreAudio callback RT safety (`VTX-D1-001`)

Move callback-time allocation, payload copying/sanitization, avoidable
collection mutation, and diagnostic construction outside the real-time boundary
while retaining the CoreAudio/C-mixer runtime architecture and observable
playback behavior.

This is a focused real-time-safety tranche, separate from effect semantics and
reference-parity corrections. Verify callback health, runtime/offline output,
stop/restart behavior, and failure fallbacks without treating an RT refactor as
permission for a backend transition.

## LATER — Native editable Amiga-frequency mode

Add native editable Amiga-frequency documents only after Linear/Amiga playback
and portamento semantics are trustworthy. The work needs an explicit document,
writer/export, UI, and compatibility contract. It must not silently convert
loaded Amiga modules to Linear or weaken
[ADR 014](decisions/014-loaded-xm-editable-copy-planning.md)'s current refusal
boundary.

## LATER — Remaining pre-v1 product milestones

After the correctness sequence and native editable Amiga decision, continue the
composition roadmap in small slices:

1. Complete pattern entry for instrument, volume, and effect columns, followed
   by selection/copy/paste and focused keyboard workflow.
2. Extend song/order composition with pattern-length and arrangement utilities
   while preserving stopped editable navigation authority.
3. Add envelope playback/editing and broader instrument/sample metadata through
   `EditableDocumentEditCoordinator.applyEdit`.
4. Add editable loop mode/range before separately scoped PCM/waveform mutation;
   add XI and loaded-to-editable instrument/sample transfer only behind explicit
   compatibility boundaries.
5. Design owned-path persistence before enabling Save or Save As; then consider
   advanced audio-export ranges, stems, and user-facing gain controls.
6. Address focused visualization, module-management, accessibility, and UI
   polish after core composition and compatibility behavior is stable.
7. Perform release hardening: CI/toolchain alignment, performance review,
   packaging, documentation, and public release verification.

These items do not jump ahead of the ordered correctness work:

- MIDI keyboard/pad input;
- Save and Save As;
- broad UI or nostalgia polish;
- graphical keymap redesign, drag painting, or automatic mapping; and
- AUv3 implementation.

Likely v1.x work includes MIDI, recording/sample capture, richer resampling, and
plug-in/audio-input-to-sample experiments. Accepted post-v1 direction remains a
narrow native macOS AUv3 tracker instrument before any general Audio Unit host,
with iPadOS only after headless-engine and contained-UI seams are proven.
[ADR 011](decisions/011-post-v1-auv3-tracker-instrument-direction.md) owns that
direction; it does not authorize current AU targets or change the runtime.

## Roadmap maintenance

- Update this file when scope, order, or verification expectations change.
- Keep completed implementation detail in release notes, public-safe reports,
  accepted ADRs, or git history.
- Keep current facts in `docs/agent-current-state.md`, not in milestone logs.
- Every behavior-changing effect PR includes focused tests and updates
  `docs/xm-effect-support.md` when status changes.
- Generated diagnostics and private evidence remain outside the repository.
