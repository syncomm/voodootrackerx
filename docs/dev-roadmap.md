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

1. Plan note audition preview at the editor/audio boundary.
2. Audit module-open performance boundaries so expensive diagnostics stay
   explicit and local-only.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless new
  linear-corpus evidence promotes it.

Recently completed narrow target:

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

Note audition remains a later editor/audio-boundary milestone. The intended
sequence is selected 1-based instrument/sample state, optional upper keyboard
row, then note audition from the selected source. Key release should only send
preview key-off; pattern key-off remains explicit `===` entry. Loaded modules
may become auditionable before they are editable, while XI import, sample
loading, instrument editing, and sample editing remain later milestones.

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
- pattern insertion/deletion
- pattern length editing

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
