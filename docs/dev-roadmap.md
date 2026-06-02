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
- Runtime CoreAudio capture and offline render have been shown equivalent for
  tested modules when settings and bounds match.
- `vtx_render_bounded_xm` supports Float32 WAV export and the FT2 mix profile.
- ft2-clone Linear is the primary FT2-style XM reference when local settings
  are recorded and match the candidate.

## Current Backend Targets

The XM backend is in a temporary backend foundation freeze. During the freeze,
avoid behavior-changing effect, C mixer DSP, parser architecture, runtime
backend, and tracker viewport work unless a freeze-exit blocker is promoted.

Recommended next work should return to GUI/editor and product milestones:

1. Start the first small pattern-entry/editor workflow slice.
2. Audit module-open performance boundaries so expensive diagnostics stay
   explicit and local-only.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless new
  linear-corpus evidence promotes it.

Recently completed narrow target:

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
- `Lxx` set envelope position first-pass support for active volume envelopes in
  the shared runtime/offline C mixer path.
- Volume-column `F0...FF` tone portamento first-pass support reusing the
  existing `3xx` target/sample-step path.
- Final expanded-corpus linear-XM effect coverage before the Amiga foundation;
  no deferred linear command was promoted ahead of Amiga frequency-table work.

Behavior-changing effect PRs should include focused tests and update
`docs/xm-effect-support.md`.

## Phase 1: Core Tracker

Goal: a reliable tracker grid and navigation foundation.

Status: in progress, with read-only display and viewport behavior already
implemented.

Implemented:

- static highlight row
- shared slot model for gutter/body alignment
- wrap behavior
- keyboard navigation baseline
- pattern selection

Remaining:

- edit mode
- note/instrument/effect entry
- copy/paste workflows
- pattern length/edit operations
- broader keyboard workflow parity

## Phase 2: Audio Engine And Playback Accuracy

Goal: deterministic, reference-comparable playback.

Status: active backend foundation.

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

Begin after the backend foundation is stable enough that editor work is not
blocked by playback churn.

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
