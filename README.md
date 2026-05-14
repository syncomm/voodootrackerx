<img src="./assets/logo/vtx-logo.png" alt="VoodooTracker X" width="800" />

**Voodoo Tracker X: A modern resurrection of the classic 1990s FastTracker-style demo scene tracker.**

_VoodooTracker X_ is a modern macOS re-imagining of the classic scene trackers that inspired a generation of chip-tune and demo-scene musicians. Rebuilt from the ground up with modern tooling and macOS native UI in mind, the goal is to preserve the keyboard-first editing feel, pattern-based workflow, and compatibility with classic module formats — while giving the app a stable, testable, and extendable foundation for a future Pro release and iOS ports.

---

## Quick links
- **Repo:** `https://github.com/syncomm/voodootrackerx`
- **License:** MIT

---

## Goals & scope (first pass)
1. Provide playback and editing compatibility for classic module formats (MOD, XM).
2. Deliver a Mac-native UI that respects the original tracker workflows (keyboard navigation, pattern editing).
3. Ship small, verifiable PRs with automated checks and tests so the project can be iterated by agentic tools and humans alike.
4. Keep the core engine open-source while enabling a future commercial “Pro” edition with additional features.

## Current State
VoodooTracker X is now a working macOS AppKit tracker prototype, not just a parser scaffold. The app can open modules, display tracker-style patterns with a static highlight row, navigate the pattern grid from the keyboard, and play XM modules through the current first-pass playback path.

Playback is useful for development and smoke testing, but it is not yet MikMod/OpenMPT accurate. The current runtime playback remains `AVAudioPlayerNode`-based through `AVAudioEngine` and `AVAudioUnitVarispeed`, with implemented passes for transport stabilization, timing and pitch corrections, sample loops including ping-pong loops, panning/stereo placement, volume column semantics, instrument volume envelopes/fadeout, debug seeking, and playback trace export.

A deterministic software mixer path has begun behind the existing audio boundary. The C-backed offline mixer can render deterministic synthetic one-shot sample voices, forward and ping-pong loops, simple linear interpolation for fractional sample steps, volume/panning envelope foundations, frame-scheduled synthetic voices, synthetic tracker row/tick scheduled voices, minimal synthetic pattern playback, and tiny bounded `PlaybackSong` segments through the synthetic adapter with bounded offline render diagnostics. Parsed `PlaybackInstrument.volumeEnvelope` points can now be mapped into that bounded offline adapted render path using the timing active at the event row, adapted note triggers carry explicit XM linear-frequency period/frequency sample-step mapping where supported, and the bounded adapter applies only XM volume-column set-volume/set-panning, a conservative row-level subset of volume-column volume/panning slides, and minimal `Fxx` speed/BPM timing changes. Amiga pitch behavior, full resampler parity, full XM volume-column parity, and full effect parity remain deferred. The path is still offline-only, not full parsed XM song playback, and not the runtime backend yet. Local WAV-to-WAV comparison tooling exists for bounded reference diagnostics, bounded C-backed adapted `PlaybackSong` candidate renders can be exported as deterministic PCM16 WAV files through a developer-only local helper, optional adapter diagnostics JSON can be exported for local trace-to-comparison correlation, a local-only smoke wrapper can compare existing candidate/reference WAVs through `scripts/audio-compare.py`, and a blank local findings template can structure local comparison evidence kept outside git; reference-stabilization fixes remain upcoming.

The app is still under active development and should not be treated as production-ready.

---

## Getting started
```bash
# clone
git clone git@github.com:syncomm/voodootrackerx.git
cd voodootrackerx
open app/VoodooTrackerX/VoodooTrackerX.xcodeproj
```

## Build and test (CLI)
```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Run the app (CLI verification)
```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

open build/Build/Products/Debug/VoodooTrackerX.app
```

Expected result: a single frontmost window titled `VoodooTracker X` opens at a visible default size (about `1000x700`) with a read-only module display.
For XM files, use `File > Open…` and you should see Pattern 0 in a monospaced tracker-style grid.
Navigation: `Up`/`Down` moves the highlighted row, `Page Up`/`Page Down` jumps by 16 rows, `Home`/`End` jumps to first/last row, and `Left`/`Right` changes the focused channel indicator.
Pattern dropdown defaults to used patterns from the song order; enable `Show all patterns` to include full pattern count.

To run the executable directly and see DEBUG startup logs:
```bash
build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Expected DEBUG lines include `[VTX DEBUG] applicationDidFinishLaunching entered` and window creation/show details.

## Core Parser Smoke Tests
```bash
swift test --filter ModuleCoreTests

swift run mc_dump tests/fixtures/minimal.mod
swift run mc_dump tests/fixtures/minimal.xm
swift run mc_dump --json tests/fixtures/minimal.xm
swift run mc_dump --json --include-patterns tests/fixtures/minimal.xm
swift run mc_dump --json --pattern 1 tests/fixtures/minimal.xm

./scripts/run-golden.sh
```

The core parser smoke harness remains focused on deterministic parser coverage and golden snapshots. Playback and mixer work live behind the app audio/playback boundary rather than in the parser module.
See `docs/testing.md` for fixture rules and golden snapshot workflow.

## Developer Audio Comparison Flow
This workflow is for local diagnostic evidence only. It does not prove correctness, does not automatically choose fixes, and does not change runtime playback. Keep generated WAVs, JSON reports, Markdown reports, traces, and notes outside git, preferably under `/tmp`.

Local/private XM modules may be used on a developer workstation for manual smoke testing, listening checks, candidate WAV renders, and local comparisons. Do not commit them, upload them, copy them into fixtures, or require them from automated tests.

`tests/fixtures/minimal.xm` is a tiny redistribution-safe smoke fixture for parser/helper validation. It is not a meaningful audio-parity fixture for MikMod/OpenMPT comparison work.

Render a bounded VoodooTracker X candidate WAV from a local XM file:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-module.xm \
  --output /tmp/vtx-candidate.wav \
  --diagnostics-json /tmp/vtx-candidate-diagnostics.json \
  --order 10 \
  --order-count 1 \
  --rows 16 \
  --sample-rate 44100
```

Render or obtain a matching reference WAV with a local reference renderer, manual capture, or another trusted local render path. Match sample rate, channel count, duration, gain, and renderer settings as closely as possible, then write it outside the repo:

```bash
# Example placeholder; use the reference renderer/settings available on your machine.
reference-renderer --output /tmp/reference.wav /path/to/local-module.xm
```

Compare the candidate and reference WAVs and generate both machine-readable JSON and reviewer-friendly Markdown:

```bash
python3 scripts/audio-compare.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/reference.wav \
  --seconds 30 \
  --window-ms 100 \
  --top-windows 5 \
  --json /tmp/vtx-audio-compare.json \
  --markdown /tmp/vtx-audio-compare.md
```

For a human review pass, prefer the local smoke wrapper because it prints the local tool status, keeps default report names consistent, and records a useful run label:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-candidate.wav \
  --reference /tmp/reference.wav \
  --label local-module-order-10-rows-16 \
  --metadata "order 10, rows 16, 44100 Hz, human listening check" \
  --json /tmp/local-module-order-10-audio-compare.json \
  --markdown /tmp/local-module-order-10-audio-compare.md \
  --seconds 30
```

Read the Markdown first for the summary and worst mismatch windows, then inspect the JSON when you need exact values for a follow-up issue or PR. See `docs/audio-comparison.md` for the detailed workflow and interpretation notes.

If candidate diagnostics JSON was exported, use `scripts/correlate-audio-comparison.py` to create a local-only report that maps worst mismatch windows to approximate adapter rows/events. Detailed commands and interpretation notes live in `docs/audio-comparison.md`.

## Project structure
* /app/ — Xcode project & macOS app code (AppKit/Swift)
* /core/ — playback engine, DSP (C/C++ or Swift)
* /tests/ — unit & golden tests
* /docs/ — design notes, format notes, contributor guide
* /assets/ — sample modules, themes
* /tools/ — scripts, build helpers

## Contributing
We welcome help. Please read `AGENTS.md` for the project’s required automation & contribution rules — it also describes the expectations for agentic contributors.

High-level rules:

* Small PRs (target ≤ 500 lines) that implement a single goal.
* All code changes must include tests (unit, integration or golden).
* Follow the coding conventions in AGENTS.md.
* When in doubt, open an issue and reference the related milestone.

## Roadmap (first milestones)
Current state summary:
1. AppKit tracker UI, module open/load flow, and tracker-style pattern display are in place.
2. Static highlight row behavior, keyboard navigation, and stable tracker viewport behavior are implemented.
3. First-pass XM playback exists through `AVAudioPlayerNode` / `AVAudioUnitVarispeed`, with several timing, loop, panning, envelope, and volume-column compatibility passes.
4. Audio comparison and playback trace diagnostics exist for local reference work.
5. ADR 004 accepted the deterministic software mixer transition, and the C-backed offline mixer now covers synthetic one-shot, loop, simple linear interpolation for fractional sample steps, volume/panning envelope, frame-scheduling, row/tick timing, minimal synthetic pattern foundations, and tiny bounded `PlaybackSong` adapter renders with diagnostics, including parsed volume-envelope point mapping, explicit XM linear-frequency period/sample-step mapping, adapter-level volume-column set-volume/set-panning and row-level slide support, minimal `Fxx` speed/BPM timing changes, deterministic PCM16 WAV export, a developer-only bounded XM candidate WAV helper with optional diagnostics JSON export, local-only WAV comparison/correlation smoke support, and a blank local findings template for those bounded offline renders.
6. Broader parser integration, full offline module rendering, and MikMod/OpenMPT accuracy work remain upcoming.

For detailed, PR-by-PR milestones, see `docs/roadmap.md`.

## License
MIT — see `LICENSE` for details.

## Contact / provenance
Originally authored in the late 1990s. The modern resurrection is led by Gregory S. Hayes (syncomm), preserving the spirit of the demo scene while building for modern machines and future platforms.
