# XM Backend Freeze / Hardening Audit

Diagnostics/planning audit for the temporary XM backend foundation freeze.

Date: 2026-06-01

## Scope

This report audits the current XM backend after the linear effect completion,
Amiga frequency-table foundation, Amiga `3xx` parity fix, and short-loop phase
diagnostics.

This PR is documentation-only. It does not change playback behavior, C mixer
DSP, parser architecture, runtime backend selection, or tracker viewport
behavior.

Private modules and generated artifacts stayed outside the repository. Public
examples use anonymized `xm-corpus-###` labels only.

## Recommendation

VoodooTracker X is ready to enter a temporary backend foundation freeze for GUI,
editor, and product work, with clearly documented parity-watch exceptions.

The freeze should mean:

- no new behavior-changing XM effect PRs by default
- no C mixer DSP changes by default
- no parser architecture changes under the backend-freeze label
- no runtime backend churn
- no tracker viewport changes coupled to backend work
- backend changes only for release-blocking crashes, deterministic
  runtime/offline mismatches, severe open-time/performance regressions, or a
  maintainer-promoted compatibility blocker

This is not a claim of FT2/OpenMPT bit-perfect playback. It is a practical
foundation-freeze recommendation: the remaining known gaps are either documented
parity-watch items, intentionally deferred v1 non-blockers, local reference
residuals that need narrower evidence before behavior changes, or diagnostics
cleanup candidates.

## Evidence Used

- `docs/xm-effect-support.md` as the canonical current effect support table.
- Current roadmap/backend docs: `docs/agent-current-state.md`,
  `docs/dev-roadmap.md`, `docs/roadmap.md`, `docs/audio-comparison.md`,
  `docs/playback-trace.md`, and `docs/diagnostic-tools.md`.
- Existing public-safe reports under `docs/reports/`, especially the final
  linear residual classification and post-`Kxx` expanded-corpus refresh.
- Fresh local structural scan with
  `scripts/summarize-xm-residual-effect-scan.py` against the private local
  label map. Redacted outputs stayed under `/tmp`.
- Fresh local bounded effect-coverage smoke across 36 anonymized labels with
  compact `--effect-coverage-json` output. This was an order-0, 60-second
  bounded smoke, not a replacement for a full-song expanded corpus report.
- Recent short-loop phase microfixtures in the C mixer and offline renderer
  tests, including the Amiga `3xx` short forward-loop windowed render case.

The ft2-clone source tree was not inspected for this report because no new
source-level reference question was needed for a docs-only freeze decision.

## 1. Final Expanded Corpus Effect Coverage

The latest committed expanded corpus reports show the shape of the linear XM
effect work before the final linear cleanup PRs and before the Amiga foundation:

- The post-`Kxx` expanded refresh covered 36 anonymized inputs.
- The largest remaining linear buckets at that time were `Rxy`, `Xxy`, `5xy`,
  `Lxx`, and volume-column tone portamento.
- Those buckets have since been implemented or moved to parity-watch in
  `docs/xm-effect-support.md`.
- `E0x` remained intentionally deferred as a limited-use filter-toggle bucket.
- Amiga-table pitch rows were correctly separated from linear-table regressions.

Fresh local evidence for this audit:

- Structural residual scan: 36 modules, 35 linear and 1 Amiga.
- Bounded coverage smoke: 36 compact coverage files, 4,166 detected commands,
  3,765 applied, 6 deferred/unsupported, 390 no-op or effect-memory-deferred,
  207 effect-memory reuses, and 0 effect-memory missing cases.
- In that bounded coverage smoke, the only deferred/unsupported command bucket
  was `E0x` filter toggle.
- The same smoke observed `Lxx` set envelope position and volume-column tone
  portamento as applied where they appeared inside the bounded window.

Important limitation: the fresh bounded smoke covers order 0 for 60 seconds per
label. It is useful freeze evidence because it catches current support-table
regressions in a broad anonymized slice, but it should not be described as a
full-song corpus refresh.

## 2. Linear XM Remaining Residuals

The remaining linear XM residuals do not block a backend foundation freeze.

Current linear residual classes:

- `E0x`: intentionally deferred filter toggle. It is low v1 value and should
  stay documented rather than promoted.
- `R00`: implemented `Rxy` foundation exists, while `R00` memory refinement
  remains parity-watch. Fresh structural evidence still sees `Rxy` rows, but
  current bounded coverage found no missing effect memory in the sampled
  window.
- `A00`, `300`, `500`, `100`, and `200` memory cases: supported where current
  first-pass memory policy applies, with no-active, no-target, no-speed, or
  no-op cases staying classified rather than forcing new playback behavior.
- `X1x`/`X2x`, `Lxx`, `5xy`, volume-column `F0...FF`, `Kxx`, `Hxy`, and core
  volume/pitch families are implemented or parity-watch in the support table.
- `Vxx`/`Wxx` high-byte findings remain classification-only, not v1 playback
  targets.

No remaining linear command in the current evidence justifies blocking GUI or
editor work.

## 3. Amiga Parity-Watch Status

The Amiga foundation is good enough to freeze as parity-watch, not as complete
parity.

Done:

- Amiga note period/frequency/sample-step foundation.
- Sample finetune metadata in the Amiga path.
- Amiga-table `2xx` portamento down foundation.
- Effect-column Amiga-table `3xx` tone portamento foundation.
- Amiga `3xx` target period alignment to the FT2-compatible quantized lookup.
- Short forward-loop phase microfixtures for C mixer and windowed offline
  render determinism.

Still parity-watch:

- One anonymized Amiga target still has a late looped-sample phase/timing
  residual after the period/target fix.
- Local diagnostics point at sustained looped voices and stable local alignment
  shifts, not a broad period-table, stereo, traversal, or gain failure.
- Reference-stem evidence remains diagnostic because individual-track exports
  did not provide a complete amplitude proof for the remaining mismatch.
- Broader Amiga pitch families beyond the narrow note, `2xx`, and effect-column
  `3xx` foundation remain deferred.

This should be frozen as a known parity-watch area. Do not change loop, ramp,
timing, sample-step, or Amiga pitch behavior without a future narrow reference
comparison PR.

## 4. Runtime / Offline Render Equivalence

Current docs state that tested runtime CoreAudio captures and offline C mixer
renders have matched at the render-core/output-capture level when sample rate,
gain/headroom, bounds, and capture settings match.

No new runtime/offline mismatch was found in this audit. Because this PR did
not change diagnostics code or playback behavior, a fresh runtime capture was
not required.

Freeze rule: treat any future runtime/offline mismatch as a diagnostic task
first. Confirm capture bounds, sample rate, gain/headroom, route/device
conversion, trace health, and comparison settings before proposing playback
behavior changes.

## 5. Reference Comparison Status

The reference comparison workflow is stable enough for a freeze:

- ft2-clone Linear remains the primary FT2-style XM reference when local export
  settings are recorded and match the candidate.
- `vtx_render_bounded_xm --wav-format float32 --mix-profile ft2` is the current
  candidate path for FT2-style comparisons.
- OpenMPT/libopenmpt, MikMod, Renoise, and other renderers remain secondary
  triangulation references.
- Reference comparisons are diagnostic evidence, not automatic correctness
  proof.

Known public-safe residual classes:

- Linear reference residuals have included amplitude/timbre, ramping, and
  reference-output-policy findings, but no current broad playback rewrite is
  justified by those reports.
- Amiga reference residuals are narrowed to looped-sample phase/timing evidence
  for one anonymized target.

Freeze rule: future reference work should promote only one narrow behavior or
diagnostic question at a time.

## 6. Performance / Open-Time / Eager Planning Risks

The biggest freeze-era backend risk is accidentally moving local diagnostics
into product paths.

Keep these out of module open and normal playback:

- full-song reference renders
- corpus coverage passes
- dry-render peak analysis for auto-headroom
- expensive per-voice/stem/reference correlation
- generated Markdown/JSON report creation
- broad trace capture by default

Local evidence from this audit reinforces the risk: a full selected-order
coverage refresh can become expensive enough that it is inappropriate for a
docs-only pass, normal app open, or routine GUI development loop.

Acceptable product-path posture during freeze:

- module open parses and displays the module without eager reference rendering
- runtime playback uses the planned C mixer path and conservative runtime gain
- long offline render/export remains an explicit developer/user action
- any future runtime auto-headroom requires an explicit preflight design and
  must not become hidden open-time work

## 7. Debug / Diagnostic Cleanup Candidates

Cleanup candidates after the freeze decision:

- Update residual-scan recommendation wording so completed foundations such as
  `Lxx` and volume-column `F0...FF` are not suggested as next implementation
  PRs by stale structural heuristics.
- Keep `scripts/summarize-xm-effect-coverage.py` and
  `scripts/summarize-xm-residual-effect-scan.py` as active local workflows, but
  align their recommendation language with `docs/xm-effect-support.md`.
- Preserve existing script paths until a unified diagnostic CLI has wrappers
  and tests.
- Keep runtime trace/capture controls debug-only and local-only.
- Do not archive stem, focused-window, runtime/offline, or residual helpers
  until active docs, tests, and maintainer workflows are migrated.

No diagnostic cleanup should change playback behavior.

## 8. Remaining Deferred Effects And V1 Blocking Status

Deferred or not-v1 buckets that do not block the freeze:

- `E0x` filter toggle: limited-usefulness deferral.
- `7xy` tremolo and `E7x` tremolo control: not observed in the fresh structural
  corpus scan; promote only with concrete corpus/reference evidence.
- `E3x` glissando control: useful only with a later portamento parity target.
- `E8x` panning and `Pxy` panning slide: `8xx` and volume-column panning cover
  the current v1 surface; promote only with corpus evidence.
- `EEx` pattern delay: traversal/timing hazard but not observed in the fresh
  structural scan; keep deferred until needed.
- `EFx` invert loop / funk repeat: not a current playback target.
- `Txy` tremor: not observed in the fresh structural scan.
- Volume-column vibrato speed/depth: not observed in the fresh structural scan.
- Broader Amiga pitch families outside the narrow foundation: parity-watch and
  future target, not freeze blocker.
- OpenMPT / ModPlug extensions: not targeted for v1.

These should remain visible in diagnostics so real user modules can promote
them later with evidence.

## 9. Recommended Backend Freeze Criteria

Enter and maintain the temporary backend freeze when all of these are true:

- `docs/xm-effect-support.md` matches current implementation status.
- The latest docs/tooling verification commands pass.
- No local privacy scan finds private module names, local absolute module
  paths, generated WAV paths, trace contents, or corpus label maps in committed
  files.
- Runtime default remains CoreAudio C mixer; retired AVAudio paths remain
  retired.
- Offline render/export remains the deterministic comparison path.
- Runtime/offline equivalence has no open reproducible mismatch for tested
  scenarios.
- Linear XM deferred effects are explicitly documented as non-blocking v1
  deferrals or parity-watch residuals.
- Amiga support is documented as a narrow foundation plus parity-watch residual,
  not complete parity.
- Full-song/corpus diagnostics remain local and explicit, not eager app-open
  work.
- Any future backend behavior PR is justified by a narrow blocker or a
  maintainer-promoted compatibility target.

Exit or pause the freeze only for:

- crash/data-corruption risk in supported module load/playback
- reproducible runtime/offline mismatch after diagnostic controls are checked
- severe playback/open-time performance regression
- a concrete v1 module compatibility blocker promoted by the maintainer
- CI/test breakage caused by backend infrastructure

## 10. Recommended Next 3 PRs

1. `tools: align xm diagnostic recommendations`

   Docs/tooling-only cleanup. Update residual/effect coverage recommendation
   wording so structural scans do not suggest already-completed effect
   foundations. Keep output redaction tests and existing script paths.

2. `editor: add first pattern entry slice`

   Return to the product path. Start with the smallest editable tracker-cell
   workflow that preserves the existing static-highlight viewport and does not
   touch backend behavior.

3. `app: audit module-open performance boundaries`

   Product hardening. Document or instrument open-time boundaries so parser/UI
   loading, playback planning, offline rendering, reference comparison, and
   diagnostic generation stay separated.

Backend parity work such as `R00` memory refinement, broader Amiga pitch, or
additional deferred effects should remain parked unless one of the freeze exit
criteria is met.

## Verification Notes For This Audit

Generated local artifacts used while preparing this report stayed under `/tmp`
and were not committed.

The full selected-order corpus coverage attempt was stopped before completion
because it was too expensive for this docs-only audit. That reinforces the
performance recommendation above and is not used as authoritative coverage
evidence.
