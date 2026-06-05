# VoodooTracker X Roadmap

This is the current PR sequencing guide. It intentionally avoids historical
play-by-play; older audio comparison details live under `docs/reports/`.

For the shortest backend snapshot, read `docs/agent-current-state.md` first.
For effect status, read `docs/xm-effect-support.md`.

## Project Goals

- Preserve classic MOD/XM compatibility and tracker workflow.
- Keep the AppKit tracker editor keyboard-first.
- Make playback deterministic enough for local reference comparison.
- Add editing, instrument, visualization, and modern workflow features only
  after the backend foundation is stable.

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

1. Start the first small pattern-entry/editor workflow slice.
2. Audit module-open performance boundaries so expensive diagnostics stay
   explicit and local-only.

Parked parity-watch items:

- Amiga-table follow-up for the remaining late looped-sample phase residual:
  use reference-stem/per-voice diagnostics before changing VTX loop, ramp,
  timing, or sample-step behavior.
- `R00` memory refinement for multi-retrigger as a later parity-watch cleanup
  unless new linear-corpus evidence promotes it.

Recently completed:

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

- Note audition preview planning at the editor/audio boundary.

Recently completed product foundation:

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

## Milestone 3: UI / Tracker Feel

Status: read-only tracker display and stable viewport behavior are implemented;
full editing remains future work after backend foundation freeze.

Current implemented foundation:

- AppKit tracker shell
- blank tracker startup and File New foundation
- module open/load flow
- metadata display
- tracker-style pattern grid display
- static highlight row behavior
- stable viewport navigation
- pattern selection
- basic transport smoke workflow

Next editor targets after backend foundation freeze:

- upper-row note entry and future note audition follow-through
- instrument and effect entry
- copy/paste rows and selections
- pattern insert/delete/length editing
- order/program display and pattern switching
- keyboard workflow parity

### Future Note Audition Path

The editor selection state should remain independent from parser internals and
audio backends. Planned sequencing is:

- keep selected 1-based instrument/sample slots as editor state first
- add the optional upper keyboard row before preview behavior
- add note audition later using the selected instrument/sample source
- treat key release as preview key-off only
- keep pattern key-off as explicit `===` entry through the tracker key binding
- allow loaded modules to become auditionable before they become editable
- defer XI import, sample loading, instrument editor, and sample editor to later
  milestones

Tracker viewport work must follow `docs/tracker-behavior-spec.md`,
`docs/ui-debugging.md`, and `docs/visual-verification.md`.

## Milestone 4: Nostalgia / Look And Feel

Wait until tracker behavior and backend foundations are stable.

Planned scope:

- visual theme baseline
- tracker typography and spacing polish
- keyboard workflow polish
- classic tracker behavior parity fixes

## Milestone 5: Modern Enhancements

Wait until core parity is stable.

Potential scope:

- quality-of-life workflow improvements
- export workflow polish
- preferences and module metadata panels
- waveform scopes and activity visualization
- sample/instrument editing

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
