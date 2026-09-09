# AGENTS.md — Repository guidance and non-negotiable contracts

## Purpose and authority

This file contains durable repository and agent rules. Keep milestone status and
sequencing out of it.

Active documentation authority is divided as follows:

- `AGENTS.md`: permanent repository, compatibility, and agent rules.
- `docs/agent-current-state.md`: concise present-tense product and runtime
  snapshot.
- `docs/roadmap.md`: the single canonical sequencing roadmap.
- `docs/dev-roadmap.md`: compatibility pointer only; do not add a second roadmap.
- Accepted ADRs and specialized docs: authority for the decision or domain they
  explicitly own.
- Release notes, reports, and git history: historical evidence, not active agent
  chronology.

When these layers appear to disagree, do not silently choose the most convenient
text. Preserve accepted ADR boundaries, verify current behavior where necessary,
and correct the active authority in a focused documentation change.

## Development principles

1. Use one dedicated branch and one behavioral contract per PR.
2. Prefer small, verifiable changes; target no more than 500 changed lines when
   the task itself does not require a larger deletion or consolidation.
3. Add focused tests for every behavior change. Documentation-only changes use
   the documentation and hygiene gates relevant to their scope.
4. Never silently change an on-disk format or module-compatibility boundary. Add
   a design note to `docs/format-changes.md`, compatibility tests, and migration
   tooling when a migration is required.
5. Preserve supported classic MOD/XM read-only compatibility. Do not remove it
   without an explicit documented plan.
6. Never commit credentials, tokens, private keys, private modules, or generated
   local diagnostic artifacts.

## Session and context loading

Begin every development session by reading:

- `docs/agent-current-state.md`
- `docs/dev-session-bootstrap.md`

Read `docs/roadmap.md` when choosing or sequencing work. Load specialized docs
only for the task they own:

- Tracker viewport/UI: `docs/tracker-behavior-spec.md`, `docs/architecture.md`,
  `docs/ui-debugging.md`, and `docs/visual-verification.md`.
- Effects: `docs/xm-effect-support.md`.
- Render/reference comparison: `docs/audio-comparison.md`.
- Runtime trace or diagnostics: `docs/playback-trace.md` and
  `docs/diagnostic-tools.md`.
- Editable instrument/sample ownership: [ADR 012](docs/decisions/012-from-scratch-instrument-sample-composition-model.md),
  [ADR 013](docs/decisions/013-visible-keymap-ownership-projection.md),
  [ADR 014](docs/decisions/014-loaded-xm-editable-copy-planning.md), and the
  relevant editor design note.

Load `docs/task-templates.md` only when it materially helps. Do not load reports
as general current context; use them only when investigating their historical
thread.

## Branch, commit, and PR workflow

- Never make a non-trivial change directly on `main`.
- Start from a clean, synchronized `main`, then create a concise task branch such
  as `feature/<topic>`, `fix/<topic>`, or `docs/<topic>`.
- Keep unrelated user changes intact. If unrelated changes make the intended
  diff ambiguous, stop and report the state.
- Codex leaves work uncommitted by default. Commit, push, or open a PR only when
  the user explicitly requests it.
- Before opening a PR, run the full local verification suite applicable to its
  scope. For a documentation-only PR, the required documentation/hygiene checks
  are the applicable suite unless the task calls for more.
- Commit messages use imperative present tense and a concise scope, for example
  `core: add xm reader`.
- Never merge your own PR. Request review from the primary maintainer before
  merge.

PR titles use `<scope>: <short description>`. PR descriptions include:

- a one-sentence summary;
- files changed;
- tests added or updated;
- exact local verification steps;
- build, test, and manual-validation checklist items.

When asked to submit or open a PR, and the branch and diff contain only intended
work:

1. Review `git status --short --branch` and the complete diff.
2. Stage only intended files.
3. Commit with an imperative scoped message.
4. Push the branch to `origin`.
5. Write the PR body to a file under `/tmp` and use `gh pr create --body-file`.
6. Confirm URL, base, head, title, and open state with `gh pr view`.

Do not ask for redundant confirmation in that clean, explicitly requested flow.
Do not merge the PR.

## Canonical Xcode build and provenance

Run normal Xcode work from the repository root and use the shared repo-root
Derived Data directory:

```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The canonical maintainer Debug executable is:

```text
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

- Use the same `-derivedDataPath build` for normal Xcode test actions.
- Do not create task-specific build directories inside the repository and do
  not expand `.gitignore` to accommodate them. Use `/tmp` or an external scratch
  location only when a genuinely isolated build is required.
- Treat stale-build provenance as a first-class failure mode. Before evaluating
  app behavior or screenshots, rebuild the intended branch/diff and confirm the
  process being launched is the canonical product above.
- Use the canonical executable directly for maintainer smoke runs. If a
  LaunchServices run is required, use the same Debug app, set environment with
  `launchctl setenv` before `open`, then quit the app and clear every override
  with `launchctl unsetenv`.
- Do not invent alternate launch paths before ruling out a stale or wrong build.

## Protected architecture and compatibility boundaries

### Parser and loaded documents

- Keep parsing isolated from UI, playback, and editable-document mutation.
- Loaded MOD/XM modules remain read-only. Audition and export availability do
  not grant mutation rights or source-path ownership.
- Changes to parser behavior require focused fixtures and compatibility tests.
- Use only project-generated, redistribution-safe fixtures in git.

### Runtime and rendering

- Keep the macOS app in Swift + AppKit with modular, testable UI components.
  Performance/DSP code may use C or C++ behind a narrow Swift boundary; do not
  embed core audio logic in view controllers.
- Runtime playback authority is the CoreAudio DefaultOutput Audio Unit host
  driving the C mixer render core.
- `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` are
  aliases for that path. The retired `av_audio` value may report a fallback but
  must not restore an AVAudio runtime backend.
- The Swift playback/adapter layer plans events; the C mixer owns the runtime and
  bounded-offline render core. Offline render/export is the deterministic audio
  comparison path; runtime smoke checks validate host delivery.
- Keep effect semantics, C-mixer DSP, parser behavior, runtime-host work, and
  real-time callback-safety work in separately scoped PRs unless an approved
  design explicitly joins them.

### Editable documents and Undo

- Route every editable-content mutation through
  `EditableDocumentEditCoordinator.applyEdit`.
- One user action creates at most one labeled Undo edit. Cancelled, invalid,
  stale, read-only, playing, conflicting, same-target, and no-op paths create no
  mutation, revision, or history.
- Keep source URLs and loaded-source ownership out of editable value snapshots.
- Save and source replacement must never be inferred from Export or Make
  Editable Copy behavior.

### Canonical sample and keymap semantics

- When instrument routing is present, the document owns one exact 96-entry XM
  keymap: C-0 is index `0`, B-7 is index `95`, and entries retain exact sample
  identity. An absent map is honest routing absence, not an implicit S01 map.
- Preserve stable S01...S16 identities, including canonical empty identities and
  sparse routes. Never compact, fabricate, or silently redirect a missing mapped
  sample to S01 or to the first playable sample.
- Selected sample is editing focus only. Tracker entry/audition, Instrument
  Editor audition, song playback, and product audio export resolve instrument +
  note through the keymap. Sample Editor audition alone resolves the represented
  selected sample directly.
- Keymap assignment is explicit document mutation through the existing edit
  path. Visible-range projection, selection, and pressed-note UI are not a second
  map or write path.
- Only the established neutral first-S01 population may initialize an absent map
  to all S01. Later population, replacement, clearing, and duplication preserve
  the exact existing map; Move and Swap remap it atomically with sample identity.

### Loaded-XM editable-copy planning

- [ADR 014](docs/decisions/014-loaded-xm-editable-copy-planning.md) owns the
  planner and its `exact`, Profile-v1 `normalized`, and
  `unavailable` outcomes.
- Exact and approved normalized results create untitled value-owned editable
  documents; unavailable results remain actionable refusals. The loaded source
  stays read-only and untouched.
- Profile v1 may normalize only its approved inert zero-payload sample-slot
  metadata. Never silently convert Amiga frequency mode to Linear or broaden the
  profile without a new approved compatibility decision and explicit UX.

### Sample import and preview

- Preserve the shared sample-import validation, decode, normalization, and
  stale-result revalidation path. Imported PCM becomes document-owned canonical
  mono 16-bit data through one edit; source paths, metadata, and unsupported loop
  state are not retained.
- Do not add a parallel format-specific mutation path or weaken container,
  bounds, destination, document-identity, revision, selection, occupancy, or
  transport checks.
- Persistent editor preview is isolated from song transport and runtime playback.
  Reuse its existing resolver, generation/cancellation, and audio stream rather
  than creating a second audition engine. Preview never mutates the document or
  creates Undo history.

### Song/order and tracker viewport

- For stopped editable documents, `BlankTrackerDocument.currentPosition` and
  `currentPatternIndex` are the canonical song/order navigation authority. Main
  POS and Song / Order controls must converge on it; view-only pattern browsing
  must not silently assign an order slot.
- Playback follow is transient. Normal Play follows the selected order; Play
  Current Pattern follows the viewed pattern without reassigning it.
- The tracker highlight row remains static while pattern rows scroll behind it.
  Gutter and pattern body must share one slot model and, wherever possible, one
  rendered geometry path.
- Tracker viewport changes must verify anchor row, gutter/body alignment,
  top/bottom wraparound, and absence of early phantom rows. If model tests pass
  but the UI is wrong, inspect actual rendered geometry immediately.

## UI debugging and manual verification

- Reproduce visual issues through the canonical local build/run path and inspect
  screenshots early.
- Compare expected and actual draw positions before adding offsets.
- Prefer architectural simplification over accumulating correction constants.
- Automate the same before/after UI scenario when practical.
- Create a checkpoint commit or tag before risky multi-step viewport refactors.
- Never commit screenshots, logs, local fixture modules, or temporary debugging
  output.

## Private corpus and artifact hygiene

- Keep private modules, local corpus label maps, and artifacts derived from them
  outside the repository.
- Never hardcode a maintainer-local corpus-map path or default. Accept an explicit
  local input and keep the map itself untracked.
- Do not publish private filenames, module identities, corpus counts, local
  absolute paths, or machine-specific notes. Use stable anonymized labels when a
  public-safe example is necessary.
- Put WAVs, traces, captures, JSON, generated Markdown, screenshots, logs,
  benchmarks, and private reports under `/tmp` or another ignored external path.
- Add public reports under `docs/reports/` only when explicitly requested and
  reviewed for redistribution and privacy.
- Run `scripts/scan-tracked-private-leaks.sh` before handoff for diagnostic,
  corpus, release, or broad documentation work.

## Documentation, automation, and large changes

- Update `docs/roadmap.md` only when milestone scope, order, or verification
  expectations change. Do not append investigation chronology to active docs.
- Put major architectural decisions under `docs/decisions/`; if a later decision
  changes one, add a superseding note rather than rewriting accepted history.
- Public functions require doc comments. Complex logic requires concise inline
  rationale.
- Scripts under `scripts/` must be idempotent. Extend documented diagnostic
  tooling instead of adding untracked one-off repository scripts.
- Architectural or large-scale changes require prior discussion, a proposal
  issue, a concise design note, and a minimal proof-of-concept branch. Use a PR
  title of `proposal: <short title>`.
- CI for build-related PRs runs on `macos-latest` and must pass the applicable
  build, tests, and `scripts/check-files.sh`. Do not merge failed CI; record
  non-trivial failures as issues.

## Emergency and regression safety

- If a change introduces a breaking regression, restore the last known-good
  behavior first, revert the PR when appropriate, and open an `incident`-labeled
  issue for a material failure.
- Before tracker UI work, identify the last known-good commit or PR for that
  area. Never leave viewport behavior regressed while polishing unrelated UI.
- Do not disable automation except as a temporary, documented incident response.

## Maintainer

Primary maintainer: Gregory Hayes (`syncomm`). Request maintainer review before
merge.
