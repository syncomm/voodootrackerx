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

A deterministic software mixer path has begun behind the existing audio boundary. The C-backed offline mixer can render deterministic synthetic one-shot sample voices, forward and ping-pong loops, volume/panning envelope foundations, frame-scheduled synthetic voices, synthetic tracker row/tick scheduled voices, minimal synthetic pattern playback, and tiny bounded `PlaybackSong` segments through the synthetic adapter with bounded offline render diagnostics. Parsed `PlaybackInstrument.volumeEnvelope` points can now be mapped into that bounded offline adapted render path using constant initial timing, and adapted note triggers now carry a minimal note/sample-derived playback step. This is not full FT2/OpenMPT pitch parity. The path is still offline-only, not full parsed XM song playback, and not the runtime backend yet. The next playback-accuracy steps are a deep handoff checkpoint, then broader parser integration and bounded PCM/WAV comparison foundations against MikMod/OpenMPT.

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
5. ADR 004 accepted the deterministic software mixer transition, and the C-backed offline mixer now covers synthetic one-shot, loop, volume/panning envelope, frame-scheduling, row/tick timing, minimal synthetic pattern foundations, and tiny bounded `PlaybackSong` adapter renders with diagnostics, including parsed volume-envelope point mapping and a minimal note-to-sample-step foundation for those bounded offline renders.
6. Broader parser integration, offline module rendering, and MikMod/OpenMPT accuracy work remain upcoming.

For detailed, PR-by-PR milestones, see `docs/roadmap.md`.

## License
MIT — see `LICENSE` for details.

## Contact / provenance
Originally authored in the late 1990s. The modern resurrection is led by Gregory S. Hayes (syncomm), preserving the spirit of the demo scene while building for modern machines and future platforms.
