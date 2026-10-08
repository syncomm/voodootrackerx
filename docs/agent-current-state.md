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
- Release semantics are decided once at their execution frame. Current
  whole-song backward trigger/mapping/diagnostic release annotations are an
  immediate mechanical projection of that immutable result.
- Semantic channel rows capture complete immutable controls once. Row grouping
  and history views share those snapshots; per-tick carried-instrument lookup
  uses a compact projection that preserves nil carries and final-row tail fallback.
- Cold adapter plans sort lightweight frame/tick/priority/source/identity keys
  and permute owned event storage in place. Exact payloads and stable writer
  ties survive; categories are collected during construction and sorted
  lexically. Final assembly allocates no second full-width event array.
  Large immutable note-trigger payloads are indirect, and semantic publication
  runs share category storage; neither change alters event values or PCM ownership.
- Runtime queues reuse immutable adapter-event storage through lightweight
  ordered references. Queue replacement/reset keeps references and their storage
  together under the existing render lock, including pattern-loop iterations.
- Nonzero Fxx speed/BPM commands govern their own row from tick 0 through the
  shared frame plan, including runtime event application and sample-time follow.
- Ordinary volume-column `6x/7x` slides update base/output on nonzero ticks of
  the effective Fxx row speed, including silent channel state. Speed 1 has no
  slide; zero amounts restore output without memory. Fine `8x/9x` stay at tick
  zero, and A/5/6 retain their independent memory and writer order.
- Volume-column `Dx/Ex` move stored pan on nonzero ticks of that same effective
  row speed, including silent state. `D0` forces zero; `E0` preserves pan without
  memory or reconversion. G09 feeds current stored pan to the existing envelope
  and final-L/R targets; Cx mapping, Pxy and static pan law remain separate.
- Volume-column `Cx` sets stored pan to `16 * nibble` at tick zero: C8 is 128
  and CF is 240. Header/Cx/8xx precedence, G09 and G06/G07 remain intact;
  header/8xx conversion, preview and final stereo pan law (G40) are unchanged.
- XM envelope/release targets and integer fadeout consume that same tick plan
  in runtime and offline rendering. One C final-L/R state interpolates ordinary
  targets over the current tick and carries in-flight window progress.
  Non-retriggering resets use a 5 ms transition from current audible output
  through that same state. Ordinary instrument-only cells restore the last
  selected declared header's cached volume/pan and reset channel semantics;
  a live source receives the reset without retriggering.
  Carried instrument memory stays separate from the sounding sample. Declared
  empty slots retain source-only defaults/tuning and silent channel clocks, with
  no fabricated sample or voice. Ordinary note-only cells resolve the carried
  instrument's exact keymap, restart represented sources, and carry tracker
  volume/pan, envelope/release state and modulation memory across either route.
  G06 consumes the existing pan segment through that same final-L/R target;
  neutral envelopes preserve static audio. Lxx positions that pan clock when the
  sounding instrument's raw volume-sustain flag is set, including disabled volume
  envelopes. The bounded G07 Lxx panning-envelope positioning contract is closed
  with automated controls and maintainer-reported Xcode/listening acceptance.
  Pan-clock/Q8 quirks, static pan law (G40) and new-note onset parity remain open.
- Offline C-mixer render/export is the deterministic comparison context. Runtime
  capture and smoke checks validate the app host and delivery path; they do not
  create a second playback authority.
- Parent `4xy`/`6xy` execute channel-local memory and phase updates across exact
  empty sample routes without a voice. Later playable `400`/`600` consume that
  state; prior-E4 instrument resets and note-only carry remain intact. Public
  Linear/Amiga and both-rate regressions pin this prerequisite.
- Volume-column Ax/Bx reuse the same 4xy/6xy vibrato memory and pitch engine.
  Ax writes speed at tick zero; Bx writes depth and executes on nonzero ticks,
  before any same-tick 4xy/6xy execution. G10's bounded Linear/Amiga contract
  is closed, including silent routes and runtime/window carry. Broader pitch
  interactions, onset, instrument autovibrato and final pan law remain separate.
- Song gain consumes channel/output volume once with global volume. Sample
  headers initialize/restore cached defaults without another song multiplier.
  Exact mapped represented PCM remains a valid source at header volume 0;
  zero initializes/restores silent channel state without invalidating the route.
  Empty/unrepresented routes remain source-less. Direct editor preview retains
  its existing availability and header/headroom policy.
- Gxx fresh notes capture the global volume visible at their channel turn;
  later same-tick writers do not backfill earlier birth/held targets. Real later
  volume publications compare against the source generation's held target,
  including repeated C40/Gxx and G00 repair. Whole/window/runtime delivery uses
  the same causal events; plain holds and envelope tick refresh remain distinct.
- Nonzero Hxy mutates one song-global volume on ticks `1..<effectiveSpeed` in
  channel order. Explicit channel-turn gain targets can differ and plain targets
  remain held until a volume publication. Volume envelopes/release refresh each
  tick; later notes inherit final canonical state. Runtime/offline/window paths
  share these targets. G12 remains authoritative for resolved Hxy/H00.
  G13 H00 effect-memory replay is closed: independent channel-local whole-byte
  memory, established only by executed nonzero ticks. Cold H00 is a true no-op;
  FT2's zero-memory target-refresh artifact is intentionally not emulated.
- Cold A00 executes a compatibility-supported zero slide on nonzero ticks,
  restoring output from current base volume through causal local publication.
  It creates no Axy/5xy/6xy memory provenance and preserves tremolo/E7 state;
  seeded replay and the distinct cold-H00 no-op policy remain intact.
- Cold 600 retains its zero-slide base-to-output assignment on nonzero ticks
  and declares local publication even when base/output are unchanged. The
  current source's held target refreshes if stale; equal targets deduplicate.
  Slide memory stays absent and vibrato is preserved.
- G15 cold Linear 500 executes the zero-slide volume half on nonzero ticks
  independently of tone target/speed availability. It restores current base to
  output and refreshes a differing held source target without creating memory,
  retriggering or changing tone admission. Partial Amiga 5xy remains open G28.
- G16 EAx/EBx execute once at tick zero with independent per-channel up/down
  memories. Seeded EA0/EB0 replay their own amount; cold forms restore output
  from base and publish a differing held target without creating memory
  provenance. Clamps, silent routes and trigger/order carry preserve those
  memories. Cold H00 remains intentionally inert; A00/500/600 stay unchanged.
- Editor audition uses the existing persistent preview stream, isolated from
  song transport and normal runtime playback.

Use `docs/audio-comparison.md` for reference-render work,
`docs/playback-trace.md` for runtime traces/captures, and
`docs/xm-effect-support.md` for the canonical effect-support table.

## Document and persistence boundary

- Opened modules remain loaded, read-only sources. Audition and audio export do
  not make them editable or grant source ownership.
- Blank documents and editable copies are value-owned. Instrument/sample edits,
  Clear Current Pattern, and Clear Song Data use
  `EditableDocumentEditCoordinator.applyEdit` with at most one labeled Undo
  edit per action; rejected and no-op requests create none. Legacy pattern entry
  and several pattern/order updates still replace document values and clear
  history. Uniform content-mutation/Undo authority is not yet complete; see
  [ADR 010](decisions/010-whole-document-edit-undo.md).
- [ADR 014](decisions/014-loaded-xm-editable-copy-planning.md) owns loaded-XM
  editable-copy planning. Its results are `exact`,
  Profile-v1 `normalized`, or `unavailable`. Exact and approved normalized plans
  create untitled documents; the loaded source remains read-only and untouched.
  Required empty headers with nonzero volume, pan or tuning are unavailable for
  copying because the editable writer cannot preserve those playback semantics.
  Proven inert cosmetic/trailing cases remain normalized.
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
- Note entry writes the selected instrument; key-off and field clearing work.
  Direct hexadecimal field edits are not wired through the app handler. Cursor
  navigation and display-text selection work; structured pattern clipboard
  menu actions remain disabled.
- Pattern New/Duplicate/Clear/assignment and order Insert/Delete/Duplicate/Move/
  PTN-step work. Active editable loops refresh edited pattern data at the loop
  boundary, coalesce newer requests, and cancel pending refresh on Stop.
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

This accepted item retains a separate focused contract:

- `VTX-D1-001` — CoreAudio callback real-time safety: the render callback still
  performs allocation/copy and other work that must move outside the real-time
  boundary.

This is post-alpha correctness debt, not a reason to reopen alpha.2.
Documentation/context authority and diagnostic-tool consolidation are complete.
Nonzero Fxx timing and the supported Linear/Amiga portamento units are corrected.
Current work is fixture-backed FT2/XM effect closure and C-engine correctness;
the [closure matrix](ft2-xm-closure-matrix.md) owns unresolved compatibility
evidence and distinguishes remaining gaps from closed foundations. XM support
classification separates implementation, FT2 closure, memory and mode coverage.
XM/backend closure remains open. `docs/roadmap.md` owns
phase targets, outstanding milestones, and sequencing.

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
