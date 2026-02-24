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

---

## Large Change Protocol

For architectural or large-scale changes:

1. Open an issue labeled `proposal`.
2. Include design notes in `/docs/`.
3. Create a minimal Proof-of-Concept branch.
4. Open PR titled: `proposal: <short title>`.

No large refactors without prior discussion.

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
