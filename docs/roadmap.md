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

Keep these as small, separately verifiable PRs:

1. `Lxx` set envelope position foundation.
2. Volume-column `F0...FF` tone portamento.
3. `R00` memory refinement for multi-retrigger.
4. Amiga frequency-table foundation, including Amiga-table pitch/effect
   behavior as its own milestone.
5. Backend hardening and cleanup after the linear-XM foundation is frozen.

Each behavior-changing PR should include focused tests and update
`docs/xm-effect-support.md` when support changes.

## Backend Cleanup / Hardening

Allowed after the current linear-XM target set is stable:

- remove or simplify obsolete diagnostics that no longer support active work
- inventory scripts before consolidation
- document which tools are current, historical, or local-only
- keep runtime, parser, tracker viewport, and offline render responsibilities
  separate

Not allowed in this docs milestone:

- playback behavior changes
- script behavior changes
- parser architecture changes
- tracker viewport changes
- retired AVAudio backend reintroduction

Recommended next docs/tooling PR:

- Diagnostic Script Inventory / Consolidation Plan

## Milestone 3: UI / Tracker Feel

Status: read-only tracker display and stable viewport behavior are implemented;
full editing remains future work after backend foundation freeze.

Current implemented foundation:

- AppKit tracker shell
- module open/load flow
- metadata display
- tracker-style pattern grid display
- static highlight row behavior
- stable viewport navigation
- pattern selection
- basic transport smoke workflow

Next editor targets after backend foundation freeze:

- note entry and row advance
- instrument and effect entry
- copy/paste rows and selections
- pattern insert/delete/length editing
- order/program display and pattern switching
- keyboard workflow parity

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
- Amiga frequency-table support has an agreed foundation plan
- local comparison workflow is documented and generated artifacts stay out of
  git
- CI and `scripts/check-files.sh` remain green
