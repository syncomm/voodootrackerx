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

The app is still under active development and is not production-ready.

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

Recommended next work should return to GUI/editor and product milestones:

1. Design a weekly codebase review harness as a docs/tooling plan before
   adding automation.
2. Module analysis follow-up should use
   `docs/design/module-analysis-lifecycle.md`: async adapter-plan prewarm now
   prepares the same cached runtime plan after load without blocking file open,
   while first-Play adapter-plan preparation remains the synchronous fallback.
   Loaded-module TIME now reads only from the installed cached/prewarmed
   adapter-plan duration with clear load/File New invalidation. A later
   optimization PR can profile and reduce adapter-plan construction cost
   itself.
3. README badges may be added later if they point at stable, useful CI or
   release signals.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless new
  linear-corpus evidence promotes it.

Recently completed narrow target:

- Clear Current Pattern is now available from the Edit menu for blank/editable
  documents only. It clears the selected blank pattern back to empty cells,
  removes key-off cells, refreshes the tracker display, and preserves selected
  instrument/sample/octave, tempo/BPM, speed, channels, rows, pattern count,
  order state, cursor location, viewport/static-highlight behavior, runtime
  playback, note audition, and loaded-module read-only policy. Clear song while
  preserving instruments/samples, reset arrangement/order table, duplicate
  pattern, insert/delete pattern or order slots, undo/redo, save XM, and export
  WAV/AAC remain deferred.
- Adapter-safe pattern-loop playback now uses the existing Loop control at Play
  start to repeat the selected/current order/pattern through a bounded range of
  the cached `RuntimeCMixerAdapterEventPlan`. The loop path keeps adapter-plan
  event consumption, avoids timer-driven note triggers, preserves active C
  mixer state across wraps, and leaves C mixer DSP, parser architecture,
  runtime gain/headroom, tracker viewport, editor behavior, note audition,
  save/export, and release workflow unchanged. Live Loop toggle during active
  playback, loop-length TIME display, pattern-loop editing, clear-pattern/
  clear-song utilities, arbitrary ranges, and broader local corpus listening
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

- note preview/audition follow-through after selection and keyboard foundations
- instrument/effect entry
- copy/paste workflows
- pattern length/edit operations
- broader keyboard workflow parity

Note audition now has a minimal loaded-module audible preview path behind the
editor/audio boundary. Edit-mode key release stops only the active preview
voice; pattern key-off remains explicit `===` entry. Loaded modules may be
auditionable before they are editable, while XI import, sample loading,
instrument editing, and sample editing remain later milestones.

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

## Phase 3: Pattern Editing

Current recommended product phase after the backend foundation freeze.

Planned scope:

- note entry and row advance
- instrument entry
- effect entry
- selection and copy/paste
- clear current pattern
- clear song/pattern data while preserving instruments and samples
- optional arrangement/order-table reset while preserving the instrument bank
- pattern insertion/deletion
- pattern length editing
- save/export flow design before persistence work

## Phase 4: Instruments And Samples

Planned scope:

- instrument panel
- sample panel
- sample trimming
- loop editing
- envelope editing

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
