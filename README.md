<img src="./assets/logo/vtx-logo.png" alt="VoodooTracker X" width="800" />

**Voodoo Tracker X: A modern resurrection of the classic 1990s FastTracker-style demo scene tracker.**

_VoodooTracker X_ is a modern macOS re-imagining of the classic scene trackers that inspired a generation of chip-tune and demo-scene musicians. Rebuilt from the ground up with modern tooling and macOS native UI in mind, the goal is to preserve the keyboard-first editing feel, pattern-based workflow, and compatibility with classic module formats — while giving the app a stable, testable, and extendable foundation for a future Pro release and iOS ports.

---

## Download

Tagged releases are published on the
[GitHub Releases](https://github.com/syncomm/voodootrackerx/releases) page.
Tagged releases include a versioned downloadable macOS DMG, such as
`VoodooTrackerX-v0.2.0-alpha.4.dmg`.

The first public builds are early alpha/demo builds, not 1.0 releases. The
release workflow builds a macOS 26+ universal app for Apple silicon and Intel
Macs (`arm64` + `x86_64`) and publishes a Developer ID signed, notarized, and
stapled DMG for tagged releases.

## For Build Beyond Attendees

VoodooTracker X is a real tracker project in early alpha form. Download the
latest release DMG from GitHub Releases or build from source, then try it with
public XM/MOD tracker modules. Expect an alpha-quality app that can open,
display, and play supported modules. The current from-scratch workflow can
create instruments, generate or import samples, assign multisample note ranges,
compose patterns and orders, export XM, reopen the result, and render WAV/M4A
audio. Supported loaded XM modules can be converted into an explicit untitled
in-memory editable copy. Loaded source modules remain read-only.

## Try It With Tracker Modules

Good public places to look for tracker modules:

- [Modland](https://www.exotica.org.uk/wiki/Modland) - large searchable module
  archive with FastTracker/ProTracker-era formats.
- [The Mod Archive](https://modarchive.org/) - long-running community archive
  with searchable XM, MOD, and other tracker formats.
- [The Hornet Archive](https://www.hornet.org/music/) - historical demoscene
  music archive with song, sample, program, disk, and contest areas.
- [Amiga Music Preservation / AMP](https://amp.dascene.net/) - Amiga module
  archive and composer database with classic scene context.
- [Scene.org music archive](https://files.scene.org/browse/music/) - broader
  demoscene music archive with tracker releases and related collections.
- [Aminet mods](https://aminet.net/tree?path=mods) - Amiga software archive
  with many module-format directories, including XM and MOD areas.
- [Mirsoft / World of Game MODs](http://www.mirsoft.info/gamemods.php) -
  game-music module archive; useful for historical game tracker music.
- [Pouet](https://www.pouet.net/) - demoscene production/community archive;
  useful for discovering productions and scene context, not just raw module
  downloads.

Only download and use modules you have rights to use. For current VoodooTracker
X testing, prefer `.xm` and `.mod` files before trying broader tracker formats.
Some archives include formats VoodooTracker X does not currently support.

## Current Status

VoodooTracker X is under active development and should not be treated as
production-ready.

The released `v0.2.0-alpha.5` is the Rendered Audio Export Alpha. It
adds app-level whole-song 48 kHz Float32 WAV export with the VTX render profile,
a 3-second tail, auto-headroom, weighted progress, cancellation, and performance
diagnostics, plus AAC-encoded M4A export for convenient sharing. Export is
non-mutating and writes only to a user-selected destination. WAV remains the
preferred high-quality and export-diagnostic format; M4A is the sharing format.
Loaded modules remain read-only, Save and Save As remain disabled, Export XM
remains scoped to the current editable subset, and advanced audio export
options remain future work.

`v0.3.0-alpha.1`, the From-Scratch Composition Alpha, is tagged and released.
It supports the public File New-to-export workflow: create instruments, generate
or import samples, assign note ranges, compose patterns and orders, Export XM,
reopen the result, and render WAV/M4A audio.

The current unreleased Sample Lifecycle Alpha implementation is complete and
release-gated on `main`. Represented samples and canonical empty S01...S16
destinations share one sparse slot model across the editors and XM persistence.
SINE or LOAD can populate the exact selected canonical empty destination; Clear
removes a represented sample in place; Duplicate appends an independent copy;
and `Edit > Move Sample…` / `Edit > Swap Sample…` preserve sample identity,
all 96 keymap references, selection, and unavailable routes through one
transactional Undo/Redo path. Supported sparse exports reopen and can become an
editable copy without compacting identities. Graphical keymap redesign,
destructive waveform editing, Rename Sample, and Move Up/Down convenience
commands remain deferred.

What works today:

- Editable blank document startup, `File > New`, and `File > Open...` for
  supported tracker modules.
- Read-only open/load flow for XM/MOD-style modules.
- Runtime playback through the CoreAudio-hosted C mixer backend.
- Loaded-module TIME display after adapter-plan readiness.
- Transport Play/Stop, Loop at Play start for the selected/current pattern, and
  `Transport > Play Current Pattern` for focused pattern audition.
- Song / Order editor floating utility window with order-list navigation and a
  paginated Pattern Bank.
- `Window > Instrument Editor` opens the fixed v1-mockup editor with selectable
  represented instrument/sample rows, stopped-editable metadata controls, read-only
  envelope displays, a committed-ownership strip aligned to the same visible
  36-note range and geometry as its movable audition piano, isolated
  computer/on-screen keyboard audition, and a stopped-editable `MAP RANGE…`
  sheet for the selected represented sample. The full 96-note document map
  remains canonical; loaded modules show its visible projection with mapping
  controls disabled.
- `Window > Sample Editor` opens a fixed HTML-mockup-aligned window
  with a compact instrument popup bound to the same canonical instrument/sample
  selection. Instrument changes are non-mutating/no-undo, and the selected row,
  exact identity/metadata, efficient waveform overview, and display-only loop
  region stay coherent for loaded and editable documents. Unnamed represented
  samples are distinct from absent samples; FORMAT reports represented bit depth
  and mono without claiming a source rate. In a stopped editable document, SINE
  fills the exact selected canonical empty S01...S16 with original deterministic
  16-bit mono looped PCM through one undoable action. Only neutral empty S01
  initializes the all-S01 keymap. LOAD imports one WAV/WAVE, AIFF/AIF, AIFC, or
  native FLAC into that exact empty destination or the occupied-sample flow
  described above. Native FLAC is limited to mono/stereo 16-bit and 24-bit
  sources; 8-bit and untested depths, Ogg-FLAC, and malformed or mismatched
  containers are rejected. Mono skips channel choice; stereo offers Mix to
  Mono, Left, or Right. Decode and canonical normalization run in the
  background, then one labeled edit installs document-owned mono 16-bit PCM. LOAD remains disabled for loaded
  modules, playback, invalid destinations, and active imports.
  AUDITION toggles the selected sample directly at C-4 through the persistent
  preview stream, preserving sample planning without keymap lookup or mutation.
  CLEAR removes the represented selection in place with confirmation and exact
  Undo/Redo. Duplicate, Move, and Swap are available from Edit for the represented
  Sample Editor selection and preserve sparse identity and keymap meaning.
- The audio import facade dispatches validated WAV, AIFF, AIFC, and native
  FLAC containers to bounded decoders; every format shares one normalized,
  value-owned candidate and commit path. FLAC tags, pictures, cues, seek
  tables, application blocks, ReplayGain, embedded names, and loops are
  ignored. Direct waveform/PCM editing, drag/drop, and global sample import
  remain future work.
- Pattern Bank single-click viewing/navigation and double-click assignment for
  editable documents.
- Pattern Ops `NEW`, `DUP`, and `CLEAR` for stopped editable documents.
- Order Ops `INSERT`, `DELETE`, `DUP`, `MOVE UP`, `MOVE DOWN`, and `PTN -/+`
  for stopped editable documents.
- `File > Make Editable Copy` for stopped supported loaded read-only XM
  modules. The copy is untitled/in-memory and does not claim the source path;
  Amiga-frequency-table XM is refused because the editable subset is Linear.
- `File > Export XM...` for stopped editable documents, covering the current
  VTX editable subset and supported existing palette/sample payloads.
- `File > Export Audio > WAV...` for stopped loaded modules, editable
  documents, and editable copies. Audio export is non-mutating, writes only to
  a user-selected destination, and uses whole-song 48 kHz 32-bit Float WAV with
  the VTX product render profile and export-boundary auto-headroom. Its progress
  sheet supports safe cancellation and continuous weighted progress after
  indeterminate preparation.
- `File > Export Audio > M4A...` for the same stopped renderable documents.
  It reuses the WAV product render plan and auto-headroom-scaled Float32 render,
  then encodes AAC at a fixed 192 kbps into a user-selected `.m4a` file. It is
  likewise non-mutating and cancellable.
- Editable copies created with `Edit > Clear Song Data` can play entered notes
  through the existing CoreAudio C mixer path when the copied palette has
  playable sample payloads. During editable current-pattern Loop playback,
  later grid edits refresh the adapter plan and become audible on a later safe
  loop pass.
- Tracker grid display with static highlight row behavior and keyboard
  navigation.
- Note entry and audition foundations for the tracker editor.
- Selected instrument/sample preview foundations for loaded modules.
- Public generated fixture support for parser/editor test coverage.
- Focused parser tests, golden snapshots, and redistribution-safe fixtures.

What is still future work:

- Save and Save As.
- Advanced audio export options, including pattern/order ranges, stems,
  channel exports, PCM16 product export, bitrate/quality controls, and custom
  export settings.
- Full arbitrary-XM round-trip parity.
- Full loaded-module editing.
- Rename Sample, Move Up/Down convenience commands, square/triangle/saw/noise
  generation, drag-to-paint/automatic keymap assignment, editable loop and
  PCM/waveform work, and destructive processing. Loaded modules remain read-only; see
  [ADR 012](docs/decisions/012-from-scratch-instrument-sample-composition-model.md).
- XI instrument import/export and broader instrument lifecycle/copy workflows.
- MIDI input and broad UI polish. AUv3 remains a post-v1.0 direction.
- Runtime backend transition; the CoreAudio-hosted C mixer remains the current path.
- Live Loop retargeting during active playback, loop-range editing, arbitrary
  loop ranges, and broader tracker editing workflows.
- Full FastTracker II, OpenMPT, or MikMod parity.

## Known Limitations

- Early release builds are signed and notarized for distribution, but remain
  alpha-quality software.
- Export XM is scoped to VTX editable documents and the current editable subset;
  Save and Save As remain disabled.
- Export Audio supports whole-song 48 kHz 32-bit Float WAV and 192 kbps AAC in
  an M4A container. Both use the VTX product profile, 64-row windowed render,
  3-second tail, and export-boundary auto-headroom without the diagnostic
  bounded-render cap. WAV remains the preferred lossless-ish diagnostic path;
  M4A is intended for convenient sharing. Cancellation removes temporary
  output and does not mutate or claim ownership of the source. PCM16 UI,
  pattern/order ranges, channel/stem export, normalization, diagnostic profiles,
  and user-selectable gain/headroom remain future work.
- Loaded modules remain read-only by default; editable copies are explicit,
  in-memory, and do not overwrite or own the opened source path.
- Editing and audition features are still evolving.
- Not all tracker formats, effects, or edge cases are guaranteed.
- Generated/local artifacts such as DMGs, screenshots, logs, traces, WAV/M4A
  files, and uncommitted comparison inputs are not included in the repository.

## Build/Test Quick Start

For source build and verification details, see
[docs/testing.md](docs/testing.md). To start from the repo root:

```bash
xcodebuild -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj -scheme VoodooTrackerX -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
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

For local render/export timing comparisons, use `./scripts/bench-render.sh`.
Plain `swift run` builds Debug by default and is not comparable to Release
render timing.

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
- [ADR 012](docs/decisions/012-from-scratch-instrument-sample-composition-model.md) - from-scratch instrument, sample, import, mapping, lifecycle, and release contract.
- [v0.3.0-alpha.1 release notes](docs/release-notes/v0.3.0-alpha.1.md) - shipped From-Scratch Composition Alpha scope and limitations.
- [docs/tracker-behavior-spec.md](docs/tracker-behavior-spec.md) - tracker viewport and editor behavior rules.
- [docs/testing.md](docs/testing.md) - local build/test commands, fixture rules, parser smoke tests, and golden snapshot workflow.
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

## License

MIT - see [LICENSE](LICENSE) for details.
