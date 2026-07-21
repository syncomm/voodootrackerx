# VoodooTracker X Roadmap

This is the current PR sequencing guide. It intentionally avoids historical
play-by-play; older audio comparison details live under `docs/reports/`.

For the shortest backend snapshot, read `docs/agent-current-state.md` first.
For effect status, read `docs/xm-effect-support.md`.

## Current Release Status

`v0.2.0-alpha.3` is tagged as the Song / Order editor composition alpha.
`v0.2.0-alpha.4` was the Export XM v1 release for the current VTX editable
subset.
`v0.2.0-alpha.5` is released as the Rendered Audio Export Alpha. It adds
whole-song 48 kHz Float32 WAV export with the VTX render profile, 3-second tail,
auto-headroom, progress, cancellation, and performance diagnostics, plus
AAC-encoded M4A export for convenient sharing. Both formats write only to a
user-selected destination. Loaded modules remain read-only, Save/Save As remain
disabled, and advanced audio export options remain future work.

The proposed next major milestone is the future `v0.3.0-alpha.1` From-Scratch
Composition Alpha. It is not yet released; its complete acceptance gate and
dependency-ordered PR plan are defined by
[ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md).
The first gate slice is implemented: File New represents empty I01/S01 and
`Edit > New Instrument` creates another honest empty destination through one
undoable stopped-editable action.

## Project Goals

- Preserve classic MOD/XM compatibility and tracker workflow.
- Keep the AppKit tracker editor keyboard-first.
- Make playback deterministic enough for local reference comparison.
- Reach VTX 1.0 as a self-contained XM-style sample/instrument tracker that can
  create complete sample-based songs from scratch.
- Keep VTX 1.0 focused on tracker composition, not DAW or plugin-host scope.
- Add visualization and broader modern workflow features only after the tracker
  composition foundation is stable.

## VTX 1.0 Composition Scope

VTX 1.0 should be a real composition-capable tracker, not only a playback,
display, or pattern-entry milestone. The 1.0 target includes:

- song/order editor foundation
- pattern editor support for notes, instruments, volume columns, and effect
  columns
- sample editor and instrument editor foundations
- WAV, AIFF/AIFC, and FLAC sample import in focused phases
- XI instrument import as an explicit target
- importing or copying instruments and samples from existing modules into
  blank/editable songs
- loop-and-edit workflow for building patterns while hearing playback
- save XM
- export WAV/AAC
- continued loaded-module read-only safety, using explicit editable-copy
  bridges before save semantics land

Likely v1.x or later work includes MIDI keyboard or pad input, recording and
sample-capture improvements, richer resampling tools, and plugin/audio-input to
sample experiments.

The accepted post-v1 priority is VTX as an AUv3 tracker instrument inside host
DAWs before VTX attempts to become a general Audio Unit plug-in host. Native
macOS AUv3 comes first; iPadOS AUv3 follows only after the headless engine and
contained UI are proven. AUv3 is the only approved plug-in format in this
direction. The first concept is a narrow Player AU; a Tracker AU may follow.
This is architecture direction, not current feature scope, and major AU
implementation begins only after an explicit post-v1 approval milestone. See
`docs/decisions/011-post-v1-auv3-tracker-instrument-direction.md`.

Other future Pro or native-format work may still explore plugin-to-sample
rendering, automation, a native VTX project format or XM3-style extended
format, AI-assisted instruments/samples/patterns, and separately scoped
third-party plug-in hosting. Classic XM compatibility must not depend on live
plug-in playback.

## Milestone 0: Foundation / CI

Status: done.

Completed scope:

- repo hygiene, license, file checks, and basic CI wiring
- minimal AppKit app skeleton and launch-window reliability
- core parser harness, synthetic fixtures, golden snapshots, and `mc_dump`

## Milestone 1: Core Parsing

Status: read-only XM/MOD foundation is in place and remains the compatibility
baseline.

Current expectations:

- preserve classic MOD/XM read-only compatibility
- keep parser logic isolated from UI and playback behavior
- keep loaded modules read-only until an explicit editable-copy workflow is
  designed and implemented
- add focused parser tests before changing parser behavior
- do not change on-disk/file-format assumptions without a design note,
  compatibility tests, and migration plan where applicable

## Milestone 2: Audio Bring-Up

Status: first-pass XM playback exists, but VoodooTracker X is not claiming
FT2/OpenMPT/MikMod bit-perfect playback.

Current backend state:

- CoreAudio DefaultOutput Audio Unit C mixer is the default runtime backend.
- `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` are
  explicit aliases for that same CoreAudio host.
- `VTX_AUDIO_BACKEND=av_audio` is retired and falls back to the CoreAudio C
  mixer with a diagnostic fallback reason.
- Retired AVAudio runtime paths must not return.
- The C mixer render core is shared by runtime playback and bounded offline
  renders.
- Offline render/export is the reference workflow for comparison.
- Runtime CoreAudio capture and offline render have been shown equivalent for
  tested modules when settings and bounds match.

Authoritative docs:

- `docs/agent-current-state.md` for current backend state and command groups
- `docs/audio-comparison.md` for candidate/reference render comparison
- `docs/playback-trace.md` for runtime trace and capture diagnostics
- `docs/xm-effect-support.md` for effect support status
- `docs/decisions/004-software-mixer-transition.md`
- `docs/decisions/005-software-mixer-core-language-boundary.md`
- `docs/decisions/007-feature-flagged-runtime-c-mixer-backend.md`
- `docs/decisions/008-alternative-runtime-output-host.md`
- `docs/decisions/009-xm-linear-period-sample-base-rate.md`

## Milestone 2.7: Deterministic C Mixer Foundation

Status: active backend foundation.

Done at a high level:

- deterministic C-backed offline mixer foundation
- one-shot, looped, ping-pong, envelope, scheduling, row/tick, and bounded
  parsed-XM adapter render paths
- bounded candidate WAV export through `vtx_render_bounded_xm`
- PCM16 and Float32 WAV export diagnostics
- product whole-song 32-bit Float WAV export UI using the VTX mix profile
- product AAC/M4A sharing export using the same scaled Float32 render output
- `--mix-profile vtx` and `--mix-profile ft2`
- runtime CoreAudio C mixer default selection
- runtime trace and capture diagnostics
- runtime/offline comparison helpers
- transport stop-position preservation and Spacebar play/stop shortcut
- current linear-table effect foundations documented in
  `docs/xm-effect-support.md`

Current comparison policy:

- ft2-clone Linear is the primary FT2-style XM reference when exported with
  matching local settings.
- Use `--wav-format float32 --mix-profile ft2` for FT2-style comparison
  candidates.
- Use `/tmp` for generated WAVs, traces, JSON, Markdown, screenshots, logs,
  and private/local reports.
- Do not put private module filenames, local absolute paths, or private corpus
  details into committed docs.

## Next Backend Targets

The backend is in a temporary foundation freeze so development can return to
GUI, editor, and product milestones. During the freeze, keep backend work
docs/tooling-only unless a freeze-exit blocker is promoted.

Recommended next PR sequence:

The three-part instrument-rich reference-pack milestone is complete. The
existing synthetic generator now consumes a validated schema-v2 manifest and can
generate or verify one/all approved XMs. The new original MIT-licensed
sustained fixture covers 16-bit audition/loops plus loader/model/editable-copy/
current metadata edits/undo/redo and Export XM/reopen without production
parser/writer/runtime changes. The second milestone adds the five-instrument
metadata matrix with exact pan/volume/tuning, 8/16-bit PCM, and all XM loop
modes. The third fixture adds a split two-sample keymap, both envelope headers,
fadeout, and autovibrato without production playback or format changes.

1. Done: build an Instrument Editor shell/read-only binding.
2. Done: add the document `applyEdit`/undo funnel needed before instrument and
   sample mutation.
3. Represented instrument NAME and selected-sample PAN editing through
   `applyEdit` are done, along with panning-envelope/autovibrato preservation
   and the read-only VOL/PAN envelope display. Selected-sample VOLUME now also
   edits exact XM `0...64` values while stopped and feeds the unchanged gain
   mapping on subsequent playback. Selected-sample FINETUNE likewise edits the
   exact XM signed byte `-128...127`; REL NOTE now follows the same boundary.
   Export XM/reopen preserves both, and later playback uses the unchanged pitch behavior.
   Focused Instrument Editor note keys now reuse the shared map, octave/selection,
   availability resolver, and isolated preview sink. The editor closes/reopens through
   normal Song/Order-aligned AppKit lifecycle, its router leaves non-key window events to AppKit,
   and preview activity does not change stopped-editable control eligibility. Editable-copy
   confirmation remains a tracker-window document sheet even when invoked from the editor.
4. Done: the on-screen Instrument Editor keyboard uses exact pitches, note-map routing,
   pointer drag/release lifecycle, isolated preview, shared visible mouse/computer pressed state,
   and UI-only octave range navigation across the read-only 96-note map. Follow it with a separately designed compatibility slice for audible sample-header
   panning, then continue explicit loaded-module copy/import flows before broader
   loaded-module editing or Save/Save As work.
   Continuous PAN, VOLUME, and FINETUNE controls now update their numeric and
   accessibility values transiently during drag while preserving one `applyEdit`
   mutation at mouse-up; held previews and the persistent stream are unchanged. See
   `docs/design/instrument-editor-window.md`.
5. Design a weekly codebase review harness as a docs/tooling plan before
   adding automation.
6. Use `docs/design/module-analysis-lifecycle.md` to sequence module-analysis
   work: async adapter-plan prewarm now keeps the cached runtime plan off the
   synchronous load path while improving first-Play readiness, and loaded-module
   TIME is derived only from the installed adapter-plan duration.
7. Consider README badges later only if they point at stable, useful CI or
   release signals.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement for multi-retrigger as a later parity-watch cleanup
  unless new linear-corpus evidence promotes it.

Recently completed:

- XM sample-header relative note and finetune are editable across the full
  signed-byte range only for a stopped editable document/copy. Labeled applyEdit
  snapshots support undo/redo and refresh signed readouts; Export XM/reopen
  preserves exact values. Later playback uses the existing pitch/sample-step
  behavior with no formula, scheduling, runtime engine, or C mixer DSP change.
- XM sample-header panning is the first editable sample metadata field. The
  selected represented sample's exact `UInt8` value can change only in stopped
  editable documents/copies, through one labeled `applyEdit` undo action; the
  PAN control stays disabled for loaded modules, playback, and empty slots.
  Export XM/reopen preserves edits. Focused audition, normal playback, and
  product audio export initialize each new voice from the resolved sample's
  byte (`0` left, `128` exact center, `255` right); loaded sources remain read-only.
- XM instrument panning envelopes now preserve up to 12 points, point ticks/
  values, counts, sustain/loop indices, and supported flags through loading,
  editable copy, snapshots, undo/redo, and Export XM. The Instrument Editor's
  local VOL/PAN selector shows either envelope read-only; adapter plans, voice
  pan, rendered PCM, C mixer DSP, and loaded-module rules are unchanged.
- The Instrument Editor opens from the Window menu as one
  reusable fixed 920 × 638 utility window following the v1 mockup
  hierarchy: instrument/name/XI/audition header, instrument/sample lists,
  envelope preview, vibrato/defaults clusters, and note-keymap placeholder with
  represented sample ranges. It follows the active loaded module, editable
  document, or editable copy and current instrument/sample selection. Only
  represented instrument NAME is editable in stopped editable documents;
  it uses XM name constraints and labeled applyEdit undo/redo, refreshing the
  editor/control panel and preserving existing Export XM support. Loaded
  modules and all sample/envelope/keymap/vibrato/waveform controls stay
  read-only.
- `File > Export Audio > M4A...` now exposes fixed 192 kbps AAC-in-M4A sharing
  export for the same stopped loaded modules and editable documents as WAV.
  It reuses the immutable product WAV plan and completed auto-headroom-scaled
  Float32 temp output, adds encoding progress/cancellation and cleanup, writes
  only to the selected destination, and leaves WAV output, render PCM, runtime
  playback/scheduling, C mixer DSP, parser architecture, tracker viewport, XM
  writer behavior, Save/Save As, and loaded-module read-only state unchanged.
- App WAV export now has a Cancel button backed by a thread-safe cooperative
  token and a dedicated non-error cancellation result. Safe checks surround
  preparation/indexing, each render window, each headroom chunk, and the final
  replace commit; cancellation removes temporary output and leaves an existing
  destination and the source document untouched. Preparation remains
  indeterminate, followed by monotonic whole-export weighting of 5% prepared,
  80% rendering, 10% headroom, and 5% final writing. Completed WAV bytes and
  product export defaults are unchanged.
- Successful app WAV exports now expose a concise structured performance
  summary built from existing instrumentation. It compares plan/adapt,
  preparation/index, render, headroom, write/replace, window/frame/event/
  boundary, and shared/fallback sample-payload costs, plus auto-headroom gain
  and unity-fast-path use. The optional
  `VTX_WAV_EXPORT_PERFORMANCE_SUMMARY=1` stderr route is off by default and
  public-safe: no paths, filenames, titles, corpus labels, or pointer addresses
  are included. PCM output, normal completion UI, runtime playback/scheduling,
  C mixer DSP, parser architecture, tracker viewport behavior, and XM writer
  behavior are unchanged.
- `File > Export Audio > WAV...` now exposes product whole-song 32-bit Float
  WAV export for stopped loaded read-only modules, editable documents, and
  editable copies. Export uses the existing bounded offline C mixer path with
  VTX mix profile, an explicit user-initiated long-render whole-song policy,
  48 kHz output, default song-end tail, 64-row windowed scheduling, and
  export-boundary auto-headroom. It performs one expensive mixer render, writes
  an unscaled Float32 temp WAV while computing peak diagnostics, applies shared
  auto-headroom gain through a streamed Float32 WAV post-process, runs off the
  main thread with continuous weighted progress after indeterminate
  preparation, writes through temporary files to the selected destination, and
  does not mutate documents, claim source paths, enable Save/Save As, alter
  loaded-module read-only defaults, change runtime playback/scheduling, change
  C mixer DSP, change parser architecture, or touch tracker viewport/static
  highlight behavior. The C mixer wrapper owns its large
  fixed-size C state on the heap so background workers do not initialize that
  state on a small GCD stack. Advanced options remain deferred: PCM16,
  pattern/order ranges, channel/stem export,
  normalization, and diagnostic comparison profiles.
- `File > Make Editable Copy` now establishes the explicit loaded-module
  editable-copy boundary for supported stopped loaded read-only XM modules. It
  creates an untitled in-memory editable copy of represented
  song/order/pattern/note data plus supported palette/sample payloads, leaves
  the opened source module read-only and untouched, does not claim source-path
  ownership, keeps Save/Save As disabled, and leaves Export XM as a
  user-selected output path. Runtime playback/scheduling,
  `RuntimeCMixerAdapterEventPlan`, C mixer DSP, parser architecture, tracker
  viewport/static-highlight behavior, Instrument Editor, and Sample Editor
  behavior did not change.
- Export XM v1 is ready for release documentation as `v0.2.0-alpha.4`: stopped
  editable documents can export the current VTX editable subset to XM,
  including supported existing instrument/sample payloads, and exported XM
  files reopen as loaded/read-only modules. Save/Save As, loaded-module direct
  editing, Instrument Editor, Sample Editor, full arbitrary-XM round-trip
  parity, and full FT2/OpenMPT/MilkyTracker parity remain future work.
- Editable blank documents and loaded-module-derived editable copies now build
  a stopped-Play `PlaybackSong` snapshot from the editable document model and
  send it through the existing `RuntimeCMixerAdapterEventPlan` /
  `PlaybackEngine` / CoreAudio C mixer runtime path. Copied instrument/sample
  palettes remain value-owned by the editable document, stopped edits are
  reflected on the next Play, active editable current-pattern loop edits
  refresh through a fresh adapter plan at a safe loop boundary, and empty
  editable documents are silent/safe.
- Clear Song Data is now available from the Edit menu for blank/editable
  documents and as a loaded-module editable-copy bridge. Blank documents clear
  song/order/pattern data in place while preserving editor state. Loaded
  modules stay read-only; invoking Clear Song Data creates a new editable
  blank song that copies the available instrument/sample palette and playable
  sample payloads, clears song/order/pattern note data, resets to order 0 and
  pattern 0, and preserves safe timing and dimensions. Broader arrangement
  editing and undo/redo migration beyond Clear Current Pattern, WAV/AIFF
  import, XI import, sample/instrument editors,
  Save XM, and advanced audio export options remain deferred.
- Adapter-safe pattern-loop playback now wires the existing Loop control into
  Play start for the selected/current order/pattern, using a bounded range over
  the cached `RuntimeCMixerAdapterEventPlan`. The runtime C mixer render core
  repeats that adapter-plan range without timer-driven note triggers, without
  clearing active voices at loop wraps, and without changing C mixer DSP,
  parser architecture, runtime gain/headroom, tracker viewport, editor, note
  audition, save/export, or release behavior. Loop changes while already
  playing, loop-length TIME display, loop-range editing, clear-pattern/clear-
  song utilities, arbitrary ranges, and broader local corpus listening remain
  deferred.
- Runtime gain/headroom policy is now documented as a design boundary:
  runtime playback keeps fixed default headroom with developer diagnostic
  overrides, offline export keeps explicit gain/headroom and `--auto-headroom`,
  future runtime auto-headroom requires cache/edit/UI design, and playback
  merge gates should treat clipping/overrange, discontinuities, and adjacent
  jumps as separate diagnostic families. No playback behavior, C mixer DSP,
  parser, tracker viewport, editor, note audition, control panel, or release
  workflow changed.
- Runtime mixer adjacent-jump diagnostics now have explicit documented
  semantics and derived stop-summary status fields. Raw adjacent-jump counts
  remain unchanged and are watch telemetry for normal transients unless paired
  with listening/comparison evidence; nonzero stricter discontinuity counts
  indicate possible continuity concern, while clipping/overrange remains a
  separate output-level concern. No playback behavior, C mixer DSP, parser,
  tracker viewport, editor, note audition, control panel, or release workflow
  changed.
- Loaded-module TIME now derives from the existing cached/prewarmed
  `RuntimeCMixerAdapterEventPlan` planned song-end frame and plan sample rate.
  Load and File New clear stale TIME to `--:--`; async prewarm or first Play
  can update TIME after the current generation installs a valid plan; Stop and
  Play after Stop keep the cached duration. No title parsing, synchronous
  load-time duration scan, offline render, playback behavior, C mixer DSP,
  parser, tracker viewport, editor, control-panel layout, or release behavior
  changed. Future editing invalidation should use the same adapter-plan/edit-
  generation lifecycle.
- Disabled-by-default adapter-plan construction profiling now reports sanitized
  `RuntimeCMixerAdapterEventPlan.make` and `PlaybackSongSyntheticAdapter`
  phase timings for local diagnostics. It measures existing prewarm/Play plan
  construction internals only and does not optimize or change playback,
  generated adapter events, C mixer DSP, parser architecture, tracker viewport,
  editor, note audition, control panel, runtime gain/headroom, TIME display, or
  release behavior.
- Runtime C mixer adapter-plan construction now prewarms asynchronously after
  module load. `PlaybackEngine.load(song:)` still invalidates stale plans
  without blocking file open, then schedules background
  `RuntimeCMixerAdapterEventPlan` preparation for the current song generation.
  First Play uses a completed prewarm, waits for the in-flight prewarm, or falls
  back to the same synchronous make/configure path if prewarm is canceled or
  unavailable. Loading another module or File New cancels/invalidates stale
  work; Stop/Play reuses the cached plan. Playback, C mixer DSP, parser
  architecture, tracker viewport, editor, note audition, control panel, and
  runtime gain/headroom behavior remain unchanged.
- Runtime C mixer adapter-plan construction now stays out of synchronous file
  open to improve file-open responsiveness. `PlaybackEngine.load(song:)`
  invalidates stale plans, first Play prepares and configures the existing
  `RuntimeCMixerAdapterEventPlan` path synchronously when needed and can carry
  the deferred planning cost when async prewarm has not completed, and
  Stop/Play reuses the cached plan without changing playback, C mixer DSP,
  parser architecture, tracker viewport, editor, note audition, control panel,
  or runtime gain/headroom behavior.
- Disabled-by-default playback load/play timing diagnostics now report
  lifecycle phase durations and public-safe counts without moving load work,
  changing Play behavior, computing TIME, or changing runtime headroom.
- XM diagnostic and residual-scan recommendation wording alignment with the
  current support table and backend-freeze posture; no playback behavior
  changed.
- XM backend freeze / hardening audit for the temporary backend foundation
  freeze recommendation; no playback behavior changed.
- Amiga reference stem/per-voice isolation diagnostics for the anonymized Amiga
  target kept playback unchanged. ft2-clone individual-track exports did not
  reconstruct the full render, and VTX isolated-channel sums were close but not
  exact, so stem evidence is diagnostic rather than an amplitude proof. The
  203.9-204.7s residual still improves with +256...+309 frame shifts; channels
  1 and 14 are the strongest post-204s contributors. Focused VTX diagnostics
  show sustained row-32 looped voices through row-33 `3xx`, no sample offsets,
  no post-204.0 replacements/ramps, no sample-position reset, and many loops.
- Amiga looped-sample phase/ramp diagnostics for the anonymized Amiga target
  kept playback unchanged. The remaining late-window residual is concentrated
  around order 26 / pattern 32 / rows 32-39 with no sample offsets or note
  replacements in the worst 204s windows. Local evidence correlates the cluster
  with sustained looped voices and a stable local alignment shift, while an
  experimental tick-length gain-ramp check did not improve full-song metrics.
- Amiga 3xx period/phase follow-up corrected Amiga note/target period
  calculation to use the FT2-compatible quantized period lookup while
  preserving VTX's existing 4x period scale and tick-level slide units. Local
  reference comparison for the anonymized Amiga target improved full-song
  correlation and RMS substantially; the remaining late-window mismatch still
  presents as looped-sample phase/timing rather than a broad period-table issue.
- Amiga reference/parity diagnostics for the narrow Amiga-table note/`2xx`/`3xx`
  foundation. Local ft2-clone comparison confirmed Amiga note, `2xx`, and
  effect-column `3xx` paths now apply without neutral-step fallback, while the
  largest remaining mismatch clusters point at Amiga pitch/phase behavior under
  looped sample playback rather than a broad level, stereo, or traversal issue.
- Amiga frequency-table foundation for note period/frequency/sample-step
  calculation, sample finetune metadata, Amiga-table `2xx` portamento down,
  and effect-column `3xx` tone portamento in the shared runtime/offline C
  mixer adapter path.
- `Lxx` set envelope position foundation for active volume envelopes in the
  shared runtime/offline C mixer path.
- Volume-column `F0...FF` tone portamento foundation reusing the existing
  `3xx` tone target/sample-step path.
- Final expanded-corpus linear-XM effect coverage before the Amiga foundation:
  no deferred linear command was promoted ahead of Amiga frequency-table work.

Each behavior-changing PR should include focused tests and update
`docs/xm-effect-support.md` when support changes.

## Backend Cleanup / Hardening

Allowed during the temporary backend foundation freeze:

- remove or simplify obsolete diagnostics that no longer support active work
- inventory scripts before consolidation
- document which tools are current, historical, or local-only
- keep runtime, parser, tracker viewport, and offline render responsibilities
  separate
- align diagnostic recommendation wording with current support status

Not allowed during the freeze unless a narrow blocker is promoted:

- playback behavior changes
- script behavior changes
- parser architecture changes
- tracker viewport changes
- retired AVAudio backend reintroduction

Recommended next product PR:

- The File New-to-export workflow/design pass is complete in
  [ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md).
  Empty instrument/S01 creation through `applyEdit` is complete; the current
  dense model appends after the highest represented slot rather than filling
  sparse holes. Deterministic SINE with all-note mapping is complete. Next, add
  WAV import decode and canonical normalization. Keep each importer, lifecycle,
  keymap editing, and reference-preserving reorder work in later focused PRs;
  do not change the runtime backend or C mixer DSP.
- Module TIME/headroom work should follow
  `docs/design/module-analysis-lifecycle.md`: loaded-module TIME now comes
  from the cached/prewarmed adapter plan; do not add synchronous full-song
  analysis to file load, do not infer duration from title strings, and do not
  move runtime gain/headroom policy without a cache/invalidation plan.
- Future Song / Order follow-up work should be scoped separately from playback:
  confirmation/undo/redo, drag or keyboard polish, pattern length utilities, and
  editable-copy/save/export flow before persistence work.

Recently completed product foundation:

- Editable XM export now writes existing palette/sample payloads for stopped
  editable documents when the editable copy safely represents XM-derived signed
  8-bit or 16-bit PCM. The supported subset includes instrument names,
  keymaps, represented volume-envelope fields, sample headers, forward and
  ping-pong loop metadata, and XM delta-encoded sample payloads. Unsupported
  sample metadata fails with focused writer errors, while Save/Save As, loaded
  read-only module export/editing, full arbitrary XM writer parity, runtime
  playback, parser architecture, C mixer DSP, tracker viewport, Song / Order
  behavior, Instrument Editor, Sample Editor, sample import, WAV export, and
  offline render behavior remain unchanged/deferred.
- Public-safe XM writer reload smoke tests now persist generated
  editable-document XM data only under test temporary directories and reload it
  through the existing parser path. Coverage includes blank documents, simple
  note/instrument cells, key-off cells, multiple pattern/order references, and
  volume/effect fields for the current VTX editable subset.
- File > Export XM... now wires the current editable XM writer to the app's
  final file-output boundary: stopped editable documents can choose an `.xm`
  destination, VTX writes atomically where possible, reload smoke covers the
  generated file through the existing parser path, cancel writes nothing, and
  writer/file errors return explicit failure results. Save, Save As,
  loaded-module editing, and full arbitrary XM export parity remain deferred.
- Minimal public-safe XM writer model tests now cover an in-memory editable
  `BlankTrackerDocument` writer foundation: XM header basics, sanitized module
  and tracker names, order/channel/timing fields, blank pattern headers,
  packed note/instrument/key-off/volume/effect cells, multiple pattern/order
  references, no-sample instrument headers, non-mutation, and the type-level
  editable-document input boundary. This foundation now backs `File > Export
  XM...`; Save/Save As remain disabled/deferred.
- File > Export XM... first established the safe app-shell boundary for XM
  export: stopped editable documents could choose an `.xm` destination, while
  loaded read-only modules and active playback were disabled/no-op. The shell
  did not enable Save or Save As and did not change parser, runtime audio, C
  mixer DSP, tracker viewport, Song / Order editor, note entry, note audition,
  Instrument Editor, or Sample Editor behavior.
- The tagged `v0.2.0-alpha.3` release marks the first-pass Song / Order editor
  composition workflow complete: editable blank documents can use note entry,
  Pattern Bank viewing/assignment, Pattern Ops NEW/DUP/CLEAR, Order Ops
  INSERT/DELETE/DUP/MOVE UP/MOVE DOWN/PTN -/+, Clear Song, normal Play/Stop,
  Loop-at-Play-start, and Play Current Pattern through the existing runtime
  path. Loaded modules remain read-only, and save/export plus Instrument/Sample
  editors remain future work.
- Song / Order editor DANGER / CLEAR SONG now mutates only stopped editable
  documents, resetting song/order and pattern cell data to one blank order and
  pattern while preserving instruments, samples, palette selection, timing, row
  count, and channel count. Loaded modules and active playback remain
  read-only/no-op; modal confirmation remains deferred.
- Song / Order editor ORDER OPS PTN -/+ now mutate only the selected stopped
  editable document order slot's pattern reference. The controls step to the
  next lower/higher allocated pattern, skip sparse gaps without allocation,
  preserve selected POS, and update the displayed pattern plus Pattern Bank
  highlight/page. Loaded modules and active playback remain read-only/no-op.
- Song / Order editor Pattern Ops DUP and CLEAR now mutate only stopped
  editable document patterns. DUP creates/views a copied unassigned pattern
  without assigning it to the selected order slot, and CLEAR empties the
  displayed pattern while preserving order references. Loaded modules and
  active playback remain read-only/no-op.
- Song / Order editor ORDER OPS DUP, MOVE UP, and MOVE DOWN now mutate only
  stopped editable document order slots. Duplicate inserts a new slot after the
  selection with the same pattern reference, move up/down reorder one slot at a
  time, moved/duplicated slots remain selected, and pattern, instrument, and
  sample data are preserved. Loaded modules and active playback remain
  read-only/no-op, with no transport, runtime audio, parser, save/export,
  sample editor, or instrument editor changes.
- Song / Order editor ORDER OPS INSERT and DELETE now update stopped editable
  document order slots only. Insert adds a slot after the selected order using
  the selected slot's existing pattern reference; Delete removes only the order
  slot, preserves pattern/instrument/sample data, and keeps at least one valid
  order. Loaded modules and active playback remain read-only/no-op, and no
  transport, playback scheduling, runtime audio, parser, save/export, sample
  editor, or instrument editor behavior changed.
- Adapter-safe pattern-loop transport now has a design note and pure model
  tests for current-order ranges over the public multi-pattern fixture. It is
  scaffolding only: no Loop button runtime behavior, pattern-loop playback,
  C mixer scheduler, parser, editor, viewport, control-panel visual,
  gain/headroom, note audition, save/export, or release behavior changed.
- Generated `tests/reference-xm/generated/multi-pattern-loop-boundary.xm` now
  provides a public-safe three-pattern, three-order traversal fixture for
  loader, `PlaybackSongBuilder`, and `RuntimeCMixerAdapterEventPlan` tests.
  This supports future adapter-safe pattern-loop design without implementing
  pattern-loop playback or changing runtime audio, parser architecture,
  tracker viewport, editor, note audition, control panel, or release behavior.
- Main-window control panel presentation now has the first Build Beyond demo
  polish pass: dark hardware-panel grouping, top gold accent, separated
  TITLE/TIME readouts, PTN decimal display, loaded-module instrument/sample
  names where available, and transport/toggle active-state styling without
  changing playback, backend, parser, tracker viewport, editor, save/export, or
  loaded-module read-only behavior. Loaded-module TIME now follows the adapter
  plan lifecycle above; no duration is inferred from module title text.
- Loaded-module audition now has explicit selected-sample slot controls in the
  existing control panel. Preview resolves the selected 1-based `Sxx` slot on
  the selected instrument, routes non-first sample slots into the preview
  descriptor when payload exists, and returns preview-unavailable for missing
  or empty selected slots instead of falling back to `S01`. Instrument changes
  preserve the selected sample slot when possible and otherwise reset to the
  first available sample slot, or `S01` when no sample slots are exposed.
  Loaded modules remain read-only, blank documents remain preview-unavailable,
  and runtime song playback, Play/Stop transport, backend selection, C mixer
  DSP, parser architecture, tracker viewport behavior, save/export behavior,
  and AVAudio runtime backend policy remain unchanged.
- Non-Edit-mode tracker note keys now use an explicit editor input policy:
  loaded-module note keys may audition selected previewable instrument/sample
  payload without mutating pattern data, blank documents remain preview
  unavailable without real sample payload, keyUp cancels only the matching
  preview and never writes `===`, backtick/Delete/Backspace mutate only where
  editing is allowed, and Play/Stop transport, runtime song playback, backend
  selection, C mixer DSP, parser architecture, tracker viewport behavior,
  save/export behavior, and loaded-module read-only mutation policy remain
  unchanged. Full FT2/XM envelope/key-off/fadeout parity, sample editing,
  sample loading, and XI import remain deferred.
- Edit-mode loaded-module note preview now carries sanitized sample-loop
  metadata through the preview descriptor/render plan and lets held preview
  notes sustain through existing forward or ping-pong C mixer loop support
  until matching keyUp cancels the preview. Non-looping samples remain
  one-shots. Runtime song playback, Play/Stop transport, backend selection, C
  mixer DSP, parser architecture, tracker viewport behavior, save/export
  behavior, and loaded-module read-only mutation policy remain unchanged. Full
  FT2/XM envelope/key-off/fadeout parity and non-Edit-mode audition remain
  deferred.
- Edit-mode loaded-module note preview now tracks the active preview key and
  stops only the editor preview voice on the matching keyUp. KeyUp does not
  write pattern `===`, backtick remains the explicit pattern key-off binding,
  repeated keyDown events still do not retrigger preview, stale keyUp events do
  not cancel newer previews, and runtime song playback, Play/Stop transport,
  backend selection, C mixer DSP, parser architecture, tracker viewport
  behavior, save/export behavior, and loaded-module read-only mutation policy
  remain unchanged. Full FT2/XM release/envelope parity and non-Edit-mode
  audition remain deferred.
- Editor note preview now maps typed note/octave to preview pitch in the same
  preview-only mixer path used by the audible sink, resolves loaded-module
  instruments through the selected instrument and the then-current sample-map
  policy,
  clears prior preview voices before scheduling replacements, and applies
  loaded-module adapter sample gain at neutral channel/global volume plus the
  default runtime C mixer output headroom, with a final preview-only safety cap.
  This keeps preview isolated from runtime song playback, Play/Stop transport,
  backend selection, C mixer DSP, parser architecture, tracker viewport
  behavior, save/export behavior, and loaded-module read-only mutation policy.
  Full gain parity, preview key-release/key-off behavior, and non-Edit-mode
  keyboard audition remain deferred.
- Audible editor note preview now has a narrow preview-only audio sink behind
  the existing note-audition preview boundary. Loaded-module note-on requests
  with positive sample payload from the generated public fixture can route to a
  short one-shot C mixer/CoreAudio preview, while runtime song playback,
  transport state, backend selection, parser architecture, tracker viewport
  behavior, save/export behavior, and loaded-module read-only mutation policy
  remain unchanged. The first spike proves the isolated editor preview path
  only: full preview gain parity against normal Play/song playback,
  non-Edit-mode keyboard audition, and preview key-release/key-off behavior
  remain deferred.
- The generated public XM fixture
  `tests/reference-xm/generated/basic-instrument-sample.xm` now proves positive
  loaded-module note-audition availability through the public fixture loading
  path and `PlaybackSongBuilder`, while keeping backend behavior, parser
  architecture, tracker viewport behavior, and loaded-module editing
  unchanged.
- Generated `tests/reference-xm/generated/basic-instrument-sample.xm` from the
  synthetic fixture generator, added deterministic generator tests, and added
  parser/editor positive-path coverage for loading real public sample payload
  without adding WAV renders, backend behavior, parser architecture changes,
  tracker viewport changes, editor behavior, or note audition audio.
- Synthetic XM fixture generator skeleton now adds the public
  `tests/reference-xm/` fixture-pack README, deterministic source manifest,
  generator script contract, and focused script tests without adding binary XM
  files, WAV reference renders, backend behavior, parser architecture changes,
  tracker viewport changes, editor behavior, or note audition audio.
- Synthetic redistributable XM fixture pack planning now defines public-safe
  fixture structure, licensing rules, focused fixture families, and local
  reference-render policy without adding fixture assets or changing backend,
  parser, tracker viewport, or editor behavior.
- Editor note audition preview routing now has a small no-audio coordinator and
  injected test sink seam behind the inert request and loaded-module
  availability model. It attempts only note-on requests with loaded-module
  previewable descriptors, keeps blank documents unavailable without real
  sample payload, keeps opened modules read-only, and leaves runtime playback,
  C mixer DSP, backend selection, parser architecture, and tracker viewport
  behavior unchanged.
- Editor note audition preview availability now resolves loaded-module
  instrument/sample requests against safe `PlaybackSong` sample data and reports
  inert descriptors for previewable payloads without adding audio playback,
  backend calls, parser changes, or loaded-module editing.
- Editor note audition preview planning now defines an inert request and
  availability model at the editor/audio boundary without adding audio preview,
  backend calls, parser changes, or loaded-module mutation.
- Blank-document note entry now includes the two-row tracker keyboard map:
  the lower row enters the selected octave, the upper row enters selected
  octave + 1, and high-C keys remain deferred.
- Blank-document editor state now tracks selected 1-based instrument/sample
  slots and displays them in the control panel as selected slots, while keeping
  blank documents in memory and opened modules read-only.
- Blank-document note entry now covers the lower-row natural/sharp keymap,
  explicit backtick key-off entry displayed as `===`, note-cell clear back to
  `...`, and centralized one-row edit-step advance while opened modules remain
  read-only.
- First in-memory note entry for blank tracker documents lets edit mode write
  natural notes into the selected note cell and advance by a clamped one-row
  edit step, while opened modules remain read-only.
- macOS menu foundation now provides a normal AppKit menu structure with
  standard app/file/edit/view/transport/window/help menus, preserving blank
  startup, File New, module open, transport, parser, backend, and tracker
  viewport behavior.
- Main window control-panel wiring and tooltip audit now keeps blank-document
  and loaded-module readouts synchronized with current UI metadata, including
  tempo/speed and restart-position display where metadata is available.
- Blank tracker startup and File New foundation now initialize an in-memory
  untitled tracker document so startup opens on an editable-grid foundation
  instead of the old no-module placeholder.

## Milestone 3: Composition Editor Foundation

Status: released as `v0.2.0-alpha.3`. The Song / Order editor composition
alpha completed the first-pass workflow for small editable blank songs. Tracker
display, blank startup, note-entry foundations, loaded-module audition,
clear-current-pattern, stable viewport behavior, adapter-safe pattern-loop
playback, and stopped editable song/order arrangement controls are implemented.
Export XM v1 for stopped editable documents was released as
`v0.2.0-alpha.4`.
Rendered audio export was released as `v0.2.0-alpha.5`. VTX 1.0 still needs the
broader composition surface below.

Current implemented foundation:

- AppKit tracker shell
- blank tracker startup and File New foundation
- module open/load flow
- metadata display
- tracker-style pattern grid display
- static highlight row behavior
- stable viewport navigation
- pattern selection
- blank-document note entry
- selected instrument/sample slot state
- loaded-module note audition and sample-slot preview
- clear current pattern for blank/editable documents, with labeled
  whole-document undo/redo
- clear song data for blank/editable documents
- pattern-loop playback at Play start
- Transport > Play Current Pattern
- Song / Order editor order-list / paginated pattern-bank binding with stopped
  selected-order navigation, Pattern Bank single-click viewing/navigation, and
  editable Pattern Bank double-click assignment
- stopped editable Pattern Ops NEW/DUP/CLEAR
- stopped editable Order Ops INSERT/DELETE/DUP/MOVE UP/MOVE DOWN/PTN -/+
- stopped editable Song / Order Clear Song reset
- Export XM v1 for stopped editable documents, scoped to the current editable
  subset and supported existing palette/sample payloads
- v1-mockup-aligned Instrument Editor utility-window shell bound to the current
  document palette and selected instrument/sample; represented rows share canonical
  selection with the control panel, stay selectable while loaded or playing, create
  no undo, and drive metadata/audition context; represented instrument NAME
  editing is enabled only for stopped editable documents and editable copies
- fixed Sample Editor utility-window shell aligned to
  `assets/mockups/sample-editor-v1.html`, the visual source of truth over prose;
  its compact instrument popup updates canonical selection without mutation or
  undo and reuses canonical sample normalization across the main window and
  Instrument Editor. One selected-sample state drives the highlighted row,
  identity, exact metadata, bounded read-only waveform, and display-only loop
  region; unnamed represented samples remain distinct from honest absence and
  no source rate is claimed
- File New owns unnamed zero-sample I01/S01; Edit > New Instrument appends and
  selects another empty S01 through one applyEdit action, and Export XM/reopen
  preserves zero-sample instrument count, order, and names without sample data
- capped whole-document applyEdit/undo foundation for stopped editable
  documents, including Edit > Undo/Redo, instrument rename, and existing
  editor/control-panel refresh paths
- exact XM sample panning preservation plus stopped editable-document mutation
  through applyEdit/undo/redo, plus resolved-sample panning in focused audition,
  runtime playback, and product audio export; loaded modules stay read-only
- exact XM signed-byte sample finetune preservation plus stopped editable-
  document mutation through applyEdit/undo/redo; subsequent playback uses the
  existing pitch path and loaded modules stay read-only
- exact XM signed-byte sample relative-note preservation through the same
  stopped-editable applyEdit/undo/redo and existing pitch path
- exact XM instrument autovibrato preservation through the same paths, with
  disabled VIBRATO display and no playback, audition, scheduling, or PCM change
- exact XM instrument panning-envelope preservation through the same paths,
  with read-only VOL/PAN display and no playback, voice-pan, scheduling, or PCM change
- deterministic public sustained, five-instrument metadata-matrix, and
  two-sample envelopes/keymap fixtures plus pinned manifest and committed-output
  verification for editor/audition/editable-copy/Export XM work; the pack adds
  no XI or reference audio
- basic transport smoke workflow

Next composition targets after backend foundation freeze:

- WAV import decode and canonical normalization foundation
- envelope playback/editing and broader instrument/sample metadata behind applyEdit
- editable Sample Editor loop mode/range behind applyEdit, followed by separate
  PCM/waveform mutation slices
- editable palette/sample workflow foundations
- instrument, volume-column, and effect-column entry
- WAV, AIFF/AIFC, and FLAC sample import plus the separate XI instrument import target
- copy/paste rows, selections, instruments, and samples
- copy/import instruments or samples from loaded modules into blank/editable
  songs through explicit editable-copy semantics
- Song / Order follow-ups such as confirmation, undo/redo, keyboard polish,
  pattern length utilities, and deeper arrangement editing
- broader loop-and-edit workflow for composing while hearing playback
- save XM and advanced audio export options
- keyboard workflow parity

Loaded modules remain read-only by default. Broader direct editing and Save/Save
As semantics remain deferred.

### Future Note Audition Path

The editor selection state should remain independent from parser internals and
audio backends. Planned sequencing is:

- keep selected 1-based instrument/sample slots as editor state first
- focused Instrument Editor computer-keyboard routing reuses the shared note
  map, current octave/selection, availability resolver, and preview sink
- the on-screen Instrument Editor keyboard now auditions exact clicked pitches,
  including release/press transitions while dragging, through the shared preview sink
- continue note audition using the selected instrument/sample source; the
  editor-side request and preview sink exist for loaded-module sample payloads
- treat key release as preview key-off only
- keep pattern key-off as explicit `===` entry through the tracker key binding
- allow loaded modules to become auditionable before they become editable
- include XI import, sample loading, instrument editor, and sample editor work
  in the 1.0 composition path

### Future Instrument Keymap Direction

The Instrument Editor piano is mapping-first and audition-second across the
full 96-note map. A full default Sample 1 assignment should stay neutral;
non-default assignments may use muted sample-number labels or colors, the
selected sample should receive stronger persistent emphasis, and transient
audition must remain a distinct pressed-key layer above the mapping. Read-only
polish may precede mutation. Keymap editing waits for stable sample-palette and
Sample Editor foundations and must use `applyEdit`/undo. Use
`instrument-envelopes-keymap.xm` as the public reference and keep this direction
linked to `docs/design/instrument-editor-window.md` and
[ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md).

Tracker viewport work must follow `docs/tracker-behavior-spec.md`,
`docs/ui-debugging.md`, and `docs/visual-verification.md`.

## Milestone 4: Nostalgia / Look And Feel

Wait until tracker behavior and backend foundations are stable.

Planned scope:

- visual theme baseline
- tracker typography and spacing polish
- keyboard workflow polish
- classic tracker behavior parity fixes

## Milestone 5: v1.x Workflow Enhancements

Wait until VTX 1.0 composition scope is stable.

Potential scope:

- quality-of-life workflow improvements
- export workflow polish
- preferences and module metadata panels
- waveform scopes and activity visualization
- MIDI keyboard or pad input
- recording and sample-capture improvements
- richer resampling tools
- plugin/audio-input to sample experiments

## Future Pro / Native-Format Concepts

Post-v1, prioritize a narrow macOS `VoodooTracker X Player AU` built with
native AUv3 APIs. A later iPadOS AUv3 phase follows only after the headless
engine and contained UI are proven; a `VoodooTracker X Tracker AU` may then add
deeper contained editing. General third-party Audio Unit hosting inside
standalone VTX remains possible but is lower priority and separately scoped.
The Performance Keyboard/Pad direction belongs to this post-v1/Pro family:
prefer a modeless macOS utility panel first, then consider a main-window drawer
or iPad touch surface backed by the same performance-state model. It does not
authorize a current tracker-main-window, logo, or viewport redesign.

AU preparation before that approval milestone means preserving reusable
document, playback-plan, state-ownership, audition/transport, and C mixer seams;
it does not mean adding AU targets or changing the current runtime. The
decision, phased outline, deferrals, and open questions are recorded in
`docs/decisions/011-post-v1-auv3-tracker-instrument-direction.md`.

AUv3 is the only approved format in this direction. VST3, AUv2, Windows,
JUCE, CMake, and cross-platform plug-in targets are not planned by this roadmap.

Other future Pro or native-format concepts may include plug-in-to-sample
rendering, automation, a native VTX project format or XM3-style extended
format, and AI-assisted instruments/samples/patterns. None are VTX 1.0
requirements or reasons to weaken classic XM compatibility.

## Ready To Expand Gate

Do not expand into broad feature work until:

- parser and tracker foundation are stable
- CoreAudio C mixer remains the only runtime backend path
- remaining linear-XM backend targets are closed or explicitly deferred
- Amiga frequency-table support has the narrow foundation landed and any
  reference/parity follow-up is scoped separately
- local comparison workflow is documented and generated artifacts stay out of
  git
- CI and `scripts/check-files.sh` remain green
