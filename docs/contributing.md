# Contributing Guide

Practical contribution guide for human contributors and autonomous agents.

## Before You Start

- Read `AGENTS.md` (project rules and PR requirements)
- Read `docs/agent-current-state.md` and `docs/dev-session-bootstrap.md`
- Read `docs/roadmap.md` (current milestone sequence)
- Keep changes small and verifiable (target <= 500 lines changed per PR)

## Local Build & Test Commands

Run from repo root.

### App (macOS AppKit)
```bash
xcodebuild -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj -scheme VoodooTrackerX -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj -scheme VoodooTrackerX -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

### Core parser tests (SwiftPM)
```bash
swift test --filter ModuleCoreTests
```

### Render tool tests (SwiftPM)
```bash
swift test --filter VTXRenderBoundedXMTests
```

Run these before changes that touch `vtx_render_bounded_xm`, render/export
policy, CLI argument handling, or render diagnostics JSON.

### Release render benchmark (local timing only)
```bash
./scripts/bench-render.sh tests/reference-xm/generated/basic-instrument-sample.xm
```

Render/export performance comparisons must use Release builds unless the
measurement is explicitly about Debug behavior. Plain `swift run` builds Debug
by default and is not comparable. The benchmark helper runs
`swift run -c release vtx_render_bounded_xm --product-export-profile`, which
expands to the app's shared 48 kHz Float32 WAV, VTX mix, song-end, 3-second
tail, 64-row window, auto-headroom, and long-render settings. Keep generated
WAVs, diagnostics, reports, and timing notes under `/tmp` or another ignored
path.

### Core parser manual dumper (metadata smoke check)
```bash
swift run mc_dump tests/fixtures/minimal.mod
swift run mc_dump tests/fixtures/minimal.xm
```

### Basic repo checks
```bash
./scripts/check-files.sh
```

## Fixtures (Safe / Redistributable Only)

Use only fixtures that are safe to redistribute.

Rules:
- Do not commit copyrighted songs or commercial module files.
- Prefer tiny synthetic fixtures generated in-repo for parser tests.
- Keep fixtures minimal (header-only or smallest bytes needed for the test).
- Add or update `tests/fixtures/README.md` when fixture provenance or generation approach changes.

When adding fixtures:
- Include only bytes needed for the scenario under test.
- Name fixtures descriptively (`minimal`, `truncated`, `bad-signature`, etc.).
- Add a test that proves why the fixture exists.

## Golden Tests (How to Add / Update)

Golden tests should be used for deterministic outputs (parsed metadata, decoded pattern rows, serialized structures, etc.).

How to add:
- Add a fixture in `tests/fixtures/` (safe to redistribute)
- Add a test that compares actual output to expected/golden values
- Keep expected data small and readable in code or a small sidecar file

How to update:
- Update goldens only when behavior changes intentionally
- In the PR description, explain why the golden changed
- Add a note or decision record if the change reflects an architectural/compatibility decision

## Documentation: What to Update and When

Update docs as part of the same PR when relevant:
- `README.md`: user-facing usage, build/test, CLI commands
- `docs/roadmap.md`: milestone scope/order/verification expectations changed
- `docs/decisions/` (ADR-style notes): any major architectural change (UI toolkit, audio engine, file format strategy, persistence/compatibility approach)

## PR Checklist Template (AGENTS.md-aligned)

Copy into the PR description and fill in.

```md
One-sentence summary
<what changed and why in one sentence>

Files changed
- `path/to/file1`
- `path/to/file2`

Tests added/updated
- <unit/integration/golden tests added or updated>

Local verification steps
- `<exact command>`
- `<exact command>`

PR checklist
- [ ] Build verification
- [ ] Test verification
- [ ] Manual validation steps

Manual validation steps
- <step 1>
- <step 2>

Requesting review from primary maintainer: @syncomm
```

## Notes for Agents

- Start each task by reading `AGENTS.md`, `docs/agent-current-state.md`, and
  `docs/dev-session-bootstrap.md`; load `docs/roadmap.md` when milestone context is relevant.
- Do not merge your own PRs.
- If a change is architectural, add a short decision note under `docs/decisions/`.
