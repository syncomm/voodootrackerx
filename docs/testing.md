# Testing Guide

Practical testing notes for parser/core work and snapshot-based regression checks.

## Fixture Rules

Fixtures live in `tests/fixtures/`.

Rules:
- Use synthetic, tiny fixtures generated for tests.
- Do not add copyrighted module music.
- Keep fixtures minimal and deterministic (header-only when possible).
- Update `tests/fixtures/README.md` if provenance/generation guidance changes.

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
