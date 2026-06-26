# Diagnostic Tools Inventory

This inventory is a planning document for diagnostic, comparison, coverage, and
helper tooling. It does not move, rename, delete, consolidate, or change any
script or tool behavior.

## Current Inventory Summary

Inventoried files:

- 17 files under `scripts/`.
- 4 Python test helper modules under `tools/`.
- 1 Python fixture-generator test helper under `tools/`.
- 2 SwiftPM command entrypoints under `tools/`.
- 1 active Swift command implementation under tool-owned SwiftPM support
  sources.

The Swift test suite also invokes `scripts/audio-compare.py` from
`tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift`; that test file is
tracked below as a reference, not as a standalone diagnostic tool.

Classification terms:

- Active workflow: documented and expected for current development.
- Active test helper: used to test scripts or tool outputs.
- Diagnostic / local-only: intended for local investigation, usually with
  generated artifacts.
- Hyper-specific investigation artifact: built for a narrow historical
  investigation and still potentially useful.
- Legacy / candidate archive: likely archiveable after references and tests are
  moved or retired.
- Candidate for unified CLI subcommand: should be folded into a future
  diagnostic command surface.
- Unknown / needs follow-up: usage could not be confidently classified.

## Local-Only And Private Artifact Rules

- Keep generated WAVs, JSON, Markdown, traces, logs, screenshots, and filled
  findings reports under `/tmp` or another ignored local path.
- Keep private module files and local corpus label maps outside the repository.
- Do not publish private filenames, local absolute paths, machine-specific
  notes, or generated reports derived from private modules.
- Use stable anonymized labels when a public-safe example is needed.
- Generated reports belong in `docs/reports/` only when the maintainer
  explicitly requests a public-safe committed report.
- Before committing diagnostic/tooling work, run a private-name/local-path scan
  and review staged files.

## Active Inventory

| Path | Classification | Purpose | Known references | Private/local corpus handling | Output under `/tmp`? | Current path? | Recommended future action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `scripts/check-files.sh` | Active workflow; active CI/local helper | Performs the repo's basic required-file hygiene check. | `README.md`, `AGENTS.md`, `docs/agent-current-state.md`, `docs/contributing.md`, `docs/roadmap.md`, design docs. | No private data. | No generated output. | Keep. | Leave as a small stable repo hygiene script. |
| `scripts/run-golden.sh` | Active workflow; golden/test helper | Regenerates parser golden JSON snapshots from redistribution-safe fixtures. | `README.md`, `docs/testing.md`; calls `swift run mc_dump`. | No private data; uses committed fixtures only. | No; intentionally writes `tests/golden/`. | Keep. | Leave separate from diagnostics; only run for intentional parser snapshot changes. |
| `scripts/generate-synthetic-xm-fixtures.py` | Active test helper; fixture generator | Prints or writes the deterministic source manifest and can explicitly write the approved generated `basic-instrument-sample.xm` fixture under `tests/reference-xm/`. | `tests/reference-xm/README.md`, `docs/design/synthetic-xm-reference-fixture-pack.md`, `tools/synthetic_xm_fixture_generator_tests.py`. | No private data; explicitly forbids private modules and private corpus dependencies. | No by default; writes only requested manifest or XM fixture paths when invoked with `--write-manifest` or `--write-xm`; no reference renders. | Keep. | Extend in small reviewed fixture PRs; do not emit reference renders by default. |
| `scripts/audio-compare.py` | Active workflow; diagnostic / local-only; candidate CLI subcommand | Compares reference and candidate WAVs and emits audio metrics, windows, JSON, and Markdown. | `docs/audio-comparison.md`, `docs/testing.md`, ADR 004, archived reports, `tools/audio_compare_tests.py`, Swift render tests. | Handles WAVs that may be derived from private modules; reports must use public-safe labels. | Yes for JSON/Markdown reports and source WAVs unless using temp test dirs. | Keep for now. | Make `audio_compare` a first-class unified CLI subcommand; keep compatibility wrapper until docs/tests migrate. |
| `scripts/local-reference-compare-smoke.py` | Active workflow; diagnostic / local-only; candidate CLI subcommand | Thin smoke wrapper around `audio-compare.py` with default report paths. | `docs/audio-comparison.md`, archived reports, `tools/audio_compare_tests.py`; invokes `scripts/audio-compare.py`. | Handles local candidate/reference WAVs; metadata is printed only and must stay public-safe. | Yes; defaults to `/tmp/vtx-local-reference-comparison`. | Keep for now. | Fold into the future `audio_compare` subcommand as a preset/default mode. |
| `scripts/correlate-audio-comparison.py` | Active workflow; diagnostic / local-only; hyper-specific; candidate CLI subcommand | Correlates `audio-compare.py` worst windows with bounded render diagnostics. | `docs/audio-comparison.md`, archived reports, `tools/audio_compare_tests.py`. | Handles diagnostics from local/private modules; labels and metadata must be anonymized. | Yes. | Keep for now. | Fold into `reference_triage` or `audio_compare correlate`; preserve report schema tests before moving. |
| `scripts/focused-window-voice-timeline.py` | Active workflow; diagnostic / local-only; hyper-specific; candidate CLI subcommand | Summarizes bounded-render voice timelines for explicit time windows. | `docs/audio-comparison.md`, archived reports, `tools/audio_compare_tests.py`. | Reads local diagnostics JSON; output should not expose input paths. | Yes. | Keep for now. | Fold into `reference_triage focused-window`; keep a wrapper until docs migrate. |
| `scripts/analyze-audio-discontinuities.py` | Diagnostic / local-only; hyper-specific; candidate archive; candidate CLI subcommand | Finds adjacent-sample jump/click evidence in a WAV and optionally correlates to diagnostics. | Archived audio history, `tools/audio_compare_tests.py`. | Handles local WAVs and optional diagnostics derived from private modules. | Yes. | Keep for now. | Archive or fold into `audio_compare discontinuities` after checking no active prompt/doc workflow depends on the standalone script. |
| `scripts/stem-scaling-diagnostics.py` | Diagnostic / local-only; hyper-specific; candidate CLI subcommand | Sums local reference stems, optionally compares the sum against a full render, and can rank matched reference/candidate stem residuals in explicit focus windows. | Archived audio history, `tools/audio_compare_tests.py`; imports `audio-compare.py`. | Handles local stem WAVs that may be derived from private modules. | Yes. | Keep for now. | Fold into `audio_compare stems` after test coverage is moved to the unified CLI. |
| `scripts/summarize-reference-render-triage.py` | Diagnostic / local-only; hyper-specific; candidate archive; candidate CLI subcommand | Summarizes anonymized triage manifests that point at local comparison JSONs. | Archived audio history, `tools/audio_compare_tests.py`. | Manifest may describe local/private comparison outputs; committed summaries must stay anonymized. | Yes for manifests and generated summaries. | Keep for now. | Fold into `reference_triage summarize` or archive if the manifest workflow is no longer used. |
| `scripts/summarize-xm-effect-coverage.py` | Active workflow; diagnostic / local-only; candidate CLI subcommand | Summarizes XM effect coverage from bounded offline diagnostics or runtime traces; recommendation wording is freeze-aligned with `docs/xm-effect-support.md`. | `docs/audio-comparison.md`, `docs/playback-trace.md`, archived reports, `BoundedXMRenderTool.swift` help text, `tools/audio_compare_tests.py`. | Reads diagnostics/traces that may come from private modules; output should use redacted labels. | Yes. | Keep for now. | Fold into `effect_coverage`; preserve backend-freeze recommendation wording and the compatibility path for existing docs. |
| `scripts/summarize-xm-residual-effect-scan.py` | Active local planning helper; diagnostic / local-only; candidate CLI subcommand | Scans a private XM corpus label map for residual effect-memory and volume-column gaps; recommendation wording is freeze-aligned with `docs/xm-effect-support.md`. | `tools/xm_residual_effect_scan_tests.py`; archived reports. | Yes; reads a local label map with private paths and emits public-safe labels/counts. | Yes; default label map and outputs are under `/tmp`. | Keep for now. | Fold into `residual_scan`; keep strict redaction tests and freeze-aligned recommendation wording before any move. |
| `scripts/focused-xm-channel-diagnostics.py` | Diagnostic / local-only; hyper-specific; candidate archive; candidate CLI subcommand | Builds a focused row/channel report from `mc_dump` JSON and bounded render diagnostics. | Archived audio history, `tools/audio_compare_tests.py`; mentions `mc_dump` and `vtx_render_bounded_xm`. | Reads local artifacts, not module files; report should not echo input paths. | Yes. | Keep for now. | Fold into `reference_triage focused-channel` or archive after checking active workflow references. |
| `scripts/summarize-runtime-c-mixer-trace.py` | Active workflow; diagnostic / local-only; candidate CLI subcommand | Summarizes runtime C mixer JSONL traces, callback health, output-copy, and route diagnostics. | `docs/playback-trace.md`, archived reports, `tools/audio_compare_tests.py`. | Reads runtime traces from local/private smoke runs; listening notes must stay local. | Yes. | Keep for now. | Fold into `runtime_trace summarize`; preserve deterministic summary tests. |
| `scripts/correlate-runtime-offline-window.py` | Active workflow; diagnostic / local-only; hyper-specific; candidate CLI subcommand | Correlates runtime/offline mismatch windows across WAVs, runtime traces, and optional offline diagnostics. | `docs/playback-trace.md`, archived reports, `tools/audio_compare_tests.py`. | Handles local runtime captures, offline WAVs, traces, and diagnostics. | Yes. | Keep for now. | Fold into `runtime_trace correlate-window`; keep current script until docs and tests migrate. |
| `scripts/run-local-corpus-runtime-metrics.py` | Active local planning helper; diagnostic / local-only; candidate CLI subcommand | Runs disabled load/play timing and runtime mixer metrics diagnostics for selected anonymized private corpus labels. | `docs/testing.md`, `tools/local_corpus_runtime_metrics_tests.py`. | Reads a maintainer-supplied local label map and redacts captured stdout/stderr; output filenames and summaries use `xm-corpus-###` labels only. | Yes; defaults to a timestamped `/tmp` directory and refuses repository output by default. | Keep. | Fold into `runtime_trace corpus-metrics` or a future corpus diagnostics subcommand; preserve redaction and output-confinement tests. |
| `scripts/update-private-xm-corpus-label-map.py` | Active local planning helper; diagnostic / local-only; candidate CLI subcommand | Updates a private XM corpus label map and writes a redacted summary. | Archived reports, `tools/private_xm_corpus_label_map_tests.py`. | Yes; source modules and full label map stay local, defaulting to `/tmp`. | Yes for map and summaries. | Keep for now. | Fold into `corpus_map update`; preserve redaction behavior and tests. |
| `tools/mc_dump/main.c` | Active workflow; SwiftPM C CLI entrypoint | Dumps parsed MOD/XM metadata and optional XM pattern events for tests and diagnostics. | `Package.swift`, `README.md`, `docs/testing.md`, `docs/contributing.md`, ADR 001, `scripts/run-golden.sh`, focused diagnostics. | Can read private modules if manually invoked; private JSON dumps stay local. | Yes for private/local dumps; golden outputs are intentional test artifacts. | Keep. | Leave as a parser CLI unless a broader tool package layout is introduced. |
| `tools/vtx_render_bounded_xm/main.swift` | Active workflow; SwiftPM CLI entrypoint | Tiny executable entrypoint for the bounded XM render/export tool. | `Package.swift`, `README.md`, `docs/agent-current-state.md`, `docs/audio-comparison.md`, `docs/playback-trace.md`, render tests. | Reads local/private XM modules; WAVs and diagnostics must stay local unless explicitly public-safe. | Yes for local renders and diagnostics. | Keep. | Preserve as the stable CLI entrypoint even if the implementation moves. |
| `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift` | Active diagnostic/export tool implementation; M4 source-location refactor complete | Implements the developer-only bounded XM render/export CLI used by `tools/vtx_render_bounded_xm/main.swift`. | `tools/vtx_render_bounded_xm/main.swift`, `Package.swift`, render tests, workflow docs via the CLI name. | Reads local/private XM modules and writes local WAV/diagnostics/coverage artifacts. | Yes for local outputs. | Keep. | Leave behavior unchanged; keep this under tool-owned support sources unless a later tooling module/package design supersedes it. |
| `tools/audio_compare_tests.py` | Active test helper | Synthetic unit/CLI tests for audio comparison, reference triage, runtime trace, effect coverage, focused diagnostics, and related scripts. | Direct test target run with `python3 -m unittest tools/audio_compare_tests.py`. | Uses synthetic data and temporary directories. | Test temp dirs only. | Keep. | Split by future CLI subcommand once the script surface is consolidated. |
| `tools/xm_residual_effect_scan_tests.py` | Active test helper | Unit tests for residual effect scan classification and recommendation logic. | Required when residual/corpus tooling is referenced or touched. | Uses synthetic module structures. | No persistent output. | Keep. | Move beside future `residual_scan` CLI package tests. |
| `tools/private_xm_corpus_label_map_tests.py` | Active test helper | Tests private corpus label-map update and redacted summary behavior with synthetic XM bytes. | Required when corpus label-map tooling docs or code are touched. | Uses synthetic fixtures in temporary directories and asserts paths/names are redacted. | Test temp dirs only. | Keep. | Move beside future `corpus_map` CLI package tests. |
| `tools/local_corpus_runtime_metrics_tests.py` | Active test helper | Tests local corpus runtime metrics selection, dry-run behavior, output confinement, label-based filenames, and stdout/stderr redaction. | Required when `scripts/run-local-corpus-runtime-metrics.py` changes. | Uses synthetic temporary label maps, fake module paths, and a fake app runner. | Test temp dirs only. | Keep. | Move beside future corpus runtime diagnostics CLI tests. |
| `tools/synthetic_xm_fixture_generator_tests.py` | Active test helper | Tests the deterministic synthetic XM fixture manifest skeleton and output-path confinement. | Required when `scripts/generate-synthetic-xm-fixtures.py` or `tests/reference-xm/` generator contracts change. | Uses synthetic manifest data and temporary directories only. | Test temp dirs only. | Keep. | Extend alongside future public fixture-generation behavior. |
| `tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift` | Active test reference | Swift render/export tests include a helper that invokes `scripts/audio-compare.py` for Float32 comparison checks. | SwiftPM test target `VTXRenderBoundedXMTests`. | Uses generated test files and temp directories. | Test temp dirs only. | Keep. | Update helper path only if `audio-compare.py` gains a compatibility wrapper or unified CLI replacement. |

Unknown / needs follow-up: none found in this pass, but all archive candidates
need one final reference scan immediately before any move.

## Consolidation Groups

Audio comparison:

- `scripts/audio-compare.py`
- `scripts/local-reference-compare-smoke.py`
- `scripts/stem-scaling-diagnostics.py`
- `scripts/analyze-audio-discontinuities.py`

Reference-render triage:

- `scripts/correlate-audio-comparison.py`
- `scripts/focused-window-voice-timeline.py`
- `scripts/focused-xm-channel-diagnostics.py`
- `scripts/summarize-reference-render-triage.py`

Effect coverage:

- `scripts/summarize-xm-effect-coverage.py`
- `vtx_render_bounded_xm --effect-coverage-json`

Residual/effect-memory scans:

- `scripts/summarize-xm-residual-effect-scan.py`

Focused window / channel / stem diagnostics:

- `scripts/focused-window-voice-timeline.py`
- `scripts/focused-xm-channel-diagnostics.py`
- `scripts/stem-scaling-diagnostics.py`

Runtime trace summaries:

- `scripts/summarize-runtime-c-mixer-trace.py`
- `scripts/correlate-runtime-offline-window.py`
- `scripts/run-local-corpus-runtime-metrics.py`

Corpus label-map tooling:

- `scripts/run-local-corpus-runtime-metrics.py`
- `scripts/update-private-xm-corpus-label-map.py`
- `scripts/summarize-xm-residual-effect-scan.py`

Golden/test helpers:

- `scripts/check-files.sh`
- `scripts/run-golden.sh`
- `scripts/generate-synthetic-xm-fixtures.py`
- `tools/mc_dump/main.c`
- `tools/audio_compare_tests.py`
- `tools/xm_residual_effect_scan_tests.py`
- `tools/private_xm_corpus_label_map_tests.py`
- `tools/local_corpus_runtime_metrics_tests.py`
- `tools/synthetic_xm_fixture_generator_tests.py`
- `tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift`

Bounded render/export:

- `tools/vtx_render_bounded_xm/main.swift`
- `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift`

## Future Unified CLI Shape

Do not implement this in the inventory PR. A future CLI can be either a Python
package with subcommands or a `tools/vtx_diag/` command surface with stable
compatibility wrappers.

One possible shape:

```text
tools/vtx_diag/
  __main__.py
  audio_compare        # compare, smoke defaults, discontinuities, stems
  reference_triage     # correlate, focused-window, focused-channel, triage summary
  effect_coverage      # diagnostics/runtime coverage summaries
  residual_scan        # private corpus residual effect-memory scans
  runtime_trace        # trace summarize and runtime/offline window correlation
  corpus_map           # private corpus label-map update and redacted summary
```

The SwiftPM tools should remain separate unless a later design explicitly moves
them:

- `mc_dump` remains the parser inspection/golden helper.
- `vtx_render_bounded_xm` remains the bounded render/export CLI entrypoint.
- `BoundedXMRenderTool.swift` now lives under
  `tools/vtx_render_bounded_xm/Support/`; keep that implementation separate
  from future Python diagnostic consolidation unless a later Swift tooling
  module design explicitly supersedes it.

Compatibility rule for consolidation PRs: keep existing script paths as
wrappers until all docs, tests, prompts, and local workflows have migrated.

## Candidate Archive List

No files should be archived in this PR.

| Path | Why it may be safe later | Required check before moving |
| --- | --- | --- |
| `scripts/stem-scaling-diagnostics.py` | It is a narrow stem reconstruction and focused matched-stem residual helper with current tests and active Amiga parity diagnostics. | Confirm no current docs/prompts use it, migrate tests, then add a compatibility wrapper or archive note. |
| `scripts/analyze-audio-discontinuities.py` | Its adjacent-jump report overlaps with audio comparison and runtime trace summary diagnostics. | Confirm click/discontinuity triage is covered by a unified subcommand and update `tools/audio_compare_tests.py`. |
| `scripts/summarize-reference-render-triage.py` | It summarizes a narrow manifest format from earlier reference-render triage work. | Confirm the manifest workflow is inactive or represented in `reference_triage`; keep anonymization tests. |
| `scripts/focused-xm-channel-diagnostics.py` | It is a narrow row/channel artifact combiner and is not in the current short workflow docs. | Check archived-report-only status again, ask whether maintainers still use it locally, and migrate tests if needed. |

Not archive candidates:

- `scripts/audio-compare.py`, `scripts/local-reference-compare-smoke.py`,
  `scripts/correlate-audio-comparison.py`,
  `scripts/focused-window-voice-timeline.py`,
  `scripts/summarize-xm-effect-coverage.py`,
  `scripts/summarize-runtime-c-mixer-trace.py`,
  `scripts/correlate-runtime-offline-window.py`,
  `scripts/summarize-xm-residual-effect-scan.py`,
  `scripts/update-private-xm-corpus-label-map.py`,
  `tools/mc_dump/main.c`, `tools/vtx_render_bounded_xm/main.swift`, and
  `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift`.

## M4: BoundedXMRenderTool Source Location

Completed state:

- The developer-only bounded XM render implementation moved from
  `app/VoodooTrackerX/VoodooTrackerX/BoundedXMRenderTool.swift` to
  `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift`.
- `tools/vtx_render_bounded_xm/main.swift` is intentionally tiny and imports the
  tool body through the SwiftPM support target.
- The file is not referenced by the Xcode app project, while `Package.swift`
  includes it in the `VoodooTrackerXPlaybackSupport` target used by the CLI.
- The Xcode app project should continue to exclude the implementation from the
  app target.

Classification:

- Active diagnostic/export tool implementation.
- Not an archive candidate.
- M4 move/refactor completed.

Preserved behavior:

- Preserve `vtx_render_bounded_xm` behavior, the existing CLI entrypoint, all
  tests, `Package.swift` source inclusion/exclusion behavior, Xcode app build
  exclusion, and runtime playback behavior.
- Do not pair source-location maintenance with playback, parser, or diagnostic
  behavior changes.

## Future PR Sequence

1. Land this inventory and consolidation plan without script behavior changes.
2. Move or split `BoundedXMRenderTool.swift` into a tool-owned location while
   preserving the CLI entrypoint, tests, Package.swift behavior, and Xcode app
   exclusion. Completed in M4.
3. Add a minimal unified diagnostic CLI/package skeleton with no behavior
   changes and with compatibility wrappers for existing script paths.
4. Move audio comparison and smoke-wrapper behavior behind the unified
   `audio_compare` command; keep existing script wrappers until docs and tests
   are migrated.
5. Move effect coverage, residual scan, and corpus map tooling behind
   `effect_coverage`, `residual_scan`, and `corpus_map`, preserving redaction
   tests.
6. Move runtime trace and reference-triage helpers behind `runtime_trace` and
   `reference_triage`, preserving report schemas and focused-window tests.
7. Archive or delete only the scripts proven unused after compatibility
   wrappers, docs, tests, prompts, and local workflows have migrated.
