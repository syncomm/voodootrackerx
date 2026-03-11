# AGENTS.md — Guidance & non-negotiables for autonomous agents (Codex, bots) working on this repo

## Purpose
This document defines the rules and expectations for any automated agent (Codex or similar) and human contributors. It exists so agentic systems can operate safely, predictably, and constructively in small PR increments.

---

## High-level principles (non-negotiable)

1. **Small, verifiable changes.** Prefer small PRs that are easy to review and test. Target ≤ 500 lines changed per PR.
2. **Tests-first mindset.** Any change that affects behavior must include tests (unit, integration, or golden tests).
3. **Never change file formats silently.** Any change to the on-disk file format or module compatibility must be accompanied by:
   - Explicit design note in `/docs/format-changes.md`
   - Compatibility tests and migration tools
4. **Respect the legacy.** The app should remain compatible with classic MOD/XM files (first pass: read-only compatibility). Do not remove legacy support without a documented plan.
5. **No secrets.** Never commit credentials, tokens, or private keys.

---

## Tracker UI Rules

- For tracker viewport work, read:
  - docs/dev-session-bootstrap.md
  - docs/tracker-behavior-spec.md
  - docs/ui-debugging.md
  - docs/visual-verification.md
  - docs/architecture.md
- For visual bugs, do manual GUI verification early.
- If model tests pass but UI is wrong, inspect rendered geometry immediately.
- Use screenshots for tracker UI regressions whenever possible.
- Do not rely only on unit tests for viewport/alignment bugs.
- Gutter and pattern body must share one slot model and one rendered geometry path whenever possible.
- Prefer architectural simplification over adding offset corrections.
- Do not commit debugging artifacts, screenshots, or local copyrighted test modules.
- For tracker viewport changes, verify: anchor row, gutter alignment, wraparound, and no phantom rows.
- Keep tracker UI PRs narrowly scoped and visually verified before commit.
- Use the repo's canonical local build/run workflow before inventing alternate launch methods.
- When permissions allow, reproduce the issue, capture screenshots, and iterate independently before asking for repeated manual checks.
- Create a checkpoint commit or tag before risky UI refactors or multi-step viewport changes.

---

## Branching & PR rules

- Default branch: `main`
- Feature branches: `feature/<short-description>`
- PR titles: `<scope>: <short description>`  
  Example: `core: add xm loader smoke test`

PR descriptions must include:
- One-sentence summary
- List of files changed
- Tests added/updated
- Local verification steps

Suggested labels:
- `pr:ci-needed`
- `pr:testing`
- `pr:docs`

---

## CI & Quality Gates

- CI must run on macOS runners (`macos-latest`) for build-related PRs.
- PRs must pass:
  - Build (if relevant)
  - Tests
  - `scripts/check-files.sh`
- If CI fails, do not merge.
- Non-trivial failures should result in an issue.

---

## Coding Style & Architecture

### App Layer
- Prefer **Swift + AppKit** for initial macOS UI.
- Keep UI components testable and modular.
- Avoid embedding core audio logic directly inside view controllers.

### Core Engine
- C or C++ permitted for DSP/performance.
- Provide a small Swift wrapper layer for interop.
- Avoid unnecessary abstraction in early milestones.

### Formatting
- Swift: `swiftformat` (to be added later)
- C/C++: `clang-format` (to be added later)

### Documentation
- Public functions must include doc comments.
- Complex logic must include inline explanation comments.

### Documentation rules
- Update `docs/roadmap.md` when milestone scope, sequencing, or verification expectations change.
- Update `docs/legacy-map.md` when understanding of legacy behavior improves or new legacy code areas are mapped.
- For major architectural choices, add a short decision note under `docs/decisions/` (ADR-style, lightweight).
- Any architectural change PR must include or update a decision note in `docs/decisions/`.

---

## Commit Style

- Imperative present tense.
  - Good: `core: add xm reader`
  - Bad: `added xm reader`
- Keep commit messages concise but meaningful.
- Include short rationale in body when necessary.

---

## Agent Operational Rules (Codex behavior)

When operating autonomously, an agent MUST:

1. Create a dedicated branch for each task.
2. Run the full local test suite before opening any PR.
3. Keep changes scoped and minimal.
4. Include tests and update docs when necessary.
5. Include a PR checklist with:
   - Build verification
   - Test verification
   - Manual validation steps
6. NEVER merge its own PRs.
7. Read `docs/roadmap.md` and `docs/legacy-map.md` at the start of work (when present) to maintain continuity.
8. Begin all development sessions by loading `docs/dev-session-bootstrap.md`.

---

## Context Loading Guidelines

Future agents should load only the documents needed for the current task.

All development sessions should begin by loading:
- `docs/dev-session-bootstrap.md`

For tracker UI work:
- `docs/dev-session-bootstrap.md`
- `docs/tracker-behavior-spec.md`
- `docs/architecture.md`
- `docs/ui-debugging.md`
- `docs/visual-verification.md`

For general development:
- `docs/dev-roadmap.md`

Load `docs/task-templates.md` only when it helps structure a new task or clarify expected deliverables. Do not load it by default for every session.

Avoid loading unnecessary documentation when it does not help the task, to reduce token usage and preserve focus.

---

## UI Debugging Protocol

When debugging UI alignment issues, always distinguish between:
- data/model correctness
- rendered geometry correctness

If a UI bug persists after model tests pass:
- inspect rendered geometry immediately
- log or compare actual draw Y positions
- do not assume model correctness implies visual correctness

Screenshots are strongly recommended for visual regressions.

When tooling permissions allow it, agents should capture their own screenshots during UI debugging instead of relying only on textual reports.

When debugging tracker UI, prefer manual GUI verification early instead of repeated speculative code changes.

When debugging app behavior, use the project's canonical local build/run path first.

When reproduction can be automated, agents should:
- launch the app themselves
- drive the UI with keyboard or mouse automation when possible
- compare before/after screenshots for the same scenario

Before risky UI iteration, create a checkpoint commit or tag so the session can safely return to the last known-good state.

Acceptable debugging artifacts:
- screenshots
- local fixture files
- temporary logging

Debugging artifacts must not be committed into the repository.

When working on tracker viewport logic, verify these invariants manually:
- gutter rows align with pattern rows
- highlight row remains static
- wrap behavior works at the top and bottom
- no phantom blank rows appear early

---

## Large Change Protocol

For architectural or large-scale changes:

1. Open an issue labeled `proposal`.
2. Include design notes in `/docs/`.
3. Create a minimal Proof-of-Concept branch.
4. Open PR titled: `proposal: <short title>`.

No large refactors without prior discussion.

## Decision Log (Lightweight ADRs)

- Store short architecture decision notes in `docs/decisions/`.
- Keep each note concise (problem, decision, rationale, impact/tradeoffs).
- Use this for major choices such as UI toolkit, audio engine approach, parser/file format strategy, and persistence/compatibility decisions.
- If a later PR changes a prior decision, add a new note that supersedes the old one rather than rewriting history.

---

When modifying the tracker editor or viewport behavior, always follow:

docs/tracker-behavior-spec.md

---

## Automation Hooks

- Scripts in `/scripts/` must be idempotent.
- CI must remain green on `main`.
- Agents should prefer adding tests before modifying production code.

---

## Emergency Policy

If an agent introduces breaking changes:

- Revert the PR.
- Open an `incident` labeled issue.
- Temporarily disable automation if necessary.

---

## Maintainer

Primary maintainer: Gregory Hayes (`syncomm`)

Agents must request review from the primary maintainer before merge.
