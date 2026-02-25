# Testing Guide

Practical testing notes for parser/core work and snapshot-based regression checks.

## Fixture Rules

Fixtures live in `tests/fixtures/`.

Rules:
- Use synthetic, tiny fixtures generated for tests.
- Do not add copyrighted module music.
- Keep fixtures minimal and deterministic (header-only when possible).
- Update `tests/fixtures/README.md` if provenance/generation guidance changes.

## Run Core Tests

```bash
swift test --filter ModuleCoreTests
```

## Golden Snapshot Tests

Golden snapshot checks are part of `ModuleCoreTests`.
They compare parser output against stable JSON snapshots in `tests/golden/`.

Run them with:

```bash
swift test --filter ModuleCoreTests
```

## Regenerate Golden Snapshots (Intentional Behavior Changes Only)

When parser behavior changes intentionally, regenerate snapshots and review the diff:

```bash
./scripts/run-golden.sh
```

Then:
- Inspect changes under `tests/golden/`
- Update tests/docs as needed
- Explain the behavior change in the PR description
