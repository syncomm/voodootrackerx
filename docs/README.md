# Documentation Index

Start here when choosing which docs to load. The repo intentionally keeps the
normal agent path short; read reports and long diagnostics only when they are
relevant to the task.

## Current State

- `docs/agent-current-state.md` - short backend and workflow snapshot for
  agents and contributors.
- `docs/dev-session-bootstrap.md` - minimal session bootstrap, especially for
  tracker UI and local build/run context.

## Backend And Audio

- `docs/xm-effect-support.md` - canonical XM effect support table.
- `docs/audio-comparison.md` - current render/reference comparison workflow.
- `docs/playback-trace.md` - runtime trace and capture diagnostics.
- `docs/diagnostic-tools.md` - diagnostic script inventory and consolidation
  plan.
- `docs/design/parsed-xm-to-c-mixer-adapter.md` - parsed-XM adapter design.
- `docs/decisions/` - architecture decision records.

## Roadmaps

- `docs/roadmap.md` - current milestone sequencing.
- `docs/dev-roadmap.md` - short phase-based roadmap.

## Tracker UI

- `docs/tracker-behavior-spec.md` - tracker viewport/editor behavior rules.
- `docs/ui-debugging.md` - UI debugging workflow.
- `docs/visual-verification.md` - visual verification requirements.
- `docs/architecture.md` - application architecture notes.

## Testing

- `docs/testing.md` - fixture and test guidance.
- `docs/design/synthetic-xm-reference-fixture-pack.md` - plan for future
  public-safe XM reference fixtures.
- `docs/templates/local-audio-comparison-findings.md` - blank local findings
  template.

## Reports And History

- `docs/reports/` - public-safe committed reports and archived history.
- `docs/reports/audio-comparison-history.md` - older audio comparison history.
- `docs/project-checkpoint.md` - archived early-development snapshot; do not
  use as current state.

Do not put private module names, local absolute paths, or private/local
artifacts in committed docs. Keep generated reports under `/tmp` unless a
maintainer explicitly asks for a public-safe committed report.
