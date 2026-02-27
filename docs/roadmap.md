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
