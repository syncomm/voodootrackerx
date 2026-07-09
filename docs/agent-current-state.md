# Agent Current State

Read this first when starting backend, audio, parser, effect, or tooling work.
It is the short current-state snapshot; load longer docs only when the task
needs them.

## Product Scope Pointer

VTX 1.0 is scoped as a self-contained XM-style sample/instrument tracker that
can create complete sample-based songs from scratch. It is not only a playback,
display, or pattern-entry milestone, and it is not a DAW/plugin-host milestone.

Loaded modules remain read-only by default. Supported stopped loaded XM modules
can be converted only through the explicit `File > Make Editable Copy` command,
which creates an untitled in-memory editable copy without claiming the opened
source path.
Future plugin or audio-input bridges should start as later sample/import
experiments, not live plugin playback inside classic XM compatibility.

Release status: `v0.2.0-alpha.4` is the prepared Export XM v1 alpha for VTX
editable documents. It covers the current editable subset, including supported
existing instrument/sample payloads where safely represented. Product
whole-song 32-bit Float WAV export is now available from
`File > Export Audio > WAV...` for stopped loaded modules, editable documents,
and editable copies. It is non-mutating, writes only to the selected
destination, does not claim source-path ownership, keeps Save/Save As disabled,
does not use the diagnostic bounded-render cap, renders through the same
64-row windowed offline path used by the proven render tool mode, and applies
export-boundary auto-headroom without a second full mixer render. The app
product default is 48 kHz Float32. The release is not a full arbitrary-XM
round-trip guarantee or a full
FT2/OpenMPT/MilkyTracker parity claim. Save/Save As, loaded-module direct
editing, Instrument Editor, Sample Editor, AAC/M4A export, PCM16 product
export, pattern/order ranges, channel/stem export, diagnostic comparison
profile UI, and user-selectable gain/headroom remain future work.

## Backend Architecture

- Runtime playback defaults to the CoreAudio DefaultOutput Audio Unit host
  driving the C mixer render core.
- `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` are
  explicit aliases for the same CoreAudio C mixer path.
- `VTX_AUDIO_BACKEND=av_audio` is retired. It must not be reintroduced as a
  runtime backend; it falls back to the CoreAudio C mixer and reports a
  diagnostic fallback reason.
- The retired AVAudioPlayerNode / AVAudioUnitVarispeed path and the retired
  AVAudioSourceNode C mixer host must not return.
- The Swift playback/adapter layer plans module events; the C mixer owns the
  render core used by runtime playback and bounded offline renders.
- Offline render/export remains the reference workflow for deterministic audio
  comparison. Runtime smoke checks validate the app host path and delivery.
- Product WAV export uses the existing bounded offline C mixer render path with
  VTX mix profile, whole-song 48 kHz Float32 WAV output, explicit
  user-initiated long-render planning, 64-row windowed scheduling, and
  export-boundary auto-headroom. The app path renders the mixer once, records
  peak diagnostics while writing an unscaled Float32 temp WAV, then applies the
  shared auto-headroom gain through a streamed Float32 WAV post-process; it
  does not change runtime playback, scheduling, or C mixer DSP.
- `CSoftwareMixer` owns the large `VTXCMixerState` on the heap so background
  offline export/render workers do not initialize that fixed-size C state on a
  smaller GCD worker stack.

## Current Runtime Default

Unset `VTX_AUDIO_BACKEND` means CoreAudio C mixer. Unknown backend names fall
back to that default and should remain diagnostics, not alternate behavior.

Runtime-only diagnostics may use:

- `VTX_C_MIXER_RUNTIME_TRACE_PATH` for local JSONL trace output.
- `VTX_C_MIXER_RUNTIME_CAPTURE_PATH` for local runtime CoreAudio capture.
- `VTX_RUNTIME_MIXER_METRICS_TRACE` for sanitized runtime mixer stop summaries.
- `VTX_DEBUG_AUTOPLAY` and `VTX_DEBUG_STOP_AFTER_SECONDS` for bounded manual
  smoke runs.

Generated traces, captures, logs, reports, screenshots, and listening notes
stay under `/tmp` or another untracked local path.

Xcode 16.4 CI has crashed the Swift frontend when new diagnostics were wired
through compiler-sensitive default `PlaybackEngine()` stored-property
initialization from `AppDelegate`. For diagnostic PRs, keep new recorder/sink
objects disabled by default and prefer explicit AppDelegate/factory injection
or small value types over adding diagnostic object creation to PlaybackEngine
default initializer paths. Treat the macOS CI Xcode build as the verification
gate even when local SwiftPM and newer local Xcode builds pass.

## Offline Render / Export Workflow

Use `swift run -c release vtx_render_bounded_xm` for local candidate renders.
Plain `swift run` builds Debug by default and is not valid for render/export
performance comparisons. The render tool loads XM through the repo
parser/builders and renders through the bounded offline C mixer path.

For product-comparable local render timing, prefer `./scripts/bench-render.sh`.
Generated WAVs, diagnostics, reports, and timing notes stay under `/tmp` or
another ignored local path.

For FT2-style reference comparisons, prefer:

```bash
LOCAL_XM="path-to-untracked-local-module.xm"

swift run -c release vtx_render_bounded_xm \
  --input "$LOCAL_XM" \
  --output /tmp/vtx-ft2-profile-candidate.wav \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --sample-rate 48000 \
  --until-song-end \
  --tail-seconds 3 \
  --window-rows 64 \
  --allow-long-render \
  --wav-format float32 \
  --mix-profile ft2
```

Use `--mix-profile vtx` when you are validating the project default export
policy. Use `--mix-profile ft2` when comparing against the ft2-clone Linear
reference policy.

Use `--wav-format float32` for reference comparison and overrange/headroom
diagnostics. Use default PCM16 only for quick listening smoke checks or when a
target tool requires PCM.

## ft2-clone Reference Policy

ft2-clone Linear is the primary FT2-style XM reference when a matching local
export is available. Record the local reference settings in any local report:

- sample rate
- Float32 or PCM export format
- Linear interpolation
- Linear frequency slides
- amplification and master volume
- volume ramping setting
- precise BPM setting
- whether stems or individual tracks were exported

MikMod, OpenMPT/libopenmpt, Renoise, and other tools can be useful secondary
references, but reference correlation alone is not a correctness proof.

## Runtime / Offline Equivalence

For tested modules, runtime CoreAudio capture and offline C mixer render have
been shown equivalent at the render-core/output-capture level. Treat new
runtime/offline mismatch evidence as a diagnostic task: confirm capture bounds,
sample rate, gain/headroom, trace health, and comparison settings before
proposing playback behavior changes.

## Private Corpus Rules

- Do not commit private modules or artifacts derived from them.
- Do not publish private filenames, local absolute paths, or machine-specific
  notes.
- Use anonymized labels only when examples are necessary.
- Keep local label maps outside the repository.
- Put local/private reports under `/tmp` unless the maintainer explicitly asks
  for a public-safe committed report.

## Effect Support Pointer

`docs/xm-effect-support.md` is the canonical current effect support table.
Read it before effect work and update it when an effect PR changes support.
It uses Implemented / Implemented, parity-watch / Deferred terminology to
separate current VTX support from tracked parity gaps and unimplemented
commands.

## Diagnostic Tooling Pointer

For diagnostic script inventory and consolidation planning, see
`docs/diagnostic-tools.md`.

## Backend Freeze Posture

The XM backend is under a temporary foundation freeze. Do not promote
behavior-changing effect, C mixer DSP, parser architecture, runtime backend, or
tracker viewport work by default.

Backend PRs should be promoted only for release-blocking crashes,
deterministic runtime/offline mismatches, severe open-time/performance
regressions, or maintainer-promoted compatibility blockers.

Parked parity-watch items:

- Broader Amiga-table follow-up for the remaining late looped-sample phase
  residual; use reference-stem/per-voice diagnostics before changing VTX loop,
  ramp, timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless the maintainer
  promotes it under a freeze-exit criterion.

Recently completed narrow targets:

- `File > Export Audio > WAV...` now renders the current stopped loaded module,
  editable document, or editable copy to a user-selected 32-bit Float WAV via
  the existing bounded offline C mixer path. The app uses the VTX mix profile,
  an explicit user-initiated whole-song long-render policy, default song-end
  tail, 48 kHz output, 64-row windowed scheduling, and export-boundary
  auto-headroom instead of the diagnostic bounded-render cap. It performs one
  expensive mixer render, writes an unscaled Float32 temp WAV while computing
  peak diagnostics, applies the shared auto-headroom gain through a streamed
  Float32 WAV post-process, shows throttled determinate progress over the full
  planned render and headroom phases while rendering on a background queue,
  writes through temporary files before replacing the selected destination,
  removes temporary output on failure, leaves source modules/documents
  untouched, does not claim source-path ownership, keeps Save/Save As disabled,
  and leaves loaded modules read-only. Cancellation,
  AAC/M4A, PCM16, pattern or order ranges, channel/stem export, normalization,
  diagnostic comparison profiles, and user-selectable gain/headroom remain
  future work.
- `File > Make Editable Copy` now defines the explicit loaded-module editable
  copy boundary. It is available only for stopped loaded read-only XM modules
  that can be represented by the current editable subset, creates an untitled
  in-memory editable copy of supported song/order/pattern/note data plus
  represented palette/sample payloads, leaves the source module read-only and
  untouched, does not claim source-path ownership, keeps Save/Save As disabled,
  and allows stopped Export XM to a user-selected destination. Runtime
  playback/scheduling, `RuntimeCMixerAdapterEventPlan`, C mixer DSP, parser
  architecture, and tracker viewport/static-highlight behavior did not change.
- Export XM v1 release-prep documentation for `v0.2.0-alpha.4` now states the
  scoped release claim, manual smoke checklist, and maintainer-only post-merge
  tag instructions. No tag should be created by the PR.
- XM diagnostic and residual-scan recommendation wording aligned with the
  backend freeze and `docs/xm-effect-support.md`; no playback behavior changed.
- Amiga frequency-table foundation for note period/frequency/sample-step
  calculation, sample finetune metadata, Amiga-table `2xx` portamento down,
  and effect-column `3xx` tone portamento in the shared runtime/offline C
  mixer adapter path.
- `Lxx` set envelope position foundation.
- Volume-column `F0...FF` tone portamento foundation.
- Final expanded-corpus linear-XM effect coverage before Amiga; no deferred
  linear command was promoted ahead of Amiga frequency-table work.

Retired AVAudio backend cleanup belongs to docs/tooling or deletion tasks only;
do not reintroduce retired playback paths.

## Required Verification Command Groups

For docs/tooling hygiene PRs:

```bash
./scripts/check-files.sh
git diff --check
```

Also run the private-name/local-path scan requested by the task or PR checklist.
Do not copy private names or local absolute path patterns into committed docs.

For effect/backend behavior PRs, also run focused Swift tests for the touched
adapter/mixer area and update `docs/xm-effect-support.md` when support changes.

For tracker viewport work, use the tracker UI docs and manual screenshot
verification. Do not treat backend docs as viewport guidance.

## Long-Doc Loading Rules

- Read `docs/audio-comparison.md` only for render/reference comparison work.
- Read `docs/playback-trace.md` only for runtime trace or diagnostic work.
- Read `docs/roadmap.md` for current milestone sequencing.
- Read `docs/dev-roadmap.md` for the short phase summary.
- Read reports under `docs/reports/` only when investigating that historical
  thread.
