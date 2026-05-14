# VoodooTracker X Roadmap (PR-by-PR)

VoodooTracker X exists to resurrect the feel of the 1990s demo scene tracker workflow while making it approachable for a new generation of musicians.

Long-term goals:
- Restore core tracker functionality and classic workflow speed
- Recreate the look/feel nostalgia (keyboard-first pattern editing, tracker grid, visual vibe)
- Preserve MOD/XM compatibility
- Add modern enhancements after parity (UX polish, reliability, export/workflow improvements)

## Milestone 0: Foundation / CI

### PR 0.1 — Repo hygiene + basic checks
- Scope: `.gitignore`, license, file checks, basic CI wiring
- Verification: `scripts/check-files.sh`, CI green on `macos-latest`

### PR 0.2 — Minimal AppKit app skeleton
- Scope: app project, window, unit test target, CLI `xcodebuild` commands
- Verification: `xcodebuild build`, `xcodebuild test`, CI green
Status: done (including launch-window reliability fixes and standard `File` menu window actions).

### PR 0.3 — Core parser harness scaffold
- Scope: `ModuleCore`, synthetic fixtures, parser tests, `mc_dump`
- Verification: `swift test --filter ModuleCoreTests`, `swift run mc_dump ...`, CI green
Status: done.

## Milestone 1: Core Parsing (Read-Only Compatibility First)

### PR 1.1 — MOD/XM header metadata (done baseline)
- Scope: deterministic header parsing only (title/name, version, channels, counts)
- Verification: synthetic fixture tests + `mc_dump` output snapshot checks
Status: done (includes golden JSON snapshots and deterministic `mc_dump --json` output).

### PR 1.2 — XM pattern header parsing
- Scope: parse XM pattern headers (length/count/packed sizes), no note decoding yet
- Verification: unit tests with synthetic XM variants + malformed/truncated cases

### PR 1.3 — XM note/event decoding (read-only)
- Scope: decode XM packed/unpacked pattern events into testable structures
- Verification: fixture-based golden tests for decoded rows/channels

### PR 1.4 — XM instrument/sample header parsing
- Scope: instrument headers, sample headers, envelope metadata (read-only)
- Verification: unit tests for instrument/sample counts and header fields, truncation/error cases

### PR 1.5 — MOD pattern/event parsing (read-only)
- Scope: parse MOD pattern data and note/effect fields
- Verification: golden tests for known rows/cells, malformed file tests

### PR 1.6 — Compatibility smoke corpus
- Scope: add redistribution-safe sample corpus + regression harness (MOD/XM)
- Verification: parser smoke suite in CI, checksum/golden metadata assertions

## Milestone 2: Audio Bring-Up (Reference Tones to Module Playback)

Current stabilization note:
- First audible XM playback currently uses `AVAudioPlayerNode` plus `AVAudioUnitVarispeed` as a safe first-pass backend for sample triggering, Play/Stop behavior, and tracker follow integration.
- This is not the final tracker-accurate mixer architecture; current playback is first-pass XM-compatible rather than FT2-period-accurate or MikMod/OpenMPT accurate.
- Timing, pitch, panning/stereo placement, sample loops including ping-pong loops, instrument volume envelopes/fadeout, volume-column behavior, debug seeking, and playback trace export have all had compatibility passes.
- ADR 004 accepted the transition toward a deterministic pull-based software mixer, and the initial software mixer path now exists behind the playback/audio boundary. It renders silence, synthetic one-shot sample voices, synthetic forward/ping-pong loops, volume/panning envelope foundations, frame-scheduled synthetic voices, synthetic row/tick scheduled voices, minimal synthetic patterns, and tiny bounded `PlaybackSong` adapter segments offline only and is not used for runtime playback.
- See `docs/decisions/002-first-pass-audio-backend.md` for the accepted backend decision and intended future path.
- See `docs/decisions/003-first-pass-playback-accuracy.md` for the current playback accuracy model and known approximations.
- See `docs/decisions/004-software-mixer-transition.md` for the current mixer transition plan.
- See `docs/decisions/005-software-mixer-core-language-boundary.md` for the architecture checkpoint that clarifies the final hot-path mixer boundary before more complex envelope, timing, and effect work.

### PR 2.1 — Audio device/output skeleton (macOS)
- Scope: audio thread/engine scaffolding (no module playback), timing-safe callback path
- Verification: unit tests for ring-buffer/state logic + manual “engine starts/stops” check

### PR 2.2 — Tone generator (sine/square test tone)
- Scope: deterministic tone output for transport/audio sanity
- Verification: unit tests on generated sample buffers + manual audible tone check

### PR 2.3 — Sample playback primitive
- Scope: play one PCM sample buffer (start/stop, rate, mono first)
- Verification: unit tests for stepping/interpolation basics + manual playback check

### PR 2.4 — Module timing/transport (no full effects)
- Scope: row/tick progression from parsed patterns, transport state only
- Verification: deterministic timing tests (songpos/patpos/tick progression)

### PR 2.5 — Basic module playback (minimal MOD/XM subset)
- Scope: note triggering + core timing for simple modules, no full effect support yet
- Verification: integration playback smoke tests + manual playback of tiny fixtures

### PR 2.6 — Effect/envelope compatibility passes
- Scope: iterate effect support and XM envelopes toward legacy behavior
- Verification: regression tests vs expected state transitions/audio metrics, manual comparison runs

## Milestone 2.7: Deterministic Software Mixer Transition

The current runtime playback remains `AVAudioPlayerNode`-based. The software
mixer work should continue in small PRs and prove itself through offline renders
and reference comparison before any runtime backend switch.

### PR 2.7.1 — Software Mixer Skeleton Behind AudioEngine
- Scope: add deterministic mixer types and silence rendering behind the existing audio/playback boundary
- Verification: focused mixer tests plus existing app/parser checks
- Status: done.

### PR 2.7.2 — Offline Render Harness for Software Mixer
- Scope: add a local/offline bounded-frame render path suitable for future PCM/WAV comparison
- Verification: deterministic render tests with synthetic data only; no copyrighted module fixtures
- Status: done.

### PR 2.7.3 — Software Mixer One-Shot Sample Rendering
- Scope: render simple one-shot sample playback with deterministic sample-position accumulators
- Verification: synthetic PCM fixtures for stepping, clamping, and deterministic output
- Status: done.

### PR 2.7.4 — Software Mixer Forward and Ping-Pong Loop Rendering
- Scope: implement forward and ping-pong loop behavior in mixer-owned sample stepping
- Verification: loop edge-case tests for loop start, length, sample offset, and turnaround frames
- Status: done.

### PR 2.7.4a — ADR: Software Mixer Core Language Boundary
- Scope: document that the Swift `SoftwareMixer` remains the deterministic reference/specification harness while the eventual hot-path mixer moves toward a small C-compatible core behind a Swift wrapper
- Verification: documentation review; no runtime behavior changes
- Status: done.

### PR 2.7.4b — C Software Mixer Core Skeleton with Swift Wrapper
- Scope: add a minimal C-compatible mixer core boundary and Swift wrapper that renders deterministic silence only
- Verification: focused C-backed wrapper tests plus existing app/parser checks
- Status: done.

### PR 2.7.4c — Port One-Shot Sample Rendering to C-Backed Mixer
- Scope: port the existing synthetic one-shot sample behavior to the C-backed mixer path while keeping Swift `SoftwareMixer` as the reference/spec harness
- Verification: compare C-backed output against the existing Swift reference expectations with synthetic PCM only
- Status: done.

### PR 2.7.4d — Port Forward and Ping-Pong Loop Rendering to C-Backed Mixer
- Scope: port the existing synthetic forward-loop and ping-pong-loop behavior to the C-backed mixer path
- Verification: compare loop edge-case output against the existing Swift reference expectations with synthetic PCM only
- Status: done.

### PR 2.7.5 — C-Backed Software Mixer Volume / Panning / Envelope Foundations
- Scope: add synthetic frame-based volume envelopes and panning envelope offsets to C-backed offline sample voices
- Verification: deterministic synthetic tests for envelope interpolation, split renders, reset, clear-voices, gain, and pan behavior
- Status: done.

### PR 2.7.6 — C-Backed Software Mixer Timing and Voice Scheduling Foundations
- Scope: introduce deterministic synthetic voice scheduling/timing into the C-backed offline mixer path
- Verification: bounded render tests for synthetic scheduling boundaries, without runtime backend switching or full XM effect integration
- Status: done.

### PR 2.7.7 — Synthetic Tracker Tick and Row Timing Model
- Scope: convert simple synthetic tracker row/tick-style events into frame-scheduled C-backed mixer events
- Verification: deterministic synthetic timing tests only; no runtime backend switching, parser integration, or full XM effects
- Status: done.

### PR 2.7.8 — Minimal Synthetic Pattern Playback Through C-Backed Mixer
- Scope: introduce a tiny synthetic pattern/order representation that schedules notes through the C-backed offline mixer
- Verification: deterministic synthetic pattern tests only; no runtime backend switching, parser integration, or full XM effects
- Status: done.

### PR 2.7.9 — Parsed XM-to-Synthetic Playback Adapter Planning
- Scope: inspect the existing parsed playback model boundary and design a small adapter from parsed XM playback data into the synthetic scheduling layer
- Verification: design/tests for the adapter boundary only; no runtime backend switching or full XM compatibility claims
- Status: done.

### PR 2.7.10 — Minimal PlaybackSong-to-Synthetic Adapter
- Scope: implement the smallest safe Swift-side adapter from `PlaybackSong` into the synthetic pattern scheduling layer using constant initial speed/BPM, bounded orders, and basic note/instrument/sample triggers
- Verification: deterministic bounded offline tests with synthetic or redistribution-safe parsed fixtures only; no runtime backend switching, full XM effects, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10a — Adapter Diagnostics and Bounded Offline Render Helper
- Scope: add richer in-memory source-to-synthetic diagnostics and a bounded offline render helper for tiny adapted `PlaybackSong` segments through the C-backed mixer
- Verification: deterministic helper tests for silence, basic triggers, diagnostics, frame bounds, split/reset determinism, and loop metadata; no runtime backend switching or full XM playback
- Status: done.

### PR 2.7.10b — Parsed Volume Envelope Mapping to C-Backed Mixer
- Scope: convert parsed `PlaybackInstrument.volumeEnvelope` point data into the existing C-backed synthetic volume-envelope representation for bounded offline adapted `PlaybackSong` renders
- Verification: deterministic hand-built `PlaybackSong` tests for disabled/invalid envelopes, mapped constant/ascending/descending envelopes, initial timing conversion, split/reset determinism, diagnostics, and loop metadata regression; no runtime backend switching, pitch accuracy, XM effects, or volume-column semantics
- Status: this PR.

### PR 2.7.11 — Feature-Flagged Runtime Backend Switch
- Scope: add an opt-in runtime mixer backend while keeping the `AVAudioPlayerNode` backend available
- Verification: app playback smoke tests, backend selection tests, and fallback validation

### PR 2.7.12 — Reference Comparison Stabilization Against MikMod/OpenMPT
- Scope: compare bounded local renders against reference renderers and close major audible gaps
- Verification: documented local comparison reports kept out of the repository

### PR 2.7.13 — Remaining FT2/effect quirks after deterministic rendering exists
- Scope: target remaining XM/FT2 effect and compatibility gaps once deterministic rendering is available
- Verification: issue-based regression tests and local reference comparison

## Milestone 3: UI / Tracker Feel (Read-Only to Editing)

### PR 3.1 — Metadata panel + file open (done baseline)
- Scope: `File > Open…` + parsed metadata display + error alerts
- Verification: app build/test + manual open of `.mod`/`.xm`

### PR 3.2 — Pattern grid display (read-only)
- Scope: tracker grid widget/view, row/channel display, cursor visualization
- Verification: snapshot/golden rendering checks where feasible + manual keyboard navigation check

### PR 3.3 — Grid keyboard navigation parity
- Scope: row/channel/item cursor movement, paging, tab behavior
- Verification: UI-level tests if feasible, otherwise integration tests for cursor state transitions

### PR 3.4 — Note entry + row advance (edit disabled save)
- Scope: keyboard note mapping, edit cursor behavior, in-memory edits only
- Verification: deterministic editor-state tests + manual note entry feel validation

### PR 3.5 — Pattern edit operations
- Scope: insert/delete row, copy/cut/paste track/pattern/block basics
- Verification: unit tests on pattern mutations + manual tracker workflow pass

### PR 3.6 — Program/order display + pattern switching
- Scope: song order list and pattern selection/navigation
- Verification: UI integration tests or state-machine tests + manual navigation checks

## Milestone 4: Nostalgia / Look & Feel Restoration

### PR 4.1 — Tracker visual theme baseline
- Scope: typography/colors/grid spacing/channel separators inspired by classic VoodooTracker/FastTracker-era feel
- Verification: manual visual review against legacy references + screenshot snapshots

### PR 4.2 — Keyboard workflow polish
- Scope: shortcut parity tuning, focus handling, repeat behavior, latency polish
- Verification: manual usability checklist + regression tests for key-state transitions

### PR 4.3 — Legacy behavior parity fixes
- Scope: targeted UX/parsing/playback discrepancies found during comparison with legacy behavior
- Verification: issue-based regression tests + manual side-by-side checks

## Milestone 5: Modern Enhancements (After Core Parity)

### PR 5.x — Quality-of-life features (incremental)
Examples:
- Safer file recovery / autosave
- Improved file browser/import UX
- Export helpers / stem renders
- Theme packs / accessibility options
- MIDI input and modern controller support

Verification expectation for each PR:
- Feature-specific tests (unit/integration/golden)
- Manual workflow validation
- No regressions in parser/audio/UI smoke suites

## Definition of “Ready to Expand” (Gate)

Before major new features beyond parity:
- MOD/XM read-only compatibility is stable
- Basic module playback works for a representative smoke corpus
- Grid navigation and editing feel fast and predictable
- CI covers parser + app build/test + core smoke tests consistently
