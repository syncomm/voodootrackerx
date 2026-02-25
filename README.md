# VoodooTracker X

**Voodoo Tracker X: A modern resurrection of the classic 1990s FastTracker-style demo scene tracker.**

_VoodooTracker X_ is a modern macOS re-imagining of the classic scene trackers that inspired a generation of chip-tune and demo-scene musicians. Rebuilt from the ground up with modern tooling and macOS native UI in mind, the goal is to preserve the keyboard-first editing feel, pattern-based workflow, and compatibility with classic module formats — while giving the app a stable, testable, and extendable foundation for a future Pro release and iOS ports.

---

## Quick links
- Repo: `https://github.com/syncomm/voodootrackerx`
- License: MIT

---

## Goals & scope (first pass)
1. Provide playback and editing compatibility for classic module formats (MOD, XM).
2. Deliver a Mac-native UI that respects the original tracker workflows (keyboard navigation, pattern editing).
3. Ship small, verifiable PRs with automated checks and tests so the project can be iterated by agentic tools and humans alike.
4. Keep the core engine open-source while enabling a future commercial “Pro” edition with additional features.

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
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Core Parser Smoke Tests
```bash
swift test --filter ModuleCoreTests

swift run mc_dump tests/fixtures/minimal.mod
swift run mc_dump tests/fixtures/minimal.xm
swift run mc_dump --json tests/fixtures/minimal.xm

./scripts/run-golden.sh
```

The core parser smoke harness is header-only for now (metadata extraction only; no playback or DSP).
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
1. Scaffolding & CI (macOS build checks)
2. Module loader smoke test (read XM/MOD & checksum sample data)
3. Audio playback harness (play/stop, tempo)
4. Pattern editor skeleton (keyboard navigation)
5. Theme to match the classic tracker look

## License
MIT — see `LICENSE` for details.

## Contact / provenance
Originally authored in the late 1990s. The modern resurrection is led by Gregory S. Hayes (syncomm), preserving the spirit of the demo scene while building for modern machines and future platforms.
