<img src="./assets/logo/vtx-logo.png" alt="VoodooTracker X" width="800" />

**Voodoo Tracker X: A modern resurrection of the classic 1990s FastTracker-style demo scene tracker.**

_VoodooTracker X_ is a modern macOS re-imagining of the classic scene trackers that inspired a generation of chip-tune and demo-scene musicians. Rebuilt from the ground up with modern tooling and macOS native UI in mind, the goal is to preserve the keyboard-first editing feel, pattern-based workflow, and compatibility with classic module formats — while giving the app a stable, testable, and extendable foundation for a future Pro release and iOS ports.

---

## Current Status

- Working macOS AppKit prototype with module open/load, tracker-style pattern display, static highlight row behavior, and keyboard navigation.
- MOD/XM parser work is covered by focused unit tests, golden snapshots, and small redistribution-safe fixtures.
- First-pass XM playback exists for development and smoke testing, but it is not yet MikMod/OpenMPT accurate.
- Default runtime playback remains `AVAudioPlayerNode` / `AVAudioUnitVarispeed` based.
- The C-backed mixer path is used for deterministic bounded renders, diagnostics, and local comparison work. An experimental runtime C mixer skeleton is available only when launched with `VTX_AUDIO_BACKEND=c_mixer`.
- The app is under active development and should not be treated as production-ready.

## Build/Test Quick Start

Open the Xcode project:

```bash
open app/VoodooTrackerX/VoodooTrackerX.xcodeproj
```

Build and test from the repo root:

```bash
./scripts/check-files.sh

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

swift test --filter ModuleCoreTests
./scripts/run-golden.sh
```

## Running the App

After building, launch the debug app:

```bash
open build/Build/Products/Debug/VoodooTrackerX.app
```

For XM files, use `File > Open...` and inspect the read-only tracker grid. Basic navigation uses `Up`/`Down`, `Page Up`/`Page Down`, `Home`/`End`, and `Left`/`Right`.

Developers can opt into the experimental runtime C mixer skeleton with `VTX_AUDIO_BACKEND=c_mixer`. Unset or unknown values keep the default AVAudio backend.

## Developer Audio Comparison

Detailed audio comparison guidance lives in [docs/audio-comparison.md](docs/audio-comparison.md). Local/private modules may be used for manual listening, smoke testing, bounded candidate WAV renders, and local reference comparisons, but they are not repo fixtures and must not be committed, uploaded, copied into tests, or required by CI.

Keep generated WAVs, JSON reports, Markdown reports, traces, screenshots, logs, and filled findings reports under `/tmp` or another ignored local path.

Short bounded candidate render example:

```bash
swift run vtx_render_bounded_xm \
  --input /path/to/local-reference-module.xm \
  --output /tmp/vtx-candidate.wav \
  --diagnostics-json /tmp/vtx-candidate-diagnostics.json \
  --order 10 \
  --order-count 1 \
  --rows 16 \
  --sample-rate 44100
```

The helper is developer-only. It does not change the default runtime backend, does not require the experimental runtime flag, and does not provide full XM song rendering.

## Documentation Map

- [docs/audio-comparison.md](docs/audio-comparison.md) - local-only candidate/reference WAV comparison workflow, artifact rules, diagnostics, and interpretation notes.
- [docs/roadmap.md](docs/roadmap.md) - detailed PR-by-PR roadmap and current audio/mixer sequencing.
- [docs/dev-roadmap.md](docs/dev-roadmap.md) - shorter phase-based roadmap and current state snapshot.
- [docs/design/parsed-xm-to-c-mixer-adapter.md](docs/design/parsed-xm-to-c-mixer-adapter.md) - bounded parsed-XM-to-C-mixer adapter design and non-goals.
- [docs/decisions/](docs/decisions) - architecture decision records, including the software mixer transition and C mixer boundary.
- [docs/tracker-behavior-spec.md](docs/tracker-behavior-spec.md) - tracker viewport and editor behavior rules.
- [docs/testing.md](docs/testing.md) - fixture rules, parser smoke tests, and golden snapshot workflow.
- [AGENTS.md](AGENTS.md) - contribution and automation requirements for humans and agents.

## Project Structure

- `app/` - macOS AppKit app and Xcode project.
- `core/ModuleCore/` - core module parsing package.
- `core/MixerCore/` - C-backed mixer core used by offline render paths.
- `tools/` - Swift package command tools, including `mc_dump` and `vtx_render_bounded_xm`.
- `scripts/` - repository checks, golden-test helper, and local audio comparison utilities.
- `tests/` - unit tests, fixtures, and golden snapshots.
- `docs/` - roadmap, design notes, ADRs, testing guidance, and workflow docs.
- `assets/` - public visual assets and placeholders.
- `legacy/` - imported legacy VoodooTracker reference code for behavior study only.

## License

MIT - see [LICENSE](LICENSE) for details.
