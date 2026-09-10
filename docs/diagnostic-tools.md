# Diagnostic Tools Inventory

This inventory records the current organization and ownership boundaries for
diagnostic, comparison, coverage, and helper tooling.

## Current Inventory Summary

Inventoried files:

- 18 files under `scripts/`.
- 4 Python test helper modules under `tools/`.
- 1 Python fixture-generator test helper under `tools/`.
- 1 unified Python diagnostic CLI package under `tools/vtx_diag/`, with core
  comparison, local smoke, stem, discontinuity, reference correlation, and
  focused-window behavior plus effect-coverage, residual-scan, runtime-trace
  summary, runtime/offline-window correlation, and corpus-map management
  migrated with focused tests.
- 2 SwiftPM command entrypoints under `tools/`.
- 1 active Swift command implementation under tool-owned SwiftPM support
  sources.

The Swift test suite also invokes `scripts/audio-compare.py` from
`tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift`; that test file is
tracked below as a reference, not as a standalone diagnostic tool.

## Consolidation Status

Diagnostic-tool consolidation is complete. The stable
`python3 -m tools.vtx_diag` entrypoint owns exactly six command families:

- `audio_compare` is package-authoritative.
- The active `reference_triage` core is package-authoritative; its two tested
  archive candidates remain standalone.
- `effect_coverage` analysis is package-authoritative;
  `vtx_render_bounded_xm --effect-coverage-json` remains the separate producer.
- `residual_scan` is package-authoritative.
- The active `runtime_trace` analyzers are package-authoritative.
- `corpus_map` is package-authoritative.

Migrated legacy paths remain compatibility wrappers.
`run-local-corpus-runtime-metrics.py` remains standalone cross-family
orchestration, while `mc_dump` and `vtx_render_bounded_xm` remain separate tool
surfaces. Benchmark, fixture-generation, hygiene, privacy, golden, and
release-packaging helpers retain distinct ownership. No archive or deletion
work is required for diagnostic consolidation to remain complete.

Classification terms:

- Active workflow: documented and expected for current development.
- Active test helper: used to test scripts or tool outputs.
- Diagnostic / local-only: intended for local investigation, usually with
  generated artifacts.
- Hyper-specific investigation artifact: built for a narrow historical
  investigation and still potentially useful.
- Legacy / candidate archive: likely archiveable after references and tests are
  moved or retired.
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
| `scripts/bench-render.sh` | Active workflow; local-only Release render benchmark helper | Runs `swift run -c release vtx_render_bounded_xm --product-export-profile` and prints elapsed wall-clock time for local render/export timing. | `README.md`, `docs/testing.md`, `docs/contributing.md`, `docs/audio-comparison.md`. | Reads local XM inputs; private module paths and generated timing notes must stay out of committed docs. | Yes by default for generated WAV output; extra diagnostics should also use `/tmp` or ignored scratch paths. | Keep. | Leave as a small wrapper. Do not add long benchmark runs to CI without a separate performance-benchmarking design. |
| `scripts/run-golden.sh` | Active workflow; golden/test helper | Regenerates parser golden JSON snapshots from redistribution-safe fixtures. | `README.md`, `docs/testing.md`; calls `swift run mc_dump`. | No private data; uses committed fixtures only. | No; intentionally writes `tests/golden/`. | Keep. | Leave separate from diagnostics; only run for intentional parser snapshot changes. |
| `scripts/generate-synthetic-xm-fixtures.py` | Active test helper; fixture generator | Prints or writes the deterministic source manifest and can explicitly write approved generated XM fixtures under `tests/reference-xm/generated/`, including `basic-instrument-sample.xm` and `multi-pattern-loop-boundary.xm`. | `tests/reference-xm/README.md`, `docs/design/synthetic-xm-reference-fixture-pack.md`, `tools/synthetic_xm_fixture_generator_tests.py`. | No private data; explicitly forbids private modules and private corpus dependencies. | No by default; writes only requested manifest or XM fixture paths when invoked with `--write-manifest` or `--write-xm`; no reference renders. | Keep. | Extend in small reviewed fixture PRs; do not emit reference renders by default. |
| `scripts/audio-compare.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy comparator CLI and helper-import surface while delegating to `tools/vtx_diag/audio_compare.py`. | `docs/testing.md`, ADR 004, archived reports, `tools/audio_compare_tests.py`, Swift render tests, package-owned stem diagnostics. | Handles WAVs that may be derived from private modules; reports must use public-safe labels. | Yes for JSON/Markdown reports and source WAVs unless using temp test dirs. | Compatibility path. | Keep until all maintained callers and prompts use `vtx_diag audio_compare compare`. |
| `scripts/local-reference-compare-smoke.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy local smoke CLI while delegating to the package-owned smoke workflow. | Archived reports and `tools/audio_compare_tests.py`. | Handles local candidate/reference WAVs; metadata is printed only and must stay public-safe. | Yes; defaults to `/tmp/vtx-local-reference-comparison`. | Compatibility path. | Keep until all maintained callers and prompts use `vtx_diag audio_compare smoke`. |
| `scripts/correlate-audio-comparison.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy worst-window correlation CLI and helper-import surface while delegating to `tools/vtx_diag/reference_triage_correlate.py`. | `docs/audio-comparison.md`, archived reports, `tools/audio_compare_tests.py`, `tools/vtx_diag/reference_triage_migration_tests.py`. | Handles diagnostics from local/private modules; labels and metadata must be anonymized. | Yes. | Compatibility path. | Keep until all maintained callers and prompts use `vtx_diag reference_triage correlate`. |
| `scripts/focused-window-voice-timeline.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy focused-window CLI and helper-import surface while delegating to `tools/vtx_diag/reference_triage_focused_window.py`. | `docs/audio-comparison.md`, archived reports, `tools/audio_compare_tests.py`, `tools/vtx_diag/reference_triage_migration_tests.py`. | Reads local diagnostics JSON; output should not expose input paths. | Yes. | Compatibility path. | Keep until all maintained callers and prompts use `vtx_diag reference_triage focused-window`. |
| `scripts/analyze-audio-discontinuities.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy adjacent-sample jump/click CLI while delegating to `tools/vtx_diag/audio_compare_discontinuities.py`. | Archived audio history, `tools/audio_compare_tests.py`, unified migration tests. | Handles local WAVs and optional diagnostics derived from private modules. | Yes. | Compatibility path. | Keep until a later explicit archive decision after callers and maintained workflows use `vtx_diag audio_compare discontinuities`. |
| `scripts/stem-scaling-diagnostics.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy stem sum, reconstruction, and focused matched-stem CLI while delegating to `tools/vtx_diag/audio_compare_stems.py`. | `docs/audio-comparison.md`, archived audio history, `tools/audio_compare_tests.py`, unified migration tests. | Handles local stem WAVs that may be derived from private modules. | Yes. | Compatibility path. | Keep until a later explicit archive decision after callers and maintained workflows use `vtx_diag audio_compare stems`. |
| `scripts/summarize-reference-render-triage.py` | Diagnostic / local-only; active automated tests; archived workflow references only; hyper-specific; candidate archive | Summarizes anonymized triage manifests that point at local comparison JSONs. | `tools/audio_compare_tests.py` imports its helpers and exercises its CLI; the only workflow invocation is in archived audio history. No current workflow doc invokes it. | Manifest may describe local/private comparison outputs; committed summaries must stay anonymized. | Yes for manifests and generated summaries. | Standalone archive candidate. | Candidate for archive after a dedicated removal/reference scan; retain standalone until that scope moves or retires its tests. |
| `scripts/summarize-xm-effect-coverage.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy effect-coverage summary CLI and helper-import surface while delegating to `tools/vtx_diag/effect_coverage.py`; recommendation wording remains freeze-aligned with `docs/xm-effect-support.md`. | `BoundedXMRenderTool.swift` help text, archived reports, `tools/audio_compare_tests.py`, `tools/vtx_diag/effect_coverage_migration_tests.py`. | Reads diagnostics/traces that may come from private modules; output retains basename-only input identity. | Yes. | Compatibility path. | Keep until all maintained callers and prompts use `vtx_diag effect_coverage summarize`. |
| `scripts/summarize-xm-residual-effect-scan.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy residual-scan CLI and helper-import surface while delegating to `tools/vtx_diag/residual_scan.py`; recommendation wording remains freeze-aligned with `docs/xm-effect-support.md`. | `tools/xm_residual_effect_scan_tests.py`, `tools/vtx_diag/residual_scan_migration_tests.py`; archived reports. | Yes; consumes an explicitly supplied or environment-selected local label map and emits public-safe labels/counts. | Yes; the map default is under `/tmp`, and generated reports remain caller-selected as before. | Compatibility path. | Keep until maintained callers and prompts use `vtx_diag residual_scan summarize`. |
| `scripts/focused-xm-channel-diagnostics.py` | Diagnostic / local-only; active automated tests; archived workflow references only; hyper-specific; candidate archive | Builds a focused row/channel report from `mc_dump` JSON and bounded render diagnostics. | `tools/audio_compare_tests.py` imports and unit-tests its summary and Markdown helpers; workflow references are confined to archived audio history. No current workflow doc invokes it. | Reads local artifacts, not module files; report should not echo input paths. | Yes. | Standalone archive candidate. | Candidate for archive after a dedicated removal/reference scan and confirmation of maintained local use; retain standalone for now. |
| `scripts/summarize-runtime-c-mixer-trace.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy runtime C mixer trace-summary CLI and helper-import surface while delegating to `tools/vtx_diag/runtime_trace_summary.py`. | `docs/playback-trace.md`, archived reports, `tools/audio_compare_tests.py`, `tools/vtx_diag/runtime_trace_migration_tests.py`. | Reads runtime traces from local/private smoke runs; listening notes must stay local. | Yes. | Compatibility path. | Keep until maintained callers and prompts use `vtx_diag runtime_trace summarize`. |
| `scripts/correlate-runtime-offline-window.py` | Active compatibility wrapper; diagnostic / local-only; hyper-specific | Preserves the legacy runtime/offline mismatch-window CLI and helper-import surface while delegating to `tools/vtx_diag/runtime_trace_correlate_window.py`. | `docs/playback-trace.md`, archived reports, `tools/audio_compare_tests.py`, `tools/vtx_diag/runtime_trace_migration_tests.py`. | Handles local runtime captures, offline WAVs, traces, and diagnostics. | Yes. | Compatibility path. | Keep until maintained callers and prompts use `vtx_diag runtime_trace correlate-window`. |
| `scripts/run-local-corpus-runtime-metrics.py` | Active standalone cross-family orchestration; diagnostic / local-only | Selects anonymized map entries, launches the Debug app, produces runtime traces, captures playback timing, adapter-plan profiles, and runtime mixer metrics, redacts logs, and writes per-label plus aggregate summaries. | `docs/testing.md`, `tools/local_corpus_runtime_metrics_tests.py`; no other active caller or importer. | Reads a maintainer-supplied local label map and redacts captured stdout/stderr; output filenames and summaries use `xm-corpus-###` labels only. | Yes; defaults to a timestamped `/tmp` directory and refuses repository output by default. | Keep standalone. | Do not place under `runtime_trace` or `corpus_map`: it orchestrates producers and several diagnostic families but neither analyzes trace contents nor manages maps. Preserve its current path until a separately designed cross-family orchestration surface exists. |
| `scripts/update-private-xm-corpus-label-map.py` | Active compatibility wrapper; diagnostic / local-only | Preserves the legacy corpus-map updater CLI and helper-import surface while delegating to `tools/vtx_diag/corpus_map.py`. | Archived reports, `tools/private_xm_corpus_label_map_tests.py`, `tools/vtx_diag/corpus_map_migration_tests.py`. | Yes; source modules and full label map stay local, defaulting to `/tmp`. | Yes for map and summaries. | Compatibility path. | Keep until maintained callers and local workflows use `vtx_diag corpus_map update`. |
| `tools/mc_dump/main.c` | Active workflow; SwiftPM C CLI entrypoint | Dumps parsed MOD/XM metadata and optional XM pattern events for tests and diagnostics. | `Package.swift`, `README.md`, `docs/testing.md`, `docs/contributing.md`, ADR 001, `scripts/run-golden.sh`, focused diagnostics. | Can read private modules if manually invoked; private JSON dumps stay local. | Yes for private/local dumps; golden outputs are intentional test artifacts. | Keep. | Leave as a parser CLI unless a broader tool package layout is introduced. |
| `tools/vtx_render_bounded_xm/main.swift` | Active workflow; SwiftPM CLI entrypoint | Tiny executable entrypoint for the bounded XM render/export tool. | `Package.swift`, `README.md`, `docs/agent-current-state.md`, `docs/audio-comparison.md`, `docs/playback-trace.md`, render tests. | Reads local/private XM modules; WAVs and diagnostics must stay local unless explicitly public-safe. | Yes for local renders and diagnostics. | Keep. | Preserve as the stable CLI entrypoint even if the implementation moves. |
| `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift` | Active diagnostic/export tool implementation; M4 source-location refactor complete | Implements the developer-only bounded XM render/export CLI used by `tools/vtx_render_bounded_xm/main.swift`. | `tools/vtx_render_bounded_xm/main.swift`, `Package.swift`, render tests, workflow docs via the CLI name. | Reads local/private XM modules and writes local WAV/diagnostics/coverage artifacts. | Yes for local outputs. | Keep. | Leave behavior unchanged; keep this under tool-owned support sources unless a later tooling module/package design supersedes it. |
| `tools/vtx_diag/` | Active unified CLI; all six planned command families migrated, with the active `reference_triage` core intentionally narrower than its archive candidates | Registers the six planned diagnostic command families. `audio_compare` owns all four comparison modes; `reference_triage correlate` and `focused-window` own the active triage core; `effect_coverage summarize` owns runtime/offline effect-coverage analysis; `residual_scan summarize` owns residual effect-memory and volume-column scans; `runtime_trace summarize` and `correlate-window` own runtime artifact analysis; `corpus_map update` owns private local map updates and public-safe summaries. | `docs/roadmap.md`, `docs/audio-comparison.md`, `docs/playback-trace.md`, this inventory, and the package CLI/migration tests. | Imports and help require no private module, corpus map, or local artifact. Existing report identity, redaction, basename-only fields, dynamic local-map inputs, and caller-selected output behavior remain unchanged. | Yes for caller-selected outputs, corpus-map `/tmp` defaults, and the smoke workflow's `/tmp` default. | Keep. | Preserve package authority, compatibility wrappers, and each command family's existing local-data boundary. |
| `tools/audio_compare_tests.py` | Active test helper | Synthetic unit/CLI tests for audio comparison, reference triage, runtime trace, effect coverage, focused diagnostics, and related scripts. | Direct test target run with `python3 -m unittest tools/audio_compare_tests.py`. | Uses synthetic data and temporary directories. | Test temp dirs only. | Keep. | Split by future CLI subcommand once the script surface is consolidated. |
| `tools/xm_residual_effect_scan_tests.py` | Active test helper | Unit tests for package-owned residual effect scan classification and recommendation logic. | Required with `tools/vtx_diag/residual_scan_migration_tests.py` when residual tooling is touched. | Uses synthetic module structures. | No persistent output. | Keep. | Keep focused classification coverage separate from CLI migration parity tests. |
| `tools/private_xm_corpus_label_map_tests.py` | Active test helper | Tests package-owned private corpus label-map metadata and redacted-summary behavior with synthetic XM bytes. | Required with `tools/vtx_diag/corpus_map_migration_tests.py` when corpus label-map tooling docs or code are touched. | Uses synthetic fixtures in temporary directories and asserts paths/names are redacted. | Test temp dirs only. | Keep. | Keep focused implementation coverage separate from legacy/unified migration parity tests. |
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

Effect-coverage analysis:

- `scripts/summarize-xm-effect-coverage.py`
- `tools/vtx_diag/effect_coverage.py`

Effect-coverage artifact production remains a separate SwiftPM tool surface:

- `vtx_render_bounded_xm --effect-coverage-json`

Residual/effect-memory scans:

- `scripts/summarize-xm-residual-effect-scan.py`
- `tools/vtx_diag/residual_scan.py`

Focused window / channel / stem diagnostics:

- `scripts/focused-window-voice-timeline.py`
- `scripts/focused-xm-channel-diagnostics.py`
- `scripts/stem-scaling-diagnostics.py`

Runtime trace summaries:

- `scripts/summarize-runtime-c-mixer-trace.py`
- `scripts/correlate-runtime-offline-window.py`
- `tools/vtx_diag/runtime_trace_summary.py`
- `tools/vtx_diag/runtime_trace_correlate_window.py`

Standalone cross-family local orchestration:

- `scripts/run-local-corpus-runtime-metrics.py`

Release render benchmarking:

- `scripts/bench-render.sh`

Corpus label-map management:

- `scripts/update-private-xm-corpus-label-map.py`
- `tools/vtx_diag/corpus_map.py`

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

- `scripts/bench-render.sh`
- `tools/vtx_render_bounded_xm/main.swift`
- `tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift`

`vtx_render_bounded_xm --product-export-profile` expands to the shared settings
used by app `File > Export Audio > WAV...`: 48 kHz Float32 WAV, VTX mix,
selected range until song end, a 3-second tail, 64-row windows, auto-headroom,
and user-initiated long-render permission. Explicit value options override the
profile regardless of argument order, while existing duration and gain
conflicts remain errors. The tool's diagnostic defaults remain unchanged when
the flag is absent. Generated WAVs and diagnostics remain local artifacts.

App WAV export and the shared windowed offline render path also provide
developer-facing performance diagnostics through Swift result models. These are
not a separate CLI surface and are intentionally output-neutral: they measure
render/export phase durations and counters, including sample-payload copy
estimates, accepted C voice adds, per-window and continuation uploads, duplicate
sample identities, defensive-copy versus pre-sanitized bulk-copy counts, and
unity-gain fast-path use. Windowed offline rendering uses the output-neutral
shared C payload path because `MixerSampleBuffer` guarantees finite Float32
PCM. One render-session cache owns the C payloads across fresh window mixers;
runtime and immediate/non-windowed rendering remain on copied payloads. The
original defensive sanitizer and pre-sanitized per-voice bulk-copy modes remain
available as fallback/reference paths. Diagnostics report C-owned payload
creates/bytes, voice and continuation references, avoided per-voice upload
counts/bytes, and fallback copies. Byte-identical parity tests pin shared output
to the copied references and preserve app-versus-tool and streaming parity.
App WAV progress identifies pre-index construction as an indeterminate indexing
preparation phase before the first completed window, then reports monotonic
whole-export progress weighted 5% prepared, 80% rendering, 10% headroom, and
5% final writing. The sheet can cancel safely at cooperative preparation,
render-window, headroom-chunk, and final-replace checkpoints; cancellation is a
non-error result and removes temporary output. Replacement-ramp continuation
lookups use an event-keyed index instead of repeated full reverse scans, while
the existing index-build duration covers the work and output remains unchanged.

Successful app exports now also expose a concise
`WAVExportPerformanceSummary` from `WAVExportCompletionResult`. It aggregates
the existing plan/adapt, preparation/index, render, headroom, write/replace,
window/frame/event, boundary, sample-payload, auto-headroom, and unity-fast-path
metrics without changing the WAV bytes. Set
`VTX_WAV_EXPORT_PERFORMANCE_SUMMARY=1` to write the same summary as one
developer-only stderr line. Logging is off by default and never includes source
or destination paths, filenames, module titles, corpus labels, or pointer
addresses; normal export alerts are unchanged. Use the summary for local
planning/rendering/headroom/write/sample-payload cost comparisons, not as a
benchmark result committed to the repository.

The shared windowed offline render core now consumes its internal scheduling
index. Performance diagnostics report index build duration, bucket counts,
consumed production windows, per-window event/update-candidate counts, and
avoided scan estimates. Byte-parity tests keep this optimization output-neutral;
continuation history construction retains its separately counted per-window
scan. The change does not alter the CLI surface, C mixer DSP, or runtime playback.

## Unified CLI Surface

The stable top-level entrypoint is:

```bash
python3 -m tools.vtx_diag --help
```

It registers exactly `audio_compare`, `reference_triage`, `effect_coverage`,
`residual_scan`, `runtime_trace`, and `corpus_map`. The fully migrated
`audio_compare` family is authoritative at:

```bash
python3 -m tools.vtx_diag audio_compare compare --help
python3 -m tools.vtx_diag audio_compare smoke --help
python3 -m tools.vtx_diag audio_compare stems --help
python3 -m tools.vtx_diag audio_compare discontinuities --help
```

The active reference-triage core is authoritative at:

```bash
python3 -m tools.vtx_diag reference_triage correlate --help
python3 -m tools.vtx_diag reference_triage focused-window --help
```

Effect-coverage analysis is authoritative at:

```bash
python3 -m tools.vtx_diag effect_coverage summarize --help
```

Residual effect-memory and volume-column analysis is authoritative at:

```bash
python3 -m tools.vtx_diag residual_scan summarize --label-map <path> [existing arguments...]
```

Runtime trace analysis is authoritative at:

```bash
python3 -m tools.vtx_diag runtime_trace summarize --help
python3 -m tools.vtx_diag runtime_trace correlate-window --help
```

Private local corpus-map management is authoritative at:

```bash
python3 -m tools.vtx_diag corpus_map update \
  --source-dir <path> \
  --map <path> \
  --summary-json <path> \
  --summary-markdown <path>
```

The `audio_compare` modes own the existing WAV comparator, local smoke defaults,
stem reconstruction and matched-stem analysis, and discontinuity analysis. All
four legacy paths remain executable compatibility wrappers with their existing
arguments, output, helper imports, and exit behavior:

- `scripts/audio-compare.py`
- `scripts/local-reference-compare-smoke.py`
- `scripts/stem-scaling-diagnostics.py`
- `scripts/analyze-audio-discontinuities.py`

Package-owned stem diagnostics imports comparator helpers directly from
`tools.vtx_diag.audio_compare`; the legacy comparator re-export remains for
external compatibility callers.

The active reference-triage implementations live under `tools/vtx_diag/`.
These legacy paths remain executable compatibility wrappers with their existing
arguments, report schemas, output, helper imports, and exit behavior:

- `scripts/correlate-audio-comparison.py`
- `scripts/focused-window-voice-timeline.py`

The audited `scripts/focused-xm-channel-diagnostics.py` and
`scripts/summarize-reference-render-triage.py` helpers remain standalone archive
candidates. They are not exposed as speculative unified modes.

The package-owned `effect_coverage summarize` mode preserves the existing
runtime JSONL and bounded offline diagnostics inputs, report schemas,
classification and recommendation wording, and basename-only input identity.
`scripts/summarize-xm-effect-coverage.py` remains an executable compatibility
wrapper with its existing arguments and behavior. It does not replace or absorb
`vtx_render_bounded_xm --effect-coverage-json`: the SwiftPM tool produces raw
coverage artifacts, while the Python command analyzes and summarizes them.

The package-owned `residual_scan summarize` mode preserves the existing dynamic
`--label-map <path>` and `VTX_PRIVATE_XM_CORPUS_LABEL_MAP` inputs, report schemas,
classification and recommendation wording, anonymized-label redaction, and
caller-selected output behavior. The map remains optional maintainer-local input
and is neither hardcoded nor required by automated tests.
`scripts/summarize-xm-residual-effect-scan.py` remains an executable
compatibility wrapper with its existing arguments, outputs, helper imports, and
exit behavior. Corpus-map creation and updates remain a separate command family
owned by `corpus_map update`.

The package-owned `runtime_trace summarize` and `runtime_trace correlate-window`
modes preserve the existing JSONL/WAV inputs, CLI defaults, JSON and Markdown
schemas, trace interpretation, alignment, recommendation text, basename-only
identity, validation, output streams, and exit behavior. These legacy paths
remain executable compatibility wrappers with their existing helper imports:

- `scripts/summarize-runtime-c-mixer-trace.py`
- `scripts/correlate-runtime-offline-window.py`

The audited `scripts/run-local-corpus-runtime-metrics.py` remains standalone and
is not exposed as `runtime_trace corpus-metrics`. It consumes a local label map
but does not create or update one, and it produces runtime traces but does not
interpret their JSONL contents. Its primary responsibility is cross-family
orchestration of app launch, playback timing, adapter-plan profiling, mixer
metrics, trace production, redaction, confinement, and aggregate reporting.

The package-owned `corpus_map update` mode preserves the existing `--source-dir`,
`--map`, `--summary-json`, and `--summary-markdown` arguments, the dynamic
`VTX_PRIVATE_XM_CORPUS_LABEL_MAP` map default, stable label assignment, map and
summary schemas, redaction, ordering, validation, output destinations, output
streams, and exit behavior. The source modules and full map remain
maintainer-local; public-safe summaries contain anonymized labels and approved
aggregate metadata only. `scripts/update-private-xm-corpus-label-map.py` remains
an executable compatibility wrapper with the same arguments and helper imports.
It does not absorb residual-effect classification or the standalone runtime
corpus orchestration helper. Shared exit statuses remain `0` for success, `1`
for operational failure, `2` for usage error, and `3` for migration pending.

Current package shape:

```text
tools/vtx_diag/
  __init__.py
  __main__.py
  cli.py               # registry, parser, dispatch, and shared exit/error contract
  audio_compare.py     # authoritative core WAV comparator
  audio_compare_smoke.py # authoritative local smoke defaults and confinement
  audio_compare_stems.py # authoritative stem sum and matched-stem diagnostics
  audio_compare_discontinuities.py # authoritative jump analysis and correlation
  reference_triage_correlate.py # authoritative worst-window correlation
  reference_triage_focused_window.py # authoritative focused voice timelines
  effect_coverage.py   # authoritative runtime/offline effect-coverage summary
  residual_scan.py     # authoritative residual effect-memory/volume-column scan
  runtime_trace_summary.py # authoritative runtime C mixer trace summary
  runtime_trace_correlate_window.py # authoritative runtime/offline window correlation
  corpus_map.py        # authoritative private local map update/redacted summaries
  cli_tests.py         # registry, help, dispatch, and import tests
  audio_compare_migration_tests.py # legacy/unified parity and confinement tests
  reference_triage_migration_tests.py # triage parity, confinement, and audit tests
  effect_coverage_migration_tests.py # legacy/unified report and failure parity
  residual_scan_migration_tests.py # residual parity, redaction, and confinement tests
  runtime_trace_migration_tests.py # runtime summary/window parity and confinement tests
  corpus_map_migration_tests.py # corpus-map parity, redaction, and confinement tests
```

The SwiftPM tools should remain separate unless a later design explicitly moves
them:

- `mc_dump` remains the parser inspection/golden helper.
- `vtx_render_bounded_xm` remains the bounded render/export CLI entrypoint.
- `BoundedXMRenderTool.swift` now lives under
  `tools/vtx_render_bounded_xm/Support/`; keep that implementation separate
  from the Python diagnostic package unless a later Swift tooling
  module design explicitly supersedes it.

Compatibility rule: keep existing script paths as wrappers until all docs,
tests, prompts, and local workflows have migrated.

## Candidate Archive List

No archive or deletion work is required for consolidation. These candidates
remain in place pending separately scoped decisions:

| Path | Why it may be safe later | Required check before moving |
| --- | --- | --- |
| `scripts/stem-scaling-diagnostics.py` | It is now a narrow compatibility wrapper for the migrated stem workflow. | Keep until a later explicit archive decision verifies every caller, prompt, and maintained local workflow uses the unified command. |
| `scripts/analyze-audio-discontinuities.py` | It is now a narrow compatibility wrapper for the migrated discontinuity workflow. | Keep until a later explicit archive decision verifies every caller, prompt, and maintained local workflow uses the unified command. |
| `scripts/summarize-reference-render-triage.py` | Current references are active automated tests plus archived workflow history; no current workflow doc invokes it. | Candidate for archive after a dedicated removal/reference scan; decide whether to retire or relocate its active tests in that scope. |
| `scripts/focused-xm-channel-diagnostics.py` | Current references are active automated tests plus archived workflow history; no current workflow doc invokes it. | Candidate for archive after a dedicated removal/reference scan and confirmation that no maintained local workflow still needs it. |

Not archive candidates:

- `scripts/audio-compare.py`, `scripts/local-reference-compare-smoke.py`,
  `scripts/correlate-audio-comparison.py`,
  `scripts/focused-window-voice-timeline.py`,
  `scripts/summarize-xm-effect-coverage.py`,
  `scripts/summarize-runtime-c-mixer-trace.py`,
  `scripts/correlate-runtime-offline-window.py`,
  `scripts/summarize-xm-residual-effect-scan.py`,
  `scripts/run-local-corpus-runtime-metrics.py`,
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

## Consolidation Closeout

All six planned command families are migrated behind the unified package with
their focused compatibility and confinement tests. Remaining wrappers and
standalone helpers preserve deliberate compatibility or ownership boundaries;
they do not leave the milestone open. Any later archive or deletion is a
separate hygiene contract that first verifies callers, docs, prompts, tests,
and maintained local workflows.
