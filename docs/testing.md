# Testing Guide

Practical testing notes for parser/core work and snapshot-based regression checks.

## Fixture Rules

Fixtures live in `tests/fixtures/`.
Future generated XM reference fixtures live under `tests/reference-xm/` once
explicitly reviewed.

Rules:
- Use synthetic, tiny fixtures generated for tests.
- Do not add copyrighted module music.
- Keep fixtures minimal and deterministic (header-only when possible).
- Update `tests/fixtures/README.md` if provenance/generation guidance changes.
- For `tests/reference-xm/`, follow that directory's README and keep binary XM
  fixture commits explicit and reviewed.

Regenerate the public synthetic XM reference manifest or approved XM fixture
from the repo root with:

```bash
python3 scripts/generate-synthetic-xm-fixtures.py --write-manifest
python3 scripts/generate-synthetic-xm-fixtures.py --write-xm
```

## Run Core Tests

```bash
swift test --filter ModuleCoreTests
```

## Manual Playback Stabilization Checklist

Use a local, known-good XM file. Do not commit copyrighted module files.

- Launch the app.
- Load the XM file.
- Press Play and confirm audio plays while the tracker follows rows.
- Confirm modules with `Fxx` speed/tempo commands visibly change playback pace when those rows are reached.
- Confirm modules with `Bxx` position jumps or `Dxx` pattern breaks continue safely without crashes or corrupted tracker state.
- Confirm modules with `0xy` arpeggio commands produce audible tick-cycled pitch changes.
- Confirm modules with `1xx` or `2xx` portamento commands produce smooth first-pass pitch slides without destabilizing playback.
- Confirm modules with `3xx` tone portamento commands slide active notes toward target notes without doubled retriggers.
- Confirm modules with `4xy` vibrato commands produce audible pitch modulation.
- Confirm modules with `5xy` or `6xy` combined volume-slide commands keep the pitch effect active while changing volume.
- Confirm modules with `7xy` tremolo commands produce audible volume modulation.
- Confirm modules with `9xx` sample offset commands start sample playback later in the sample without crashing on out-of-range offsets.
- Confirm modules with `Gxx` global volume commands safely change overall playback volume without breaking per-channel volume behavior.
- Confirm modules with `Hxy` global volume slide commands change overall playback volume progressively across ticks.
- Confirm modules with `E9x` retrigger commands repeat active notes at the configured tick interval without runaway stacked audio.
- Confirm modules with `ECx` note cut commands stop active notes cleanly on the configured tick.
- Confirm modules with `EDx` note delay commands trigger notes later in the row, and invalid delay values fail safely.
- Confirm modules with `EEx` pattern delay commands hold tracker follow on the current row for the configured additional row durations.
- Confirm modules with `Axy` volume slide commands change volume progressively across ticks.
- Press Play again while already playing and confirm playback does not stack, restart unexpectedly, or create doubled audio.
- Press Stop and confirm tracker progression stops and audio stops immediately.
- Press Stop again and confirm there is no crash or bad state.
- Repeat Play/Stop several times and confirm there are no stuck notes, stale timers, or hangs.
- Load another XM while stopped and confirm playback state resets cleanly.
- Load another XM while playing and confirm the old playback stops before the new module is shown.
- Let playback reach the end if practical and confirm it stops predictably.
- Confirm tracker viewport alignment remains stable.

## Playback Load / Play Timing Diagnostics

Lifecycle timing diagnostics are disabled by default. To measure module load
and Play setup phases during a local smoke run, launch the Debug app from a
terminal with:

```bash
VTX_PLAYBACK_TIMING_TRACE=1 \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Open a public synthetic fixture or another public-safe module, then press Play.
The trace writes stderr lines prefixed with `vtx_playback_timing` and reports
milliseconds for load phases, playback-song setup, async adapter-plan prewarm,
first-Play fallback/reuse state, Play start position resolution, transient
runtime-state reset, adapter event schedule setup, and CoreAudio prepare/start
when reached from Swift-side lifecycle code.

Load traces should show `runtime_adapter_event_plan_invalidated` and
`runtime_adapter_event_plan_prewarm_scheduled`, but not load-time
`runtime_adapter_event_plan_make`. Async prewarm emits a separate `prewarm`
lifecycle with `runtime_adapter_event_plan_prewarm_make` and
`runtime_adapter_event_plan_prewarm_configure` when the plan is installed before
Play. The first Play after loading emits
`runtime_adapter_event_plan_ready_for_play` with `play_adapter_plan_mode`:
`prewarmed` when prewarm finished, `waited` when Play waited for the in-flight
prewarm job, `sync_fallback` when Play had to build synchronously, or
`unavailable` if planning failed. Stop followed by Play should report
`cached_reuse` and omit creation phases unless the song was invalidated by a
new load or File New.

Timing output is observability only. It should not include local paths or
private module titles, and enabling it must not change playback, parser, mixer,
headroom, TIME display, tracker viewport, editor, note audition, or control
panel behavior.

## Runtime Mixer Metrics Trace

Runtime mixer metrics diagnostics are disabled by default. To emit one
sanitized output-level summary when playback stops, launch the Debug app with:

```bash
VTX_RUNTIME_MIXER_METRICS_TRACE=1 \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

The flag also accepts `true`, `yes`, and `on`. The trace writes stderr lines
prefixed with `vtx_runtime_mixer_metrics` and reports aggregate runtime mixer
output metrics from the existing render-core snapshot, including sample rate,
rendered/requested frame counts, output peak/RMS, overrange and clipping sample
counts, adjacent-sample jump/discontinuity counters, and the active runtime
gain/headroom policy.

Example sanitized line:

```text
vtx_runtime_mixer_metrics schema=1 phase=stop_summary runtime_audio_backend=c_mixer stop_reason=transport_stop sample_rate=48000.000000 channel_count=2 rendered_frame_count=96000 output_peak=0.421875 output_rms=0.104331 overrange_sample_count=0 clipping_sample_count=0 clipping_detected=false max_output_adjacent_sample_jump=0.125000 runtime_output_gain=0.251189 runtime_headroom_policy=default_runtime_headroom_db runtime_default_headroom_db=-12.000000 runtime_gain_policy_source=default runtime_auto_headroom_enabled=false
```

Runtime mixer metrics output is observability only. It does not include module
titles, module paths, raw sample data, or private local identifiers, and
enabling it must not change playback, C mixer DSP, scheduling, runtime gain,
runtime headroom, parser behavior, tracker viewport, editor, note audition, or
control panel behavior. It is not runtime auto-headroom.

## Local Corpus Runtime Metrics Runbook

Maintainers can run the disabled timing and runtime mixer metrics diagnostics
against a small private XM corpus subset by supplying a local label map. The
label map must stay outside the repository, and all generated outputs must stay
under `/tmp` or another ignored local directory.

Use only anonymized `xm-corpus-###` labels in summaries, issue notes, and PR
descriptions. Do not publish private module filenames, paths, titles, generated
logs, traces, WAVs, screenshots, or reports.

Build the Debug app first, then run a small subset:

```bash
export VTX_PRIVATE_XM_CORPUS_LABEL_MAP=/path/to/local/private-map.json

scripts/run-local-corpus-runtime-metrics.py \
  --label-map "$VTX_PRIVATE_XM_CORPUS_LABEL_MAP" \
  --labels xm-corpus-001,xm-corpus-002 \
  --seconds 10 \
  --output-dir /tmp/vtx-runtime-metrics-smoke
```

Use `--pre-play-delay-seconds N` to give async prewarm a fixed window before
debug autoplay. The default is `0`, which exercises the immediate-first-play
path where Play may wait for or synchronously complete planning. A short value
such as `5` seconds exercises the delayed-first-play path where first Play
should usually report `prewarmed` if prewarm finished in time.

To inspect the selected anonymized labels before launching the app:

```bash
scripts/run-local-corpus-runtime-metrics.py \
  --label-map "$VTX_PRIVATE_XM_CORPUS_LABEL_MAP" \
  --limit 2 \
  --dry-run
```

The helper launches the Debug app directly with `VTX_OPEN_PATH`,
`VTX_DEBUG_AUTOPLAY=1`, `VTX_DEBUG_STOP_AFTER_SECONDS`,
`VTX_DEBUG_REPLAY_AFTER_STOP=1`, `VTX_PLAYBACK_TIMING_TRACE=1`,
`VTX_RUNTIME_MIXER_METRICS_TRACE=1`, and a label-based local runtime C mixer
trace path. It does not require Accessibility permissions or GUI automation.

By default the helper runs Play, debug Stop, then Play/Stop again so summaries
can compare first Play adapter-plan preparation with cached second Play reuse.
Use `--single-play` only when a one-cycle diagnostics smoke is enough.

Output filenames are based on the anonymized label only, for example
`xm-corpus-001.stderr.txt`, `xm-corpus-001.runtime-c-mixer-trace.jsonl`, and
`xm-corpus-001.metrics.json`, plus top-level `summary.json` and `summary.md`.
Summaries include load timing, metadata/build timing, prewarm adapter-plan
timing, first Play timing, first Play adapter-plan mode
(`prewarmed`, `waited`, `sync_fallback`, or `unavailable`), second Play timing,
second Play adapter-plan mode, and whether second Play reused the cached plan.
The helper redacts the private source path and basename from captured
stdout/stderr and writes summaries without module paths, filenames, or titles.
It refuses to write inside the repository unless `--allow-repo-output` is
supplied for synthetic tests.

Private corpus runs are manual local diagnostics only. Do not add them to CI or
automated tests.

## Audio Reference Comparison

Use `docs/audio-comparison.md` when comparing VoodooTracker X playback against a
reference WAV from a local renderer such as `openmpt123` or MikMod.

Example:

```bash
./scripts/audio-compare.py \
  --reference /tmp/reference.wav \
  --candidate /tmp/voodootrackerx.wav \
  --seconds 30 \
  --report /tmp/audio-compare.txt
```

Run its focused regression tests with `python3 -m unittest tools/audio_compare_tests.py`.

## Golden Snapshot Tests

Golden snapshot checks are part of `ModuleCoreTests`.
They compare parser output against stable JSON snapshots in `tests/golden/`.
XM coverage includes a summary snapshot and a single-pattern event snapshot.

Run them with:

```bash
swift test --filter ModuleCoreTests
```

## Regenerate Golden Snapshots (Intentional Behavior Changes Only)

When parser behavior changes intentionally, regenerate snapshots and review the diff:

```bash
./scripts/run-golden.sh
```

Manual equivalent commands:

```bash
swift run mc_dump --json tests/fixtures/minimal.mod > tests/golden/minimal.mod.json
swift run mc_dump --json tests/fixtures/minimal.xm > tests/golden/minimal.xm.json
swift run mc_dump --json --pattern 1 tests/fixtures/minimal.xm > tests/golden/minimal.xm.pattern1.json
```

Then:
- Inspect changes under `tests/golden/`
- Update tests/docs as needed
- Explain the behavior change in the PR description

## Release DMG Workflow

The release workflow runs when a tag matching `v*.*.*` is pushed. It builds the
`VoodooTrackerX` Xcode scheme in Release configuration on a macOS runner as a
universal `arm64` + `x86_64` app, signs it with a Developer ID Application
certificate, packages `VoodooTrackerX.app` into
`dist/VoodooTrackerX-<tag>.dmg`, signs the DMG, notarizes and staples the DMG,
then attaches that DMG to the GitHub Release for the tag.

Manual `workflow_dispatch` runs are package-only dry runs: they build the app,
create the DMG, and upload it as a workflow artifact, but they do not publish a
GitHub Release.

Tag releases require these GitHub Secrets:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`

Encode the Developer ID Application `.p12` as a single-line base64 secret with:

```bash
base64 -i path/to/cert.p12 | tr -d '\n' | pbcopy
```

The release build must set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. Without
that setting, Xcode can inject `com.apple.security.get-task-allow`, which is
not valid for a notarized Developer ID release. The workflow checks the final
app entitlements and fails if that entitlement is present.

The DMG itself is signed with the Developer ID Application identity before
notarization. This is separate from signing the app bundle inside the DMG.

Useful local validation commands for signed releases:

```bash
codesign --verify --deep --strict --verbose=2 VoodooTrackerX.app
codesign -d --entitlements :- VoodooTrackerX.app
codesign -dv --verbose=4 VoodooTrackerX.app
codesign --verify --verbose=2 VoodooTrackerX-<tag>.dmg
codesign -dv --verbose=4 VoodooTrackerX-<tag>.dmg
xcrun notarytool submit VoodooTrackerX-<tag>.dmg --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple VoodooTrackerX-<tag>.dmg
spctl -a -vvv -t open --context context:primary-signature VoodooTrackerX-<tag>.dmg
```
