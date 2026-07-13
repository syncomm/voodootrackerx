# VoodooTracker X Development Roadmap

This is the short phase summary. Use `docs/roadmap.md` for current milestone
sequencing and `docs/agent-current-state.md` for the backend snapshot agents
should read first.

## Current State

VoodooTracker X currently has:

- an AppKit macOS shell
- module open/load flow
- read-only tracker pattern display
- static highlight row behavior and stable viewport navigation
- first-pass XM playback
- CoreAudio C mixer runtime playback by default
- bounded offline C mixer render/export for local comparison
- runtime trace/capture diagnostics
- current XM effect support tracked in `docs/xm-effect-support.md`
- blank tracker startup, note-entry foundations, selected instrument/sample
  slot state, loaded-module note audition, Clear Current Pattern for
  blank/editable documents, Clear Song Data for blank documents and loaded
  module editable-copy palette reuse, pattern-loop playback at Play start,
  Transport > Play Current Pattern for explicit current-pattern loop playback,
  and the Song / Order editor order-list / paginated pattern-bank binding with
  stopped selected-order navigation, editable Pattern Bank double-click
  assignment, stopped editable order-slot insert/delete controls, stopped
  editable ORDER OPS PTN -/+ pattern-reference stepping, and stopped editable
  Pattern Ops NEW/DUP/CLEAR pattern creation, duplication, and
  clear-current-pattern mutation, stopped editable DANGER / CLEAR SONG reset,
  and a stopped editable-document `File > Export XM...` path that writes the
  current editable subset to a user-chosen `.xm` file, including existing
  palette/sample payloads where the editable model safely represents signed
  8-bit or 16-bit XM-derived PCM, plus stopped `File > Export Audio > WAV...`
  whole-song 32-bit Float WAV export for loaded modules and editable documents,
  plus stopped `File > Export Audio > M4A...` sharing export that reuses the
  same product render plan and scaled Float32 PCM before fixed 192 kbps AAC
  encoding,
  plus explicit `File > Make Editable Copy` for stopped supported loaded
  read-only XM modules, with public-safe byte-level model tests and
  temporary-file reload/header smoke tests through existing parser/render
  paths, plus a reusable `Window > Instrument Editor` shell bound to the
  current palette and selected instrument/sample, with represented instrument
  NAME editing for stopped editable documents only and exact XM sample panning
  shown read-only, plus a capped
  whole-document applyEdit/undo funnel used by Clear Current Pattern and
  instrument rename

The app is still under active development and is not production-ready. VTX 1.0
is now scoped as a real XM-style composition-capable tracker: users should be
able to create complete sample-based songs from scratch, not only play modules
or type notes into a blank pattern.

The tagged `v0.2.0-alpha.3` release completed the first-pass Song / Order
editor composition workflow: a user can compose a small song from a blank
editable document using the main pattern grid, transport controls, Pattern
Bank, Pattern Ops, Order Ops, and Clear Song while loaded modules remain
read-only.

`v0.2.0-alpha.4` was the Export XM v1 release for the current editable subset.

The released `v0.2.0-alpha.5` centers on the Rendered Audio Export
Alpha. Stopped loaded modules and editable documents can export whole-song
48 kHz Float32 WAV using the VTX render profile, 3-second tail, auto-headroom,
weighted progress, cancellation, and performance diagnostics, or AAC-in-M4A
for convenient sharing. Export writes only to a user-selected destination and
does not mutate documents or claim source-path ownership. WAV remains the
preferred high-quality and export-diagnostic format. Loaded modules remain
read-only, Save and Save As remain disabled, Export XM remains scoped to the
current editable subset, and advanced options such as PCM16, pattern/order
ranges, channel/stem export, bitrate/quality controls, and diagnostic profile
selection remain future work.

## Backend Snapshot

- Runtime default: CoreAudio DefaultOutput Audio Unit C mixer.
- Explicit aliases: `VTX_AUDIO_BACKEND=c_mixer` and
  `VTX_AUDIO_BACKEND=c_mixer_coreaudio`.
- Retired value: `VTX_AUDIO_BACKEND=av_audio`, which falls back to the
  CoreAudio C mixer with a diagnostic fallback reason.
- Retired AVAudio playback paths must not return.
- Offline C mixer render/export is the deterministic reference comparison path.

For backend history, comparison policy, and command groups, read
`docs/agent-current-state.md` and `docs/roadmap.md`.

## Backend Freeze And Next Targets

The XM backend is in a temporary backend foundation freeze. During the freeze,
avoid behavior-changing effect, C mixer DSP, parser architecture, runtime
backend, and tracker viewport work unless a freeze-exit blocker is promoted.

Recommended next work should return to GUI/editor and product milestones while
preserving the backend freeze:

Recommended next PR:
`instrument: add panning envelope model round-trip foundation`.

1. Define editable-document ownership and save/export semantics before any
   file-writing implementation. Done; see
   `docs/design/editable-document-save-export-model.md`.
2. Minimal public-safe XM writer model, app export wiring, reload smoke tests,
   and existing palette/sample payload export are in place for the current
   editable-document writer subset.
3. Export XM v1 release preparation for `v0.2.0-alpha.4` is complete.
4. Define an explicit loaded-module editable-copy command before direct
   loaded-module editing or Save/Save As work. Done.
5. Build an Instrument Editor shell/read-only binding. Done.
6. Add the document `applyEdit`/undo funnel for future instrument/sample edits.
   Done.
7. Instrument NAME editing and sample panning model round-trip support are done;
   next add the runtime-inert panning envelope model round-trip foundation.
8. Pattern editor completion for instrument, volume-column, and effect-column
   entry.
9. Sample/instrument editing foundations plus WAV/AIFF sample import and XI
   instrument import target.
10. Rendered audio export release preparation for `v0.2.0-alpha.5` is complete.
   Keep PCM16, ranges, stems, bitrate/quality controls, and diagnostic profiles
   as later slices.
11. Song / Order follow-ups such as confirmation, undo/redo, keyboard polish,
   pattern length utilities, and deeper arrangement editing.
12. Design a weekly codebase review harness as a docs/tooling plan before
   adding automation.
13. Module analysis follow-up should use
   `docs/design/module-analysis-lifecycle.md`: async adapter-plan prewarm now
   prepares the same cached runtime plan after load without blocking file open,
   while first-Play adapter-plan preparation remains the synchronous fallback.
   Loaded-module TIME now reads only from the installed cached/prewarmed
   adapter-plan duration with clear load/File New invalidation. A later
   optimization PR can profile and reduce adapter-plan construction cost
   itself.
14. README badges may be added later if they point at stable, useful CI or
   release signals.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless new
  linear-corpus evidence promotes it.

Recently completed narrow target:

- Labeled whole-editable-document snapshots now flow through
  `EditableDocumentEditCoordinator` and a capped `UndoManager`. Clear Current
  Pattern is the first routed operation; undo/redo refresh existing editor
  displays and remain unavailable for loaded read-only or playing contexts.
- The first Instrument Editor foundation now provides one reusable fixed
  920 × 638 read-only utility window from the Window menu, aligned to the v1
  mockup's header, instrument/sample lists, envelope, vibrato/defaults, and
  note-keymap hierarchy. It follows File New, module load, Make Editable Copy,
  Clear Song transitions, and main control-panel instrument/sample selection;
  shows represented metadata, immutable volume-envelope and keymap-range data,
  and clean empty states. Future editing/XI/audition/keymap controls are
  disabled. It adds no mutation, envelope/keymap editing, or waveform display;
  playback, parser, writer, and export behavior remain unchanged.
- App M4A export now reuses the existing whole-song product WAV plan and
  completed scaled Float32 temp output, then encodes fixed 192 kbps AAC through
  AVFoundation. It has the same stopped-document gating, non-mutation and
  source-ownership safety, progress/cancellation behavior, and temporary-file
  cleanup expectations as WAV export without changing WAV bytes or render PCM.
- App WAV export now supports safe cooperative cancellation from its progress
  sheet with a dedicated cancelled result, temporary-file cleanup, and checks
  around preparation/indexing, render windows, headroom chunks, and final
  replacement. Preparation stays indeterminate; determinate progress is
  monotonic and weighted 5%/80%/10%/5% across prepared/render/headroom/write.
  Completed WAV output and product defaults are unchanged.
- Successful app WAV exports now provide a concise, typed
  `WAVExportPerformanceSummary` built from existing instrumentation. It covers
  plan/adapt, preparation/index, render, headroom, write/replace, window/frame/
  event/boundary, shared/fallback payload-copy, auto-headroom, and unity-fast-
  path metrics. `VTX_WAV_EXPORT_PERFORMANCE_SUMMARY=1` enables a single
  public-safe developer stderr line; logging is off by default, normal export
  alerts and PCM bytes are unchanged, and no render optimization was included.
- Production accumulated and streaming windowed offline rendering now caches
  finite sample PCM in render-session-scoped, C-owned shared payload objects for
  repeated notes and window carryovers. App WAV export and product-equivalent
  tool rendering inherit that path; defensive and pre-sanitized per-voice copy
  modes remain explicit fallbacks/references, while runtime and immediate
  rendering remain unchanged. Diagnostics report shared creates/bytes, voice
  and continuation references, avoided uploads, and fallback copies.
  Byte-identical shared-versus-copied, accumulated-versus-streaming,
  indexed-versus-scan, and app-versus-tool tests pin output.
- App WAV export now reports pre-index construction as an indexing-render-
  windows preparation phase instead of appearing stalled at rendering 0/N.
  Same-channel replacement-ramp continuation lookup is pre-indexed by old event
  identity and preserves the prior last-matching-ramp semantics. Existing
  index-build timing diagnostics include the preparation work; PCM output and
  runtime playback remain unchanged.
- Windowed offline rendering now bulk-copies already-sanitized Float32 sample
  payloads into the same C-owned per-voice storage while preserving the
  defensive sanitizing C APIs for runtime/untrusted callers. Diagnostics report
  accepted C voice adds, payload counts/bytes, continuation uploads, duplicate
  identities, and fast/slow copy counts; byte-parity tests pin output.
- Windowed offline rendering now consumes pre-indexed event, continuation, and
  update-candidate buckets to reduce repeated scheduling scans. Public-safe
  scan-reference, accumulated-vs-streaming, and app-vs-tool byte-parity tests
  pin output and diagnostics; runtime playback, C mixer DSP, parser, tracker
  viewport, and XM writer behavior remain unchanged.
- `File > Export Audio > WAV...` now renders stopped loaded modules, editable
  documents, and editable copies to whole-song 32-bit Float WAV through the
  existing bounded offline C mixer path. It uses the VTX mix profile, an
  explicit user-initiated long-render whole-song policy, 48 kHz output, default
  song-end tail, 64-row windowed scheduling, and export-boundary auto-headroom
  instead of the diagnostic bounded-render cap. It performs one expensive mixer
  render, writes an unscaled Float32 temp WAV while computing peak diagnostics,
  applies shared auto-headroom gain through a streamed Float32 WAV
  post-process, shows continuous weighted progress after indeterminate
  preparation while rendering off the main thread, writes only to the
  selected destination through temporary files, removes temporary output on
  failure, leaves source modules/documents untouched, does not claim source
  paths, keeps Save/Save As disabled, and leaves loaded modules read-only by
  default. The C mixer wrapper owns its
  large fixed-size C state on the heap so background workers do not initialize
  that state on a small GCD stack. Advanced audio export options remain
  deferred.
- `File > Make Editable Copy` now creates an explicit untitled in-memory
  editable copy from a stopped loaded read-only XM module when the current
  supported editable subset can represent its song/order/pattern/note data and
  represented instrument/sample palette payloads. Loaded modules remain
  read-only by default, the opened source path is untouched and not owned by
  the copy, Save and Save As remain disabled, and Export XM remains a
  user-selected output path. Runtime playback/scheduling, parser architecture,
  C mixer DSP, tracker viewport/static-highlight behavior, Instrument Editor,
  and Sample Editor behavior did not change.
- Editable XM export now writes existing instrument/sample palette data for
  stopped editable documents when the copied palette safely represents
  XM-derived signed 8-bit or 16-bit PCM payloads. The writer emits instrument
  names, keymaps, represented volume-envelope fields, sample headers, loop
  metadata for forward/ping-pong loops, and correctly delta-encoded sample
  payloads; unsupported sample metadata returns focused writer errors. Save,
  Save As, loaded-module direct export/editing, arbitrary XM writer parity,
  runtime playback, parser architecture, C mixer DSP, tracker viewport, Song /
  Order behavior, Instrument Editor, Sample Editor, sample import, WAV export,
  and offline render behavior remain unchanged/deferred.
- File > Export XM... now wires the current editable XM writer to the app's
  final file-output boundary: stopped editable documents can choose an `.xm`
  destination, VTX writes atomically where possible, reload smoke covers the
  generated file through the existing parser path, cancel writes nothing, and
  writer/file errors return explicit failure results. Save, Save As,
  loaded-module editing, full arbitrary XM export parity, runtime playback,
  parser architecture, C mixer DSP, tracker viewport behavior, Song / Order
  behavior, Instrument Editor, and Sample Editor remain unchanged/deferred.
- Public-safe XM writer reload smoke tests write generated editable-document
  XM data only under test temporary directories and reload it through the
  existing parser path. Coverage includes blank documents, simple
  note/instrument cells, key-off cells, multiple pattern/order references, and
  volume/effect fields for the current VTX editable subset.
- Minimal public-safe XM writer model tests now cover an in-memory editable
  `BlankTrackerDocument` writer foundation: XM header basics, sanitized module
  and tracker names, order/channel/timing fields, blank pattern headers,
  packed note/instrument/key-off/volume/effect cells, multiple pattern/order
  references, no-sample instrument headers, non-mutation, and the type-level
  editable-document input boundary. This foundation now backs `File > Export
  XM...`; Save/Save As remain disabled/deferred.
- File > Export XM... first established the editable-document-only
  menu/save-panel shell: it is enabled only for stopped editable documents and
  disabled/no-op for loaded read-only modules and active playback. Save and
  Save As remained disabled, and runtime playback, parser, C mixer DSP, tracker
  viewport, Song / Order editor behavior, note entry, note audition, and
  Instrument/Sample editor behavior did not change.
- The tagged `v0.2.0-alpha.3` release marks the first-pass Song / Order editor
  composition workflow complete for small editable blank songs: Pattern Bank
  viewing/assignment, Pattern Ops NEW/DUP/CLEAR, Order Ops
  INSERT/DELETE/DUP/MOVE UP/MOVE DOWN/PTN -/+, Clear Song, Play Current
  Pattern, normal Play/Stop, and Loop-at-Play-start all remain on the existing
  document/runtime paths. Loaded modules stay read-only; save/export and
  Instrument/Sample editors remain future work.
- The Song / Order editor DANGER / CLEAR SONG control now routes stopped
  editable documents through the existing safe clear-song semantics: song/order
  and pattern cell data reset to one blank pattern/order while preserving
  instruments, samples, palette selection, timing, row count, and channel count.
  Loaded modules and active playback remain read-only/no-op, and modal
  confirmation remains deferred.
- The Song / Order editor ORDER OPS PTN -/+ controls now mutate only the
  selected stopped editable document order slot's pattern reference. They step
  to the next lower/higher allocated pattern, skipping gaps without allocating
  missing pattern numbers, preserve selected POS, update the displayed pattern
  and Pattern Bank highlight/page, and keep loaded modules plus active playback
  read-only/no-op.
- The Song / Order editor Pattern Ops DUP and CLEAR controls now mutate only
  stopped editable document patterns. DUP creates/views a copied unassigned
  pattern without changing selected POS or order references, and CLEAR empties
  the displayed pattern while preserving order references. Loaded modules and
  active playback remain read-only/no-op.
- The Song / Order editor ORDER OPS DUP, MOVE UP, and MOVE DOWN controls now
  mutate only stopped editable document order slots. Duplicate inserts the same
  pattern reference after the selected slot, move up/down reorder one slot at a
  time, and loaded modules plus active playback remain read-only/no-op.
- The Song / Order editor Pattern Ops NEW control now creates and views a blank
  unassigned pattern for stopped editable documents, displays/highlights it
  through the existing pattern-bank and tracker refresh path, and leaves order
  slot assignment to explicit Pattern Bank double-click. Loaded modules and
  active playback remain read-only/no-op.
- The Song / Order editor ORDER OPS INSERT and DELETE controls now mutate only
  stopped editable document order slots. Insert adds a new slot after the
  selected order using the selected slot's existing pattern reference; Delete
  removes the selected slot without deleting pattern, instrument, or sample
  data and keeps at least one valid order slot. Loaded modules and active
  playback remain read-only/no-op, with no transport, runtime audio, parser,
  save/export, sample editor, or instrument editor changes.
- Transport > Play Current Pattern now starts the displayed/selected pattern
  from row 0 as an isolated loop through the existing
  `RuntimeCMixerAdapterEventPlan` runtime path. Normal Play still starts from
  the selected POS/order, hidden/unreferenced pattern viewing remains
  view-only, Stop ends the pattern loop, and no order/pattern mutation,
  second playback path, parser, C mixer DSP, viewport, save/export, sample
  editor, or instrument editor behavior changed.
- The Song / Order editor Pattern Bank now keeps single-click navigation as
  view-only and uses double-click to assign an existing pattern to the selected
  order slot in editable documents while stopped. Empty pattern cells and
  active-playback double-clicks are ignored, loaded modules remain read-only,
  and no pattern allocation, order insert/delete, transport, playback,
  runtime audio, parser, save/export, sample editor, or instrument editor
  behavior changed.
- The Song / Order editor Pattern Bank single-click path remains read-only
  stopped/idle navigation to existing loaded-module or editable-document
  patterns through the existing main-window state path. Hidden/unreferenced
  views preserve the selected POS/order used by normal Play.
- The Song / Order editor order list now supports stopped/idle selected-order
  navigation for loaded modules and editable documents that expose order rows.
  Row clicks update the current order/pattern through the existing main-window
  state path, highlight the selected order, and auto-page the read-only pattern
  bank to the referenced pattern. Active playback row clicks are ignored; order
  list mutation, pattern-bank assignment, transport controls, playback paths,
  runtime audio, parser behavior, save/export, sample editor, and instrument
  editor behavior remain deferred.
- The Song / Order editor shell now displays read-only order-list and paginated
  pattern-bank state from the current loaded module or editable document,
  refreshing after File New, module load, Clear Song Data, Clear Current
  Pattern, and existing main-window order/pattern selection changes. Editing,
  mutation commands, transport controls, playback paths, parser behavior,
  runtime audio, save/export, sample editor, and instrument editor behavior
  remain deferred.
- The Song / Order editor now has a fixed-size floating utility-window shell
  opened from the Window menu, with inert pattern-ops, order-ops, and danger
  panels. Real order/pattern editing remains deferred; no transport, playback,
  parser, save/export, tracker viewport, note entry, note audition, sample
  editor, or instrument editor behavior changed.
- Shared AppKit editor control primitives now provide reusable theme tokens,
  panel labels, segment readouts, indicator LEDs, tactile editor buttons,
  editor knobs, and center-detent pan sliders for future Song / Order,
  Instrument, and Sample windows,
  without wiring new windows or changing main-window, playback, parser, C
  mixer, save/export, tracker viewport, note entry, or note audition behavior.
- Editable blank documents and loaded-module-derived editable copies now build
  a stopped-Play `PlaybackSong` snapshot from the editable document model and
  send it through the existing `RuntimeCMixerAdapterEventPlan` /
  `PlaybackEngine` / CoreAudio C mixer runtime path. Copied instrument/sample
  palettes remain value-owned by the editable document, stopped edits are
  reflected on the next Play, active editable current-pattern loop edits
  refresh through a fresh adapter plan at a safe loop boundary, and empty
  editable documents are silent/safe.
- Clear Song Data is now available from the Edit menu for blank/editable
  documents and as a loaded-module editable-copy bridge. Blank documents still
  clear notes, key-offs, instruments, volume-column data, effect-column data,
  and editable cell fields in place. Loaded modules stay read-only; invoking
  Clear Song Data creates a new editable blank song with copied instrument and
  sample palette data, playable sample payloads where available, cleared
  song/order/pattern note data, order 0, pattern 0, and safe preserved timing
  and dimensions. Broader arrangement editing and undo/redo migration beyond
  Clear Current Pattern, WAV/AIFF import, XI import,
  sample/instrument editors, Save XM, and advanced audio export options remain
  deferred.
- Adapter-safe pattern-loop playback now uses the existing Loop control at Play
  start to repeat the selected/current order/pattern through a bounded range of
  the cached `RuntimeCMixerAdapterEventPlan`. The loop path keeps adapter-plan
  event consumption, avoids timer-driven note triggers, preserves active C
  mixer state across wraps, and leaves C mixer DSP, parser architecture,
  runtime gain/headroom, tracker viewport, editor behavior, note audition,
  save/export, and release workflow unchanged. Live Loop retargeting during
  active playback, loop-length TIME display, loop-range editing, duplicate/insert/
  delete pattern utilities, arbitrary ranges, and broader local corpus listening
  remain deferred.
- Generated `tests/reference-xm/generated/multi-pattern-loop-boundary.xm` adds
  a public-safe three-pattern, three-order traversal fixture with loader,
  `PlaybackSongBuilder`, and `RuntimeCMixerAdapterEventPlan` coverage for
  future adapter-safe pattern-loop design. It does not implement pattern-loop
  playback and does not change runtime audio, C mixer DSP, parser architecture,
  tracker viewport, editor, note audition, control panel, or release behavior.
- Runtime gain/headroom policy now has a focused design doc. Runtime playback
  stays on fixed default headroom with developer diagnostic overrides; offline
  export remains the place for explicit gain, explicit headroom, and
  `--auto-headroom`; future runtime auto-headroom needs cache, invalidation,
  and UI policy design before implementation. The doc also records local
  anonymized evidence, pattern-loop and visualizer implications, and merge-gate
  guidance without changing playback, C mixer DSP, parser, tracker viewport,
  editor, note audition, control panel, or release workflow.
- Runtime mixer adjacent-jump diagnostics now distinguish raw transient watch
  telemetry from stricter continuity concerns. Stop summaries keep the raw
  adjacent-jump/discontinuity/clipping/overrange fields and add derived
  continuity/output-level status labels for local diagnostics. Adjacent jumps
  alone are not merge-blocking without listening, comparison, or stricter
  discontinuity evidence. No playback behavior, C mixer DSP, parser, tracker
  viewport, editor, note audition, control panel, or release workflow changed.
- Loaded-module TIME now formats a valid planned song-end frame from the
  installed `RuntimeCMixerAdapterEventPlan` as `MM:SS`. The display remains
  `--:--` before prewarm/Play plan readiness and after load/File New
  invalidation, Stop does not clear it, and no title parsing, load-time duration
  scan, offline render, playback behavior, C mixer DSP, parser, tracker
  viewport, editor, note audition, control-panel layout, or release workflow
  changed. Future editing invalidation should follow the adapter-plan/edit-
  generation lifecycle.
- Disabled-by-default adapter-plan construction profiling now measures
  sanitized `RuntimeCMixerAdapterEventPlan.make` and
  `PlaybackSongSyntheticAdapter` phase timings for local diagnostics only. It
  identifies expensive plan-construction phases before a later optimization PR
  and does not change playback semantics, generated adapter events, C mixer
  DSP, parser architecture, tracker viewport, editor, note audition, control
  panel, runtime gain/headroom, TIME display, or release behavior.
- Runtime C mixer adapter-plan construction now prewarms asynchronously after
  module load. Loading a module invalidates stale plans, schedules background
  `RuntimeCMixerAdapterEventPlan` preparation for the current song generation,
  and keeps backend configuration on the main actor. First Play uses a completed
  prewarm, waits for an in-flight prewarm, or synchronously falls back to the
  existing make/configure path if prewarm is canceled or unavailable. File New
  and loading another song invalidate stale work; Stop/Play reuses the cached
  plan. Playback semantics, C mixer DSP, parser architecture, tracker viewport,
  editor, note audition, control panel, and runtime gain/headroom behavior did
  not change.
- Runtime C mixer adapter-plan construction is now lazy: file load invalidates
  stale plans without calling `RuntimeCMixerAdapterEventPlan.make`, improving
  file-open responsiveness for modules dominated by adapter planning. First
  Play prepares/configures the existing cached plan path when needed and can
  carry the deferred planning cost when async prewarm has not completed;
  Stop/Play reuses the cached plan without changing playback semantics, C mixer
  DSP, parser architecture, tracker viewport, editor, note audition, control
  panel, or runtime gain/headroom behavior.
- Disabled-by-default playback load/play timing diagnostics now measure module
  load, playback-song build, load-time adapter-plan invalidation, first-Play
  runtime adapter-plan setup, Play start/reset/enter phases, and Swift-side
  CoreAudio prepare/start without changing playback,
  parser, C mixer DSP, tracker viewport, editor, note audition, control panel,
  TIME display, or runtime headroom policy.
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
  editing is allowed, and runtime song playback, transport state, backend
  selection, C mixer DSP, parser architecture, tracker viewport behavior,
  save/export behavior, and loaded-module read-only editing remain unchanged.
  Full FT2/XM envelope/key-off/fadeout parity, sample editing, sample loading,
  and XI import remain deferred.
- Editor note preview now routes sanitized sample-loop metadata from loaded
  `PlaybackSong` samples into the preview-only render plan and C mixer voice,
  so held Edit-mode preview notes can sustain through existing forward or
  ping-pong sample loops until keyUp cancels the active preview. Non-looping
  samples remain one-shots, and runtime song playback, transport state,
  backend selection, C mixer DSP, parser architecture, tracker viewport
  behavior, save/export behavior, and loaded-module read-only editing remain
  unchanged. Full FT2/XM envelope/key-off/fadeout parity and non-Edit-mode
  audition remain deferred.
- Editor note preview now stops/cancels the active preview-only voice on the
  matching Edit-mode tracker note keyUp. The release path is token-gated so
  stale keyUp events from a replaced preview do not cancel the newer preview,
  keyUp does not write pattern `===`, backtick remains the explicit pattern
  key-off entry, repeated keyDown suppression is preserved, and runtime song
  playback, transport state, backend selection, C mixer DSP, parser
  architecture, tracker viewport behavior, save/export behavior, and
  loaded-module read-only editing remain unchanged. Full FT2/XM release
  envelope parity and non-Edit-mode audition remain deferred.
- Editor note preview now maps lower-row keys to the selected octave and
  upper-row keys to selected octave + 1 for preview pitch in the same
  preview-only mixer path used by the audible sink. Loaded-module preview used
  the selected instrument and the then-current sample-map/first-playable
  sample selection policy, new preview notes clear prior preview voices before
  replacement, and preview gain uses loaded-module adapter sample gain at
  neutral channel/global volume plus default runtime C mixer output headroom,
  with a final preview-only safety cap inside the isolated preview sink.
  Runtime song playback, transport state, backend selection, C mixer DSP,
  parser architecture, tracker viewport behavior, save/export behavior, and
  loaded-module read-only editing remain unchanged. Full gain parity, preview
  key-release/key-off behavior, and non-Edit-mode audition remain deferred.
- Audible note preview architecture now has a preview-only audio sink behind
  the existing editor note-audition seam. Positive loaded-module note-on
  requests with copied sample payload can render a short isolated one-shot
  preview through a separate C mixer/CoreAudio boundary without changing
  runtime song playback, Play/Stop transport, backend selection, parser
  architecture, tracker viewport behavior, save/export behavior, or loaded
  module read-only editing. The first spike proves the isolated editor preview
  path only: full preview gain parity against normal Play/song playback,
  non-Edit-mode keyboard audition, and preview key-release/key-off behavior
  remain deferred.
- Generated public fixture coverage now proves positive loaded-module
  note-audition availability for selected `I01` / `S01` through
  `tests/reference-xm/generated/basic-instrument-sample.xm` and
  `PlaybackSongBuilder`, while keeping backend behavior, parser architecture,
  tracker viewport behavior, and loaded-module editing unchanged.
- Generated `tests/reference-xm/generated/basic-instrument-sample.xm` from the
  synthetic fixture generator with one public-safe instrument/sample payload and
  focused parser/editor positive-path tests, without adding WAV renders,
  backend behavior, parser architecture changes, tracker viewport changes,
  editor behavior, or note audition audio.
- Synthetic XM fixture generator skeleton now adds the public fixture-pack
  README, deterministic source manifest, generator script contract, and focused
  script tests without adding binary XM files, WAV reference renders, backend
  behavior, parser architecture changes, tracker viewport changes, editor
  behavior, or note audition audio.
- Synthetic redistributable XM fixture pack planning now defines public-safe
  fixture structure, licensing rules, focused fixture families, and local
  reference-render policy without adding fixture assets or changing backend,
  parser, tracker viewport, or editor behavior.
- Note audition preview routing now has a small no-audio coordinator and
  injected test sink seam behind the inert request and loaded-module
  availability model. It attempts only note-on requests with loaded-module
  previewable descriptors, keeps blank documents unavailable without real
  sample payload, keeps opened modules read-only, and leaves runtime playback,
  C mixer DSP, backend selection, parser architecture, and tracker viewport
  behavior unchanged.
- Note audition preview availability now resolves loaded-module selected
  instrument/sample state against safe `PlaybackSong` sample data, returning
  inert descriptors for previewable payloads while keeping blank documents
  unavailable without real payload and leaving audio/backend/parser behavior
  unchanged.
- Note audition preview planning now adds an inert editor-side request and
  availability seam. Blank documents without real instrument/sample payload
  remain preview-unavailable, loaded modules may become auditionable before
  editing, and no audio/backend/parser behavior changed.
- Blank-document note entry now supports the two-row tracker keyboard map:
  lower row at selected octave, upper row at selected octave + 1, with high-C
  keys and audio audition deferred.
- Blank documents now carry selected 1-based instrument/sample slot state and
  show those slots truthfully in the control panel, without adding preview
  playback, backend dependencies, or loaded-module editing.
- Blank-document note entry now includes the lower-row natural/sharp keymap,
  backtick key-off entry rendered as `===`, note-cell clear back to `...`, and
  the centralized default one-row edit-step behavior, without opening loaded
  modules for mutation.
- First blank-document pattern-entry slice adds in-memory natural-note entry
  for the selected note cell with immediate display refresh and clamped
  one-row edit advance, without making opened modules editable.
- macOS menu foundation adds a normal minimal AppKit menu structure while
  leaving backend, parser, playback planning, and tracker viewport behavior
  unchanged.
- Main window control-panel readouts and tooltips now reflect blank startup,
  File New reset, and loaded-module metadata without changing playback,
  parser architecture, or tracker viewport behavior.
- Backend-freeze and diagnostic wording cleanup recently landed without
  playback behavior changes.
- Current effect support and parity-watch items live in
  `docs/xm-effect-support.md`.
- Detailed backend sequencing and historical notes live in `docs/roadmap.md`.

Behavior-changing effect PRs should include focused tests and update
`docs/xm-effect-support.md`.

## Phase 1: Core Tracker

Goal: a reliable tracker grid and navigation foundation.

Status: in progress, with read-only display and viewport behavior already
implemented.

Implemented:

- blank tracker startup and File New foundation
- two-row tracker keyboard map
- static highlight row
- shared slot model for gutter/body alignment
- wrap behavior
- keyboard navigation baseline
- pattern selection

Remaining:

- note audition parity follow-through after selection and keyboard foundations
- instrument/effect entry
- copy/paste workflows
- pattern length/edit operations
- broader keyboard workflow parity

Note audition now has a minimal loaded-module audible preview path behind the
editor/audio boundary. Edit-mode key release stops only the active preview
voice; pattern key-off remains explicit `===` entry. Loaded modules may be
auditionable before they are editable, while XI import, sample loading,
instrument editing, and sample editing remain later 1.0 composition
milestones.

## Phase 2: Audio Engine And Playback Accuracy

Goal: deterministic, reference-comparable playback.

Status: temporary backend foundation freeze; behavior changes require a
promoted freeze-exit blocker.

Current responsibilities:

- keep CoreAudio C mixer as the runtime path
- keep offline render/export as comparison authority
- maintain clear separation between runtime, parser, tracker viewport, and
  offline render behavior
- use `docs/audio-comparison.md` for comparison workflows
- use `docs/playback-trace.md` for runtime trace/capture diagnostics
- use `docs/xm-effect-support.md` for effect support state

Current non-goals:

- no retired AVAudio backend reintroduction
- no parser architecture changes as part of backend effect work
- no tracker viewport changes as part of audio work
- no private corpus artifacts in git

## Phase 3: Pattern And Song Editing

Current recommended product phase after the backend foundation freeze. This is
part of the VTX 1.0 composition path, not a playback-only milestone.

First-pass scope now complete for the `v0.2.0-alpha.3` composition alpha:

- note entry and row advance
- clear current pattern
- clear song data while preserving instruments and samples
- Song / Order editor foundation
- Pattern Bank viewing/navigation and explicit assignment
- Pattern Ops NEW/DUP/CLEAR
- Order Ops INSERT/DELETE/DUP/MOVE UP/MOVE DOWN/PTN -/+
- Play Current Pattern and Loop-at-Play-start composition audition

Export XM v1 was released as `v0.2.0-alpha.4` and covers stopped editable
documents in the current VTX editable subset, including supported existing
palette/sample payloads where safely represented.

Rendered audio export was released as `v0.2.0-alpha.5`: whole-song 48 kHz
Float32 WAV is the preferred high-quality and diagnostic format, while
AAC-in-M4A provides a convenient sharing format. Both write only to a selected
destination and preserve loaded-module read-only and disabled Save/Save As
semantics.

Remaining phase scope:

- instrument entry
- volume-column entry
- effect entry
- selection and copy/paste
- broader arrangement/order-table polish while preserving the instrument bank
- pattern length editing and deeper pattern-table utilities
- editable-copy/save semantics before loaded-module mutation
- save XM
- advanced audio export options

Loaded modules remain read-only by default. Broader direct editing and Save/Save
As semantics remain deferred.

## Phase 4: Instruments And Samples

Implemented foundation:

- document-level applyEdit/undo using capped whole-value snapshots, with Clear
  Current Pattern and represented instrument rename routed through it
- v1-mockup-aligned Instrument Editor shell bound to loaded modules,
  editable documents, editable copies, and the current instrument/sample
  selection; only the represented instrument NAME field is editable in stopped
  editable documents, with future sample/import/envelope/keymap/audition
  controls inert
- exact XM sample panning byte representation, loaded/editable-copy/snapshot/
  Export XM preservation, and disabled Instrument Editor PAN display; runtime
  playback and render output remain unchanged

Remaining VTX 1.0 scope:

- panning-envelope, autovibrato, and broader instrument
  metadata/editing foundations behind applyEdit
- sample editor foundation
- WAV/AIFF sample import
- XI instrument import target
- importing or copying instruments and samples from existing modules into
  blank/editable songs
- sample trimming and loop editing foundation
- envelope editing foundation

## Phase 5: Visualization

Planned scope:

- waveform scopes
- activity meters
- tracker-friendly playback visualization

## Phase 6: Module Management

Planned scope:

- module metadata panel
- preferences
- playback/export settings
- UI configuration

## Phase 6.5: v1.x And Future Pro Scope

Likely v1.x or later work includes MIDI keyboard or pad input, recording and
sample-capture improvements, richer resampling tools, and plugin/audio-input to
sample experiments.

Future Pro or native-format work may explore AUv3/VST-style plugin hosting,
plugin instruments/effects, plugin-to-sample rendering, automation, a native
VTX project format or XM3-style extended format, and AI-assisted
instruments/samples/patterns. These are not VTX 1.0 requirements, and classic
XM compatibility should not require live plugin playback.

## Phase 7: Release Hardening

Planned scope:

- CI and local verification cleanup
- packaging
- documentation pass
- performance review
- public release readiness

## Documentation Rules

- Read `docs/agent-current-state.md` before long backend docs.
- Do not append long investigation reports to this file.
- Put public-safe long reports under `docs/reports/` only when requested.
- Put private/local reports and generated artifacts under `/tmp`.
