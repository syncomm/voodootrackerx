<img src="./assets/logo/vtx-logo.png" alt="VoodooTracker X" width="800" />

**Voodoo Tracker X: A modern resurrection of the classic 1990s FastTracker-style demo scene tracker.**

_VoodooTracker X_ is a modern macOS re-imagining of the classic scene trackers that inspired a generation of chip-tune and demo-scene musicians. Rebuilt from the ground up with modern tooling and macOS native UI in mind, the goal is to preserve the keyboard-first editing feel, pattern-based workflow, and compatibility with classic module formats — while giving the app a stable, testable, and extendable foundation for a future Pro release and iOS ports.

---

## Download

Tagged releases are published on the
[GitHub Releases](https://github.com/syncomm/voodootrackerx/releases) page.
Tagged releases such as `v0.1.0-alpha.1` include a downloadable macOS DMG named
`VoodooTrackerX-v0.1.0-alpha.1.dmg`.

The first public builds are early alpha/demo builds, not 1.0 releases. The
release workflow builds a macOS 26+ universal app for Apple silicon and Intel
Macs (`arm64` + `x86_64`) and packages it into a plain DMG.

Early DMGs may be unsigned and not notarized. If macOS Gatekeeper blocks the
app, use right-click `Open` in Finder or approve the launch in System Settings
only if you trust the downloaded release.

## For Build Beyond Attendees

VoodooTracker X is a real tracker project in early alpha form. Download the
latest release DMG from GitHub Releases or build from source, then try it with
public XM/MOD tracker modules. Expect a demo-quality app that can open, display,
and play supported modules while editing and export workflows continue to land.

## Try It With Tracker Modules

Good public places to look for tracker modules:

- [Modland](https://www.exotica.org.uk/wiki/Modland) - large searchable module
  archive with FastTracker/ProTracker-era formats.
- [The Mod Archive](https://modarchive.org/) - long-running community archive
  with searchable XM, MOD, and other tracker formats.
- [The Hornet Archive](https://www.hornet.org/music/) - historical demoscene
  music archive with song, sample, program, disk, and contest areas.
- [Pouet](https://www.pouet.net/) - demoscene production/community archive;
  useful for discovering productions and scene context, not just raw module
  downloads.

Only download and use modules you have rights to use. For current VoodooTracker
X testing, prefer `.xm` and `.mod` files before trying broader tracker formats.

## Current Status

VoodooTracker X is under active development and should not be treated as
production-ready.

What works today:

- Blank document startup and `File > Open...` for supported tracker modules.
- Read-only open/load flow for XM/MOD-style modules.
- Runtime playback through the CoreAudio-hosted C mixer backend.
- Tracker grid display with static highlight row behavior and keyboard
  navigation.
- Note entry and audition foundations for the tracker editor.
- Selected instrument/sample preview foundations for loaded modules.
- Public generated fixture support for parser/editor test coverage.
- Focused parser tests, golden snapshots, and redistribution-safe fixtures.

What is still future work:

- Save/export from the app.
- Full loaded-module editing.
- Instrument and sample editors.
- Pattern loop editing and broader tracker editing workflows.
- Full FastTracker II, OpenMPT, or MikMod parity.

## Known Limitations

- Early release DMGs may be unsigned and not notarized, so Gatekeeper may warn.
- Save/export is not available yet.
- Loaded modules remain read-only for editing.
- Editing and audition features are still evolving.
- Not all tracker formats, effects, or edge cases are guaranteed.
- Generated/local artifacts such as DMGs, screenshots, logs, traces, WAVs, and
  uncommitted comparison inputs are not included in the repository.

## Build/Test Quick Start

For source build and verification details, see
[docs/testing.md](docs/testing.md). To start from the repo root:

```bash
open app/VoodooTrackerX/VoodooTrackerX.xcodeproj
./scripts/check-files.sh
```

## Running the App

After building, launch the debug app:

```bash
open build/Build/Products/Debug/VoodooTrackerX.app
```

For XM files, use `File > Open...` and inspect the read-only tracker grid.
Basic navigation uses `Up`/`Down`, `Page Up`/`Page Down`, `Home`/`End`, and
`Left`/`Right`.

By default, runtime playback uses the CoreAudio-hosted C mixer.
`VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio`
explicitly select the same CoreAudio host. `VTX_AUDIO_BACKEND=av_audio` is
retired and falls back to the CoreAudio default with a diagnostic fallback
reason. Unknown values also fall back to the CoreAudio default and are reported
in diagnostics.

## Developer Audio Comparison

Detailed audio comparison guidance lives in
[docs/audio-comparison.md](docs/audio-comparison.md). Developer-only comparison
inputs and generated outputs are not repo fixtures and must not be committed,
uploaded, copied into tests, or required by CI.

XM effect support status is tracked in [docs/xm-effect-support.md](docs/xm-effect-support.md).

Keep generated WAVs, JSON reports, Markdown reports, traces, screenshots, logs,
and filled findings reports under `/tmp` or another ignored local path.

Developer-only render tools do not change runtime backend selection and do not
provide full XM song rendering.

## Documentation Map

- [docs/README.md](docs/README.md) - concise documentation index for humans and agents.
- [docs/agent-current-state.md](docs/agent-current-state.md) - current backend state, comparison defaults, and context-loading guidance.
- [docs/audio-comparison.md](docs/audio-comparison.md) - current local-only candidate/reference WAV comparison workflow.
- [docs/xm-effect-support.md](docs/xm-effect-support.md) - public XM effect support matrix for the runtime/offline C mixer adapter path.
- [docs/diagnostic-tools.md](docs/diagnostic-tools.md) - diagnostic script inventory and consolidation plan.
- [docs/roadmap.md](docs/roadmap.md) - current milestone sequencing.
- [docs/dev-roadmap.md](docs/dev-roadmap.md) - short phase-based roadmap.
- [docs/playback-trace.md](docs/playback-trace.md) - runtime trace and capture diagnostics.
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
