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
- Fine/extra-fine source eligibility builds one planning-only scalar pitch/cut
  index per adapted plan. Source-event identities remain generation keys;
  strict-before position lookups reuse the existing lifetime predicate without
  rescanning song-wide pitch histories. G17/G18 semantics and runtime/window
  delivery are unchanged; no index survives into a replacement plan or callback.
- Nonzero Fxx speed/BPM commands govern their own row from tick 0 through the
  shared frame plan, including runtime event application and sample-time follow.
- Regular `1xx`/`2xx` directional memory is admitted by executed nonzero ticks.
  Effective speed-1 rows neither seed nor replace it; `100`/`200` replay only
  admitted history. Linear and Amiga `1xx`/`2xx` share this admission rule.
- G27 Amiga `1xx` subtracts `16 * resolved parameter` per nonzero tick; `100`
  replays independent upward memory without restarting a source. G30B adds native
  UInt16 storage and the signed upward minimum of 1 (VTX period 4). Downward
  slides have a distinct signed-threshold rule and continue beyond that threshold.
- G25 Linear `0xy` in-range tick ordering is closed. Ordinary tick zero uses base pitch;
  later ticks select `[base,x,y][(effectiveSpeed - tick) % 3]` using command-row
  Fxx timing. `000` is inert with no parameter memory; pitch updates retain the
  source generation/cursor. G30A owns conversion precision; G30B's bounded inverse
  projection gives B-7 `037` periods 1540/1540. The base phase remains unprojected;
  an X/Y phase projects even when its selected nibble is zero.
- Retained-source arpeggio row handoff restores canonical pitch before the next
  row's writer. Pure volume-column Bx output is held through the first arpeggio
  tick zero; subsequent phases and blank/000 exits use canonical pitch. Incoming
  arpeggio/fine writers subsume the prior exit across delivery/history consumers,
  retaining its raw diagnostic evidence.
- Instrument autovibrato now composes one independent canonical-tick delta after
  each ordered ordinary native pitch intent, with folded births and causal blank-tick
  delivery through the existing C step protocol. Playback-only metadata interpretation,
  symmetric rounding, bounded sweep/release and retained-source bounds follow the
  [approved VTX policies](design/xm-final-pitch-publication.md). The bounded G32
  contract is closed by maintainer acceptance; its approved intentional reference
  differences remain explicit.
- G02 new-source onset uses an independent C voice multiplier from zero to the
  existing target over 240 output frames at 48 kHz / 220 at 44.1 kHz. Source
  timing/cursor and final targets remain independent, including silent/zero-step
  births and window continuation. Its bounded contract is closed after passing
  CI and Gregory's independent listening acceptance. G03 song retirement now
  uses the same C-owned 5 ms interval with current-value `1-k/N` output, one
  deadline per displaced generation and retained physical pitch/cursor. Its bounded
  contract is closed after [PR #510](https://github.com/syncomm/voodootrackerx/pull/510),
  green CI and Gregory's listening acceptance. G21 offline retrigger-tail
  reconstruction and the historical at-most-one-LSB PCM16 host/offline musical-study
  residual remain open. Its cause is unproven and distinct from #512's fixed
  strict Float32 test failure. See the
  [onset contract](design/xm-reset-output-ramp.md#g02-new-source-onset).
- G05 represented XM song sources join the single C-owned final mono/L/R
  authority at valid birth, including zero initial gain; previously plain sources
  receive sparse changed targets under existing ordinary tick-length/quick 5 ms
  policies. The bounded final-output admission contract is closed after merged
  [PR #512](https://github.com/syncomm/voodootrackerx/pull/512), green native arm64
  CI and Gregory's October 27, 2026 bounded musical-listening acceptance.
  G02/G03/G04, G32 physical IDs/order, exact source/keymap identity and generic
  non-XM/editor-preview ramp policy remain protected.
- G26 Amiga `0xy` is closed for in-range quantized pitches. It reuses G25's
  phase selector and the existing Amiga note/finetune lookup and sample-step
  conversion. Tuning, relative-note/octave crossings, effective Fxx speed,
  retained/released sources and both-rate delivery are pinned. Paired Release
  planning/cache checks and startup attribution pass; the overall product
  ≤1 s startup target remains outstanding. `000` remains inert. G30B closes bounded
  extreme projection; broader modulation interactions remain G39, without
  a universal Amiga pitch-parity claim.
- G30B ordinary mapped-note admission uses UInt8 note-plus-relative arithmetic:
  1...119 starts PCM with lookup pitch, 0 starts PCM retaining current/base pitch,
  and 120...255 refuses source replacement. Exact raw-note routing precedes pitch
  admission. Refusal preserves generation/cursor/pitch and latent tone state while
  independently applying proven instrument resets to the retained source. Explicit
  instruments restore the sounding cache before later volume/pan writers; immediate
  note-only refusal does not reset. EDx classifies and resets at actual dispatch.
  Cold effective-zero PCM receives an existing explicit zero-step update before
  its first rendered frame. No C DSP or callback change is involved.
- G30B Amiga ordinary lookup spans VTX periods 88...116096. Shared native-word
  slide arithmetic and direction-specific tone comparisons preserve in-range
  units, timing and memory; zero-speed tone execution can still clamp a crossed
  target. Arpeggio projection and Amiga vibrato UInt16 wrap remain distinct
  policies. G30A supplies downstream quantization/conversion unchanged. The
  combined bounded G30 contract is closed; broader pitch interactions remain open.
- Cold Amiga E10/X10 apply the upward signed minimum to owned current pitch
  even with zero amount and no memory provenance. Completed/empty semantic
  owners clamp without fine-pitch PCM publication; unowned channels stay absent.
  Cold Amiga 100 applies the same signed-negative clamp on its first nonzero
  tick without seeding memory. Both-rate combined G30 verification covers these
  consumers; G31 remains separate.
- G19 E90 is a special row-entry source trigger at cursor zero, with no interval
  memory. Instrumentless rows carry volume, pan, envelopes, release/fadeout and
  effect memory; explicit instruments resolve the exact note map and reset once
  before same-cell overrides. NOTE_OFF suppresses the start. Cold/unavailable
  routes create no source; completed sources can restart from retained identity.
  Nonzero E9 and Rxy retain their separate contracts; mixer ramps are unchanged.
- Rxy G20–G22 is closed: independent zero-initialized mode/speed bytes and a
  persistent channel counter survive source absence and order/loop transitions.
  Each eligible invocation increments the counter; reaching the interval resets
  it and executes. Interval zero executes every invocation. Volume-column
  tick-zero gating follows the pinned FT2 dispatch; memory always resolves.
  R restarts the exact retained route at cursor zero while carrying envelope,
  release/fadeout and effect state. Instrument triggers reset the counter,
  preserving nibble memory; note-only starts and E90 preserve it.
  Initialized source-less channels retain semantic volume changes. Only the
  fully uninitialized bookkeeping mutation is excluded as C: the first
  note+instrument resets it before observable output. G21 runtime/offline
  retrigger-tail reconstruction remains separate debt; runtime uses G03's 5 ms
  retirement. Exact integer volume modes cover all inputs 0...64; mode 6 sums
  separately truncated `v/2 + v/8 + v/16`, correcting 32→22. G20 memory and
  G21 execution/carry semantics are unchanged.
- G23 instrument-only `ED1...EDF` selects the valid carried instrument at row
  entry, then dispatches the retained note through its exact map at tick x.
  Represented routes start one new cursor-zero generation and reset defaults,
  envelopes, key/fadeout and permitted modulation phases then. Empty routes
  retire the old source without PCM; cold channels invent no retained note.
  Explicit column volume/pan setters follow the delayed reset; ordinary slides
  keep their nonzero ticks and fine/Ax tick-zero writers are skipped. Out-of-row
  delays keep the owner without a delayed reset/start; instrument-only ED0
  resets immediately without restarting. Ordinary delayed notes, Rxy and mixer
  ramps are unchanged.
- G24 note97/raw `K00` selects the carried owner, releases once, restores
  admitted cached defaults, then applies volume/pan writers. Raw K00 suppresses
  ordinary starts and skips instrument reset; note97+K00 is one release.
  Source/cache/envelope ownership and cursor stay unchanged. Nonzero Kxx uses
  the low five bits after that tick's column writer: K21 releases at tick 1,
  K20 has no nonzero invocation, and out-of-row releases are omitted while
  ordinary row-entry resets remain. Cold releases carry key/fadeout into later
  note-only consumers without a source; channel finalization runs once per tick.
  The bounded G24 contract, both-rate canonical-host delivery and startup
  attribution gates are closed. The overall product ≤1 s startup target remains
  outstanding; G24 does not change startup architecture.
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
  Direct and carried volume factors use signed Q8 slopes with exact point
  reassignment under the bounded G31 contract. Pan retains Float interpolation;
  volume-Lxx loop/end positioning and cold before-first initialization remain open.
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
  Pan-clock/Q8 quirks, static pan law (G40) and broader onset interactions remain open.
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
- Supported same-cell note+instrument tone portamento restores the retained
  sounding-header volume/pan, restarts its enabled envelopes, restores key-on
  and full fadeout, then applies explicit writers. Sounding metadata, generation and
  cursor stay retained; carried instrument and target pitch are independent.
  This covers 3xx/5xy/volume Fx in both modes. G28 Amiga 5xy composes existing
  3xx progression with the shared A/5/6 writer; Fx stores its nibble << 4 in
  shared tone-speed memory. Cold 500 and F0 reuse their established zero/replay rules.
- Tone targets are latent channel state. Ordinary mapped triggers replace the
  sounding source without clearing the target or tone speed; existing note-only
  carry and explicit-instrument default/reset rules remain intact. Later 300 can
  resume on the new generation. Explicit 3xx/5xy/Fx
  notes replace the target and latch a channel-owned period direction. Equality
  installs no direction; unrelated pitch/source changes preserve it. Later
  300/500/F0 consumes that latch. An executed target clamp leaves the
  higher-period direction latched; implicit zero speed can clamp a crossed
  target without creating speed memory. G29 pitch writers preserve this state.
- Cold supported note+instrument tone portamento restores volume 0/pan 128
  without a source/header cache. Instrument, neutral target and speed still carry;
  explicit writers follow. Later ordinary note-only starts its exact mapped source
  while carrying tracker volume/pan and clocks. Declared empty headers retain
  their own defaults; completed/released retained-source reset stays distinct.
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
- Global-volume target projection carries only output volume beside immutable
  row references, materializing complete diagnostic controls only for a target
  publication. This temporary plan-local representation preserves Gxx/Hxy
  channel-turn visibility, source-generation held gains and all G12/G13 semantics;
  canonical channel-state/snapshot width and runtime delivery are unchanged.
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
  retriggering or changing tone admission. G28 reuses this same volume half
  for Amiga; conversion/range policy and broader pitch interactions stay separate.
- G16 EAx/EBx execute once at tick zero with independent per-channel up/down
  memories. Seeded EA0/EB0 replay their own amount; cold forms restore output
  from base and publish a differing held target without creating memory
  provenance. Clamps, silent routes and trigger/order carry preserve those
  memories. Cold H00 remains intentionally inert; A00/500/600 stay unchanged.
- G17 Linear E1x/E2x own independent per-channel directional fine-pitch memories.
  Seeded E10/E20 replay once at tick zero. Cold forms leave canonical pitch
  unchanged and restore a differing held output from it without provenance.
  Converged targets deduplicate; uninitialized and completed sources receive no
  step publication or new voice. FT2's source-less cold-E10 0→1 clamp artifact
  is intentionally omitted. G29 extends these same stores to Amiga.
- G18 Linear X1x/X2x own independent per-channel directional extra-fine memories,
  separate from E1/E2 and regular/tone/modulation state. Seeded X10/X20 replay
  once at tick zero. Cold forms perform zero arithmetic and restore meaningful
  canonical pitch to held output without provenance. Converged targets deduplicate;
  empty/completed routes cannot receive C step writes or a new voice. Uninitialized
  pitch stays absent, intentionally omitting FT2's cold-X10 0→1 clamp artifact.
  Parent units/ranges remain unchanged; G29 shares these stores with Amiga.
- G29 in-range Amiga E1x/E2x and X1x/X2x execute at tick zero through the
  existing fine/extra-fine memories: fine uses ±16 times the resolved nibble,
  extra-fine ±4, in VTX's 4x period domain. Same-cell forms fold into one
  ordinary trigger; no-note forms retain source/cursor and silent semantic
  ownership. Same-cell E5 uses `16 * nibble - 128` through the existing exact
  mapped note lookup, preserving relative note and ordinary defaults/reset.
  No-note E5 is inert with no memory or later-trigger retune. All five writers
  preserve latent tone target/direction/speed. Both-rate whole/window/core/host
  checks and reference audio pass with known onset/interpolation residuals.
  G30B closes bounded range/minimum separately; universal Amiga parity remains open.
- G30A closes valid-domain Linear finetune quantization and shared reference-step
  conversion: `7680 - 64*(effectiveNote-1) - 4*floor(finetune/8)` and a Q16
  sample step converted exactly to Double. Existing pitch consumers share that
  adapter authority at 44.1/48 kHz, with zero sustained cursor drift. Source
  admission, carried periods, signed arithmetic, extreme target/direction and
  arpeggio projection are owned by G30B above and verified together under the
  closed bounded G30 contract. C DSP, onset,
  interpolation rounding and generic 32-frame ramps remain separate from G03
  song retirement.
- G33 Pxy now uses the native adapter's ordered nonzero-tick pan writer and own
  channel byte, feeding the existing G06/G07 and final-output path. Speed 1 does
  not admit memory; pan-only commands preserve held global gain. Qualification
  and maintainer musical listening remain pending; G40/cold/pan-clock boundaries
  and legacy-engine cleanup remain separate.
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
- Instrument Editor and tracker audition use the exact keymap. Song playback
  and product audio export honor present exact maps; ordinary explicit-note
  adapter paths and some tone targets still request `.firstPlayableSample` when
  the map is nil. Note-only, E90 and retained-source restart use `.fail`.
  Ordinary instrument-only cells restore cached defaults without selecting a
  sample; nonzero instrument-only EDx uses the strict retained-note path.
  Selected sample remains editing focus; Sample Editor audition alone resolves
  that represented selection directly. Both mapped and direct preview retain
  positive-header availability, distinct from song represented-PCM eligibility.
- Exact mapped declared-empty ordinary ED0/in-row EDx cuts the prior source at
  dispatch and applies the header/default/reset state without new PCM or fallback.
  Represented PCM with header volume zero is a different source condition;
  represented ED zero-volume gain carry remains a separate open discrepancy.
- Noncanonical short/partial loaded XM headers can yield nil maps with PCM.
  Loader reachability is observed; no read-only fallback exception or abnormal-file
  FT2 playback semantics is verified. Current fallback is legacy behavior, not a
  no-fallback gate pass. [Accepted Policy B](decisions/012-from-scratch-instrument-sample-composition-model.md#accepted-superseding-routing-clarification-policy-b)
  is binding routing authority; deployed fallback differs, leaving the absent-map
  implementation/compatibility gap OPEN. The separate `VTX-J-002`
  Clear Song Data bridge can carry nil-plus-PCM into editable state; its admission
  and the writer's nil-to-S01 conversion remain [open boundary concerns](design/editable-document-save-export-model.md#export-xm).
- Sample import accepts the currently supported WAV/WAVE, AIFF/AIF, AIFC, and
  native FLAC subset through one validation/decode/normalization path. A
  successful import owns canonical mono 16-bit PCM in the document, retains no
  source path, revalidates asynchronous state, and commits once through
  `applyEdit`.
- Current stopped-editable metadata includes instrument name and selected-sample
  panning, volume, relative note, and finetune. Preserved envelope/autovibrato
  controls remain read-only; preserved autovibrato metadata now drives playback.

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
