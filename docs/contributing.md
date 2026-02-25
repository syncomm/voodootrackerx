# Contributing Guide

Practical contribution guide for human contributors and autonomous agents.

## Before You Start

- Read `AGENTS.md` (project rules and PR requirements)
- Read `docs/roadmap.md` (current milestone sequence)
- Read `docs/legacy-map.md` (legacy behavior mapping and preservation goals)
- Keep changes small and verifiable (target <= 500 lines changed per PR)

## Local Build & Test Commands

Run from repo root.

### App (macOS AppKit)
```bash
xcodebuild -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj -scheme VoodooTrackerX -configuration Debug -destination 'platform=macOS' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj -scheme VoodooTrackerX -configuration Debug -destination 'platform=macOS' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO test
```

### Core parser tests (SwiftPM)
```bash
swift test --filter ModuleCoreTests
```

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
- `docs/legacy-map.md`: legacy behavior understanding improved or new code areas mapped
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

- Start each task by reading `AGENTS.md`, `docs/roadmap.md`, and `docs/legacy-map.md`.
- Do not merge your own PRs.
- If a change is architectural, add a short decision note under `docs/decisions/`.
