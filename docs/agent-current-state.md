# Agent Current State

Read this first when starting backend, audio, parser, effect, or tooling work.
It is the short current-state snapshot; load longer docs only when the task
needs them.

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

## Current Runtime Default

Unset `VTX_AUDIO_BACKEND` means CoreAudio C mixer. Unknown backend names fall
back to that default and should remain diagnostics, not alternate behavior.

Runtime-only diagnostics may use:

- `VTX_C_MIXER_RUNTIME_TRACE_PATH` for local JSONL trace output.
- `VTX_C_MIXER_RUNTIME_CAPTURE_PATH` for local runtime CoreAudio capture.
- `VTX_DEBUG_AUTOPLAY` and `VTX_DEBUG_STOP_AFTER_SECONDS` for bounded manual
  smoke runs.

Generated traces, captures, logs, reports, screenshots, and listening notes
stay under `/tmp` or another untracked local path.

## Offline Render / Export Workflow

Use `swift run vtx_render_bounded_xm` for local candidate renders. It loads XM
through the repo parser/builders and renders through the bounded offline C
mixer path.

For FT2-style reference comparisons, prefer:

```bash
LOCAL_XM="path-to-untracked-local-module.xm"

swift run vtx_render_bounded_xm \
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

## Current Remaining Backend Targets

Keep these as separate, small PRs:

- Amiga reference/parity follow-up for the narrow Amiga-table note/`2xx`/`3xx`
  foundation.
- `R00` memory refinement as a later parity-watch cleanup unless new
  linear-corpus evidence promotes it.
- Backend hardening and cleanup after the linear-XM foundation is frozen.

Recently completed narrow targets:

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
