# Audio Export, Render Performance, and Architecture Risk Audit

Review-only audit of app WAV export parity, offline render performance, C mixer
memory ownership and thread safety, future export and editor architecture, and
parser/writer/editable-copy invariants.

Date: 2026-07-09
Audited tree: `main` at `a146348`.

## Scope and method

This report is documentation-only. It changes no runtime playback behavior, no
C mixer DSP, no parser architecture, no tracker viewport behavior, and it does
not enable Save/Save As or loaded-module direct editing. All suggested fixes
are scoped to be freeze-compatible under the current XM backend foundation
freeze (instrumentation, export-layer changes, refactors behind tests, docs,
and narrow parser input validation).

The audit was produced by parallel specialized review passes over the active
tree (app/, core/, tools/, scripts/, docs/, tests/, Package.swift, the Xcode
project), followed by adversarial evidence verification of every high-severity
finding against the code, a completeness pass against the requested scope, and
maintainer-side resolution of reviewer disagreements by direct code
inspection. No builds, renders, or profiles were executed; performance
findings are complexity-shape conclusions from code structure, which is why
the instrumentation PR is recommended first. A local checkout of the public
open-source ft2-clone project was consulted for a conceptual comparison; no
code was copied and all references use its public file names.

Line numbers reference the audited commit and will drift; symbol names are the
stable anchors.

## 1. Executive summary

The offline render/export foundation is in better shape than a file-size scan
suggests: the app export and the diagnostic render tool compile the same
sample-affecting code (mixer, scheduler, timing planner, WAV writer, headroom
math) through the shared SwiftPM playback-support target, sample payload
ownership across the Swift/C boundary is copy-based and leak-free, the C core
has no global state, retired backends are genuinely deleted, and the zero-TODO
docs-tracked-deferral convention actually holds.

The audit found **no blockers** and twelve high-severity findings in four
clusters:

1. **Robustness**: the C XM header parser can `memcpy` up to 256 bytes past
   the end of a hostile file's buffer on every File > Open (INV-A1), and the
   editable-copy boundary silently converts Amiga-frequency-table modules to
   linear on playback and export (INV-B1).
2. **Real-time hygiene**: the CoreAudio render callback performs
   malloc/free and whole-sample copies via C mixer voice lifecycle calls,
   contradicting its own documented contract, and the runtime snapshot
   hard-codes diagnostics that claim otherwise (MIX-A1, MIX-A4).
3. **Export performance**: the windowed product export replans the whole song
   for every 64-row window (quadratic in song length), re-copies full sample
   PCM into fresh C-owned storage for every note and every window-boundary
   continuation, runs per-sample Swift encode/decode loops over both file
   passes, and always executes a second full-file headroom pass even when the
   computed gain is exactly 1.0 (PERF-A1/A2/A3, PERF-C1/C2). Separately, every
   documented local build and `swift run` workflow is Debug/`-Onone`, so most
   existing timing impressions conflate architecture with compiler settings
   (PERF-B1/B2). The shipped DMG builds Release, so end users get optimized
   code; local comparisons against tracker-native exporters do not.
4. **Verification gaps**: no test pins app-export bytes against tool-render
   bytes even though parity is the export feature's stated claim (PAR-2), and
   the render tool's 109-test suite compiles but never executes in CI
   (QLT-2).

Parity itself is currently intact: under the documented flag set the app
export and the tool should produce byte-identical WAVs because everything
sample-affecting is shared code. That equivalence, however, rests on two
unpinned duplicated ~250-line render loops and a constellation of
independently defined defaults — it is protected by luck, not tests.

The design reviews conclude that both the unified audio export architecture
(PCM16/AAC/ranges/stems) and the Instrument/Sample Editors are reachable
without touching the render core or parser: the render request type already
carries order ranges and a channel isolation filter, and the instrument/sample
model is already a pure Swift value model. The prerequisite work is seams, not
engines: a shared render configuration, an encoder seam, cancellation, an
undo funnel, a palette mutation policy, and model fields for panning
envelope/vibrato data that the writer currently zero-fills.

## 2. Top findings, ranked by impact and risk

Severity: blocker = corruption/crash/data-loss or goal impossible; high = real
defect or major cost with concrete evidence; medium = meaningful debt or
drift; low = polish or unconfirmed suspicion. All highs were independently
adversarially verified; five findings originally filed high were downgraded to
medium during verification and appear in their sections.

| # | ID | Sev | Finding |
|---|----|-----|---------|
| 1 | INV-A1 | high | XM order-table `memcpy` can read up to 256 bytes out of bounds on hostile header sizes, reachable from File > Open |
| 2 | MIX-A1 | high | CoreAudio render callback mallocs/frees and copies whole samples via voice lifecycle calls, against its documented contract |
| 3 | PERF-A3 / PERF-C1 | high | Windowed export rescans whole-song plans every 64-row window — O(length²) scheduling work |
| 4 | PERF-C2 | high | Full sample PCM malloc'd + copied into C-owned storage per note event and per window-boundary continuation, freed at window teardown |
| 5 | PERF-A2 | high | Auto-headroom always adds a second full-file read+rewrite pass (even at gain 1.0); each rendered sample touched ~9 times end to end |
| 6 | PERF-A1 | high | Per-sample Swift encode/decode loops in both WAV passes; no bulk copy or vectorization |
| 7 | PERF-B1 | high | Every documented local workflow builds Debug (`-Onone`/`-O0`), invalidating casual speed comparisons vs native exporters |
| 8 | PAR-2 | high | No test pins app-export WAV bytes equal to tool-render bytes; `renderWindowedStreaming` has zero direct tests |
| 9 | INV-B1 | high | Editable copy silently converts Amiga-frequency-table modules to linear on playback and export |
| 10 | EDT-A1 | high | No undo architecture exists anywhere in the document layer; both editor designs require it |
| 11 | EDT-A3 | high | Editable model cannot represent the instrument editor's required v1 fields (sample panning, panning envelope, autovibrato) |
| 12 | QLT-2 | high | The render tool's 109-test suite never executes in CI |

Explicit all-clears from the completeness pass (recorded so they are not
re-audited or optimized): the mixer renders **exactly once** per export
(`WAVExportCoordinator.export` invokes `renderWindowedStreaming` once; no
repeated full renders); progress callbacks are benign (throttled to stage
changes or ≥1% deltas at `WAVExportCoordinator.swift:688`, one emission per
window, non-blocking async main-actor hop at `AppDelegate.swift:349`); no
`#if DEBUG`-only costs exist in the export path; and the Swift/C render call
granularity is healthy (one `vtx_c_mixer_render` call per window, no
per-sample Swift closures in the offline hot path).

## 3. App WAV export vs vtx_render_bounded_xm parity audit

### What is actually shared

`Package.swift:37-43` builds the render tool on a shared target that compiles
the app's own playback sources, including `PlaybackSongOfflineRender.swift`
(`Package.swift:128`) and `SoftwareMixer.swift` (`Package.swift:132`). The C
mixer, synthetic scheduler, Fxx timing planner, WAV header construction
(`SoftwareMixer.swift:868`), sample scaling (`SoftwareMixer.swift:1033`), and
the auto-headroom gain function (`SoftwareMixer.swift:455`) are literally the
same compiled code in both binaries.

The headroom semantics are provably equivalent for Float32 despite the
different pipelines. The app writes `scaledSample(s, gain: 1)` (bit-preserving
for finite samples, zeroing non-finite ones) to a temp WAV, then a gain pass
computes `Float(Double(s) * Double(gain))` (`SoftwareMixer.swift:956,
1033-1047`); the tool computes the identical expression in one pass, and both
derive gain from the same `MixerWAVExportPolicy.autoHeadroom(preExportPeak:)`
fed by the same peak accumulator. Peak is a max, so post-process chunking
cannot change results. Song-end frames use the same shared expression
(`timingPlan.frameFor(row: rowTimings.count, tick: 0)`) on both sides
(`WAVExportCoordinator.swift:380`; `BoundedXMRenderTool.swift:908`), and both
render each 64-row window in a single `mixer.render` call, so buffer
boundaries match. Conclusion: with the documented flag set (48000 Hz,
`--until-song-end --tail-seconds 3 --window-rows 64 --auto-headroom
--wav-format float32 --mix-profile vtx --allow-long-render`), app export and
tool render should be byte-identical today. This is a static-analysis
conclusion; the parity pin test below is the definitive check.

### Findings

**PAR-2 — No parity pin test; `renderWindowedStreaming` has zero direct tests
(high, verified).**
Files: `WAVExportCoordinatorTests.swift`, `OfflineRenderTests.swift`,
`tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift`.
Why: parity is the export feature's stated claim, but no test compares the two
paths. Existing equivalence tests cover only tool-internal variants
(`OfflineRenderTests.swift:194-197` compares `render` vs `renderWindowed`;
`VTXRenderBoundedXMTests.swift:1088` compares tool windowed vs tool default).
A repo-wide grep for `renderWindowedStreaming` matches only its definition and
its single call site at `WAVExportCoordinator.swift:468` — no test target.
`WAVExportCoordinatorTests` exercises the streaming path end to end but
asserts only bounds/format, never byte equality with a reference render.
Fix: an app-test-target parity pin — build a fixture spanning multiple 64-row
windows, export via `WAVExportCoordinator.export`, separately render via
`renderWindowed(windowRows: 64)` + `MixerWAVExporter.writeWAV(format:
.float32, exportPolicy: .autoHeadroom)`, assert byte-identical files. (The pin
must live in the app test target: `WAVExportCoordinator.swift` is excluded
from the SwiftPM target at `Package.swift:74`, so tool-side tests cannot see
it.)
Tests: the pin itself, plus a negative variant proving the assertion fails
when window rows differ (guards against a vacuous pass).
Manual verification: export a local module from File > Export Audio > WAV...,
run the tool with the matching eight-flag invocation, `cmp` the outputs.

**PAR-1 — App and tool run two different duplicated ~240-line windowed render
loops (medium, downgraded from high on verification).**
Files: `PlaybackSongOfflineRender.swift`, `WAVExportCoordinator.swift`,
`BoundedXMRenderTool.swift`.
Why: the app exclusively calls `renderWindowedStreaming`
(`PlaybackSongOfflineRender.swift:934`); the tool exclusively calls
`renderWindowed` (`:615`). Verification diffed the two bodies: identical
window loop, identical thirteen `Self.schedule*` calls, identical diagnostics
assembly — differing only in block accumulation vs streaming sink. They are
in sync *today* (hence medium, not high), but a scheduling call added to one
loop and not the other silently splits app output from tool output, and PAR-2
means nothing would catch it.
Fix: extract the shared per-window scheduling/render body into one private
core; `renderWindowed` wraps it by accumulating, `renderWindowedStreaming` by
forwarding to the sink. Land the PAR-2 equivalence test first, then refactor
behind it; PCM must stay bit-identical.
Tests: `renderWindowed` output equals concatenated `renderWindowedStreaming`
blocks for a multi-window fixture with carryover voices and Fxx changes.
Manual verification: same `cmp` check as PAR-2 after the refactor.

**PAR-3 — Every export-relevant default is defined independently and differs
(medium).**
Files: `WAVExportCoordinator.swift`, `BoundedXMRenderTool.swift`,
`SoftwareMixer.swift`, `AudioBackendSelection.swift`.
Why: app fixes 48 kHz / float32 / auto-headroom / 3 s tail / 64-row windows
(`WAVExportCoordinator.swift:242-248`); the tool defaults to 44.1 kHz / pcm16
/ unity / no tail / no windowing (`BoundedXMRenderTool.swift:200-211, 909`).
The divergence is deliberate product-vs-diagnostic policy, but it is encoded
nowhere shared — parity requires an eight-flag invocation documented only in
`docs/audio-comparison.md:130-139`, and either side's defaults can drift
without any failure.
Fix: a shared product-export profile constant set in the playback-support
target, referenced by `WAVExportCoordinator.defaultConfiguration` and expanded
by a new tool flag (e.g. `--product-export-profile`).
Tests: field-by-field equality of the tool's profile expansion and the app's
default configuration.
Manual verification: `--help` lists the profile values; compare against the
app progress UI.

**PAR-4 — Seconds-to-frames conversion triplicated with three rounding modes
(medium).**
Files: `WAVExportCoordinator.swift:631` (`.toNearestOrAwayFromZero`),
`BoundedXMRenderTool.swift:1068` (`.down`),
`AudioBackendSelection.swift:252` (`.up`).
Why: at the default 3.0 s / 48 kHz all three yield 144,000 frames — parity
survives by arithmetic luck. Any non-exact seconds value (a future
configurable tail; 0.7 s at 48 kHz) produces off-by-one frame counts between
app and tool, breaking byte parity.
Fix: one shared `frameCount(seconds:sampleRate:)` helper with a single
documented rounding rule for export-side conversions; leave the runtime tail
policy untouched (no-runtime-behavior-change guardrail).
Tests: exact products, binary-inexact products, zero, non-finite; a
cross-check that app plan tail frames equal the tool's diagnostics for
identical inputs.
Manual verification: `--tail-seconds 0.7 --sample-rate 48000` through both
paths; frame counts match after the fix.

**PAR-5 — Song-end/loop validation exists only in the app; the tool silently
renders guard-bounded traversals (medium).**
Files: `WAVExportCoordinator.swift:614-620`,
`BoundedXMRenderTool.swift:902-908`.
Why: the app refuses looping songs (`stopReason == .songEnd` guard); the
tool's `--until-song-end` renders whatever the guard-bounded plan yields
without reporting the stop reason. Comparisons on looping modules mislead, and
the tool cannot reproduce the app's refusal.
Fix: instrumentation-only — emit `stopReason`/`guardHit` in the tool's
progress line and diagnostics JSON. No render behavior change.
Tests: looping fixture (Bxx to order 0) reports the non-songEnd stop reason in
tool JSON; the same fixture throws `renderDurationNotDeterministic` in the
app.
Manual verification: run the tool on a Bxx-looping module and confirm the
diagnostics flag it.

**PAR-8 — Boundary-cut diagnostics are computed per window and silently
discarded by the product export; ADR 006 scope has drifted (medium; found by
the completeness pass).**
Files: `WAVExportCoordinator.swift`, `PlaybackSongOfflineRender.swift:1132-1133`,
`docs/decisions/006-windowed-offline-candidate-rendering.md`.
Why: ADR 006 accepted windowed rendering for *developer-only* candidate WAV
exports and documents audible tradeoffs (older voices not carried forward;
boundary drops under continuation pressure). The renderer records
`droppedAtWindowBoundaryCount` / `mayContainBoundaryCuts` per window, and
tests prove drops are reachable (`OfflineRenderTests.swift:594`), but
`WAVExportCoordinator` contains zero references to these fields — a product
WAV export with audible boundary cuts completes silently as success.
Fix: surface the aggregated window summary in the export completion result
(and optionally the completion alert when `mayContainBoundaryCuts` is true),
and update ADR 006 to acknowledge the product-export promotion. Export-layer
only.
Tests: a fixture that forces continuation drops asserts the completion result
carries the flag; clean fixtures assert it does not.
Manual verification: export a dense module that exceeds continuation capacity
and confirm the completion surface reports the caveat.

**PAR-6 — 100,000,000-frame safety cap duplicated as independent literals;
long-render gating differs (low).** `WAVExportCoordinator.swift:248` vs
`BoundedXMRenderTool.swift:584`; the tool's separate 60-second default clamp
is frames-based (`PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount`,
44,100 × 60), so it shrinks to ~55.1 s at `--sample-rate 48000` — worth one
doc sentence. Fix: hoist one shared cap constant.

**PAR-7 — Export progress window count recomputed independently from actual
window specs (low, unconfirmed).** `WAVExportCoordinator.swift:646` uses
`ceil(rows/64)` while the renderer builds windows from the adapter plan's
synthetic row count and skips zero-length windows
(`PlaybackSongOfflineRender.swift:1689, 1714`). Progress display only; never
PCM. Fix: expose the renderer's window-spec count and use it for the plan.

## 4. Offline render performance audit

### 4.0 Measurement conditions come first

**PERF-B1 — Every documented local app workflow builds Debug, running the
export path at Swift `-Onone` and the C mixer at `-O0` (high, verified).**
Files: `project.pbxproj`, `README.md`, `docs/testing.md`,
`docs/contributing.md`, `.github/workflows/basic-checks.yml`.
Why: the project-level Debug config pins `GCC_OPTIMIZATION_LEVEL = 0`
(`project.pbxproj:643`) and `SWIFT_OPTIMIZATION_LEVEL = "-Onone"` (`:647`,
repeated at the app target `:692`). Crucially, the app target compiles
`vtx_c_mixer.c` directly into its Sources phase (`project.pbxproj:546, 184`)
rather than linking the SwiftPM MixerCore product, so these Xcode settings —
not `Package.swift` — govern in-app mixer codegen. Every documented local
build is Debug (`README.md:144`, `docs/testing.md:10`,
`docs/contributing.md:18`, CI `basic-checks.yml:25`), and the shared scheme's
Launch action is Debug. `-Onone` is commonly a 5-30× slowdown for tight Swift
loops; `-O0` costs the C loop several × more.
Conditioning (from the completeness pass): the release workflow builds
optimized (`.github/workflows/release.yml:109`), so **end users running the
tagged DMG get Release code**. If a slowness comparison was made against the
released artifact, this finding does not explain it and the
windowing/copying findings below dominate. If timings came from Xcode
Run/`swift run` — the only documented local workflows — the comparison is
invalidated before any architectural factor is considered.
Fix: docs-only — a "Performance measurement" note in `docs/testing.md` and
`docs/contributing.md` requiring `-configuration Release` /
`swift run -c release` for any export timing or ft2-clone comparison.
Tests: none (docs).
Manual verification: export the same module from Debug and Release builds;
compare wall clock; output bytes identical.

Related, unreviewed mediums:
**PERF-B2** — the documented tool workflow is plain `swift run
vtx_render_bounded_xm` (`docs/agent-current-state.md:89`,
`docs/audio-comparison.md:66`), which SwiftPM builds debug; no doc or script
anywhere passes `-c release`. **PERF-B3** — neither Release config sets
`SWIFT_OPTIMIZATION_LEVEL`, `GCC_OPTIMIZATION_LEVEL`, or
`SWIFT_COMPILATION_MODE` (`project.pbxproj:652-669, 697-721`); build-system
defaults give Swift `-O` / C `-Os` but single-file compilation, which blocks
cross-file inlining across the export hot path — pin
`SWIFT_COMPILATION_MODE = wholemodule` (verify current values first with
`xcodebuild -showBuildSettings`). **PERF-B5** — no release-mode bench helper
exists under `scripts/`, and the one timing script defaults to the Debug app
binary (`scripts/run-local-corpus-runtime-metrics.py:20, 153`); add
`scripts/bench-render.sh` (release build + documented flags + wall-clock
report) and a Debug-path warning to the metrics script. **PERF-B6 (low)** —
the app recompiles the C sources with Xcode settings while SwiftPM compiles
them separately; any future SwiftPM-side C flags silently would not apply
in-app — document the alignment requirement.

### 4.1 The architectural costs (in likely order of dominance)

**PERF-A3 / PERF-C1 — Windowed export rescans whole-song plans every 64-row
window: O(windows × songSize), i.e. quadratic in song length (high, verified
twice independently).**
Files: `PlaybackSongOfflineRender.swift`, `WAVExportCoordinator.swift`,
`CSoftwareMixer.swift`, `core/MixerCore/src/vtx_c_mixer.c`.
Why: the adapter plan is correctly built once per export
(`PlaybackSongOfflineRender.swift:941`), but per window the loop constructs a
fresh `CSoftwareMixer` (`:971-972`), filters ALL song events for the window
(`eventPairs`, `:2633`) and again for continuations (`:1756`), runs twelve
scheduling passes that each iterate the FULL whole-song diagnostics arrays —
including every per-tick vibrato/arpeggio/portamento step update
(`:1012-1107`, e.g. `:1187, 1222, 1252`) — and per carried voice rescans all
`voiceStateUpdates` (`:1841`) plus seven full effect arrays twice via
`sampleStepUpdates` (`:1932-1953`, invoked at `:1896` and `:2331`). With
windows, events, and updates all proportional to song length, planning work is
O(L²); effect-dense songs (heavy vibrato/arpeggio) are the worst case. The
tool's default path schedules one session and renders once
(`BoundedXMRenderTool.swift:683` → `render` at
`PlaybackSongOfflineRender.swift:602-613`), which is a large part of why it
outruns the app export. Windowing itself is justified — the 256-slot voice
pool cannot hold a whole song (ADR 006) — but the per-window inputs can be
pre-partitioned once.
Fix (export-layer, order-preserving, freeze-compatible): precompute once per
export (a) events bucketed by window, (b) diagnostics indexed by
`activeEventIndex`, (c) per-event sorted step-update lists; the window loop
consumes slices. The same mixer calls are issued with the same arguments in
the same order, so PCM is bit-identical by construction.
Tests: unit tests asserting the precomputed indices reproduce the exact
per-window mixer call sequence for a fixture; existing windowed determinism
tests unchanged; an `XCTest measure{}` case on a synthetic many-window song.
Manual verification: `vtx_render_bounded_xm --window-rows 64` before/after,
byte-compare WAVs, compare wall clock on a long effect-heavy module.

**PERF-C2 — Full sample PCM malloc'd and copied into C-owned storage for
every note event and every window-boundary continuation, freed at window
teardown (high, verified).**
Files: `vtx_c_mixer.c`, `PlaybackSongOfflineRender.swift`,
`CSoftwareMixer.swift`, `PlaybackTiming.swift`.
Why: every `vtx_c_mixer_add_*` call mallocs a fresh buffer and element-copies
the whole sample through an `isfinite` sanitize loop (`vtx_c_mixer.c:819-825`)
— duplicating a sanitize already done at `MixerSampleBuffer` construction
(`SoftwareMixer.swift:171`). In the windowed export, each in-window note
copies its sample once (`PlaybackTiming.swift:241-242`) and each carried voice
re-adds its full sample at every window boundary
(`PlaybackSongOfflineRender.swift:2291-2292`); window teardown frees
everything (`CSoftwareMixer.swift:231-233` → `vtx_c_mixer.c:710`). A long
looped pad held across a whole song is re-uploaded at every 64-row boundary
per channel — plausibly hundreds of MB of malloc/copy/free churn per export
(mechanism confirmed; magnitude estimated, not measured).
Fix: instrumentation first — count add-voice calls and payload bytes at the
Swift wrapper and surface them in export diagnostics. If measurement confirms
dominance, propose an additive C API for caller-owned/interned sample buffers
as an explicit freeze-exception RFC (it changes memory ownership, not DSP
semantics), proven by byte-identical WAV comparison via the render tool.
Tests: payload-byte counters match analytic expectations for a fixture;
determinism tests unchanged.
Manual verification: Instruments Allocations during a long export; compare
transient malloc traffic against the counter and against a single-session
tool render.

**PERF-A2 — Auto-headroom adds a second full-file read+rewrite pass; each
rendered sample is touched ~9 times end to end (high, verified).**
Files: `WAVExportCoordinator.swift`, `SoftwareMixer.swift`.
Why: headroom does NOT re-render the mixer (good — the docs' single-render
claim holds), but the cost shape is three filesystem data passes (unscaled
temp write; temp read + gained rewrite; rename) and ~9 in-memory touches per
sample: C mixer write, scale+encode to `Data`, diagnostics accumulator, temp
write, gain-pass read, `pendingBytes.append` copy (`SoftwareMixer.swift:824`),
`Array(samplesData)` copy (`:947`), decode+re-accumulate+re-encode (`:955`),
final write. Verification confirmed there is no unity-gain guard:
`exportPolicy(for:)` always returns `autoHeadroom`
(`WAVExportCoordinator.swift:560-568`), which yields gain = 1 whenever the
peak is already under the ceiling (`SoftwareMixer.swift:455-462`), yet
`export()` unconditionally runs the full second pass (`:496`). A native
exporter does one write pass and ~2 touches.
Fix (keeping the two-pass architecture, which whole-song peak-dependent gain
requires): process `inputData` directly via `withUnsafeBytes` (drop both
redundant copies); derive post-gain stats from pass-1 stats × gain instead of
re-accumulating; and short-circuit to a file move when computed gain == 1.0.
Caveat from verification: the unity fast path must preserve `scaledSample`'s
non-finite sanitization (pass 1 already applied it, so a plain rename is
byte-identical — the golden test makes this mandatory, not optional).
Tests: byte- and diagnostics-identity before/after; a unity-gain fixture
exercises the fast path.
Manual verification: export a long quiet module; the Applying Headroom stage
should drop to near-instant; checksum matches pre-change output.

**PERF-A1 — Per-sample Swift encode/decode loops in both WAV passes (high,
verified; PERF-B4 is the same defect viewed from the optimization-level
angle).**
Files: `SoftwareMixer.swift`.
Why: the stream writer encodes one sample at a time — a Double round-trip
gain scale (`:1033-1036`, even at unity), then a 4-byte `Data.append` per
sample (`:1139-1141`, `:1068-1071`) — and the peak/RMS accumulator runs
`enumerated()` plus a modulo per sample (`:501-502, 535`). The gain pass
re-decodes each Float from four indexed bytes after an `Array(samplesData)`
copy (`:947-954`). For a 4-minute stereo 48 kHz song that is ~23M samples ×
2 passes of unspecialized per-sample work. Float32 LE samples are
memory-layout identical on all supported targets, so the unity path is nearly
a `memcpy` per block plus a vectorized peak scan. Verification confirmed no
vDSP/Accelerate/bulk path exists anywhere in the file.
Fix: bulk conversion via `withUnsafeBufferPointer` + `Data(bytes:count:)`
(explicit-endianness fallback retained), vDSP or plain indexed loops for
peak/RMS, one reused output buffer. Caveat: a raw memcpy path would preserve
NaN bit patterns that `scaledSample` currently zeroes — the byte-identity
golden must gate the fast path on pass-1 non-finite counts (or keep the
sanitize in the bulk loop).
Tests: golden byte-for-byte and diagnostics-equality tests over deterministic
fixtures, including non-finite and unity-gain cases; an `XCTest measure{}`
case on a multi-megabyte block.
Manual verification: `cmp` before/after exports; compare stage timings.

### 4.2 Secondary findings

**PERF-A4 / PERF-C5 — No timing instrumentation anywhere in the export path
(medium; should land FIRST).** No `os_signpost`, `DispatchTime`, or stage
timing exists in `WAVExportCoordinator`, `PlaybackSongOfflineRender`,
`CSoftwareMixer`, `MixerFloat32WAVStreamWriter`, or `vtx_c_mixer.c`; the
adapter's existing `AdapterPlanProfileSession` facility is not threaded into
the export adapt call (`PlaybackSongOfflineRender.swift:941-946`). The export
records rich correctness diagnostics but zero timing, so the split between
plan scans, payload upload, C mixing, encode, and I/O is unknowable without an
external profiler — and every fix above needs this data for prioritization
and validation. Fix: instrumentation-only PR — phase timers (plan/adapt,
per-window continuations+scheduling, mixer render, payload bytes, WAV write,
headroom pass) on `PlaybackSongWindowedRenderWindowDiagnostic` and the export
summary, plus `os_signpost` intervals. Tests: timing fields populated,
non-negative, sum ≈ total; PCM unchanged with instrumentation active.

**PERF-A5 — Whole-song export plan rebuilt on every menu validation and twice
per export start (medium; maintainer-verified against the code during this
audit).** `validateMenuItem` → `WAVExportCoordinator.canExport` →
`unavailableReason` → `_ = try makePlan(context:)`
(`WAVExportCoordinator.swift:271-296`): a full `EditablePlaybackSongBuilder`
build (editable docs), full traversal plan, and full Fxx timing plan run on
the main thread every time AppKit validates the Export WAV menu item, then
again in `beginExport`'s availability re-check and again in its `makePlan`
call (`:302-311`). Fix: cheap structural check for menu validation; single
plan computation inside `beginExport`. Same pattern exists in the
editable-copy coordinator (see EDT-A7/INV-D1: `unavailableReason` runs the
full writer dry-run — verified: `LoadedModuleEditableCopyCoordinator.swift`,
`unavailableReason` → `makeSupportedEditableCopy` → `EditableXMWriter().data`).

**PERF-C3 — The fixed 256-voice / 4096-event C pools are the structural
reason the app must window at 64 rows (medium).** `vtx_c_mixer.h:16, 22`;
finished one-shot voices keep their slots (`vtx_c_mixer.c:714-716`), so the
fast single-session path caps at 256 note events total. The capacity limit,
not the mixing math, dictates the export architecture. Fix under the freeze:
occupancy/rejection counters per window in export diagnostics to quantify
headroom for future window-size or capacity decisions.

**PERF-C4 — C render inner loop scans the full voice pool per output frame
with a per-sample helper call chain (medium; observation only, no DSP change
proposed).** `vtx_c_mixer.c:1754-1767` iterates every allocated slot per
frame including inactive/finished/not-yet-started voices; active voices pay
interpolation + ramp + a linear 12-point envelope scan + fadeout + two
pan-law gain calls per sample (`:1780-1792`). The VTX profile uses the linear
pan law, so the FT2 cos/sin cost does not apply to product export. Fix:
compile-time-optional visit counters only; any future call-granularity change
requires byte-identical WAV proof across the full fixture set.

**PERF-C6 — Scheduled-event queue is insertion sort with struct shifting plus
a compaction pass per schedule call (medium).** `vtx_c_mixer.c:1527,
1548-1556`: 72-byte events shift on middle insertion; the export schedules
updates grouped by effect type, so later types insert mid-queue — worst case
O(k²) moves with k up to 4096; per-tick effects push k into the thousands.
Fix: move counters first; then a Swift-side pre-sort of each window's updates
by frame (appends hit the no-shift path), proven byte-identical.

**PERF-C7 (low)** — per-window allocation churn: fresh zero-filled `[Float]`
per render (`CSoftwareMixer.swift:742`) although a zero-alloc `render(into:)`
exists (`:763`); a throwaway config-probe mixer allocating ~400 KB of
`VTXCMixerState` just to read its config
(`PlaybackSongOfflineRender.swift:648`); full-state memset per window
(`vtx_c_mixer.c:984`). Easy wins after instrumentation. **PERF-C8 (low)** —
the tool's `--window-rows` path accumulates whole-song PCM in memory
(`PlaybackSongOfflineRender.swift:644-645, 804`) while the app streams; keep
profiling comparisons on the same path. **PERF-A6 (low)** — render, encode,
and file I/O are fully serialized on one thread; defer pipelining until
instrumentation shows writer time matters.

### 4.3 Conceptual comparison with tracker-native exporters

From the public ft2-clone source (no code copied; public file names only):
its WAV render (`ft2-clone src/ft2_wav_renderer.c`) drives the **same
replayer tick loop as playback** on a background thread — a single pass that
fills one reusable ~2 MB chunk buffer (64 replayer ticks) per `fwrite`, with
song end detected live by the replayer, one gain scalar decided up front,
hard clamp at ±1.0 for float output, no second pass, no normalization, no
read-back. Its mixer (`ft2-clone src/ft2_mix.c`) is voice-major with 32.32
fixed-point stepping, run-length-limited branch-free inner loops, and sample
data referenced in place with pre-padded loop edges — zero allocation
anywhere in the audio path.

| Dimension | ft2-clone | VTX product export today |
|---|---|---|
| Passes over rendered audio | ~2 CPU touches, 1 file pass | ~9 CPU touches, 3 file passes |
| Scheduling | replayer-driven, live | fully pre-planned; whole-song rescan per 64-row window |
| Sample data | referenced in place | full PCM copied per voice per window |
| Mixer session | one, reused buffers | fresh mixer + buffers per window |
| Gain | fixed user amp, hard clamp | measured auto-headroom, second full-file pass (even at gain 1) |
| Progress | dirty-flag cursor, no % | deterministic %, throttled (better) |
| Threading | pauses live audio, mutates global song state | background queue, GUI-decoupled, atomic replace (better) |

Deliberately different and worth protecting (do not regress while
optimizing): deterministic pre-planned duration with validated WAV layout;
unclamped Float32 with measured auto-headroom and peak/RMS/overrange
diagnostics (ft2-clone hard-clips float output at ±1.0); real determinate
progress; atomic temp-file replacement; and offline rendering decoupled from
live playback state. The performance lessons are the structural ones already
captured above: skip the no-op gain pass, register sample PCM once and
reference it, bulk-encode, and make the windowed path consume precomputed
slices instead of rescanning.

## 5. CSoftwareMixer / MixerCore memory ownership and thread-safety audit

### What is sound

State ownership is clean and single-owner: each `CSoftwareMixer`
heap-allocates one `VTXCMixerState` (`CSoftwareMixer.swift:226` — the
documented GCD-stack-overflow avoidance), `vtx_c_mixer_init` zeroes the whole
struct (`vtx_c_mixer.c:984`), and `deinit` pairs `vtx_c_mixer_clear_voices`
with `state.deallocate()` (`:231-234`). Sample payloads are **copied, not
borrowed**: `vtx_c_mixer_add_sample_voice_internal` mallocs C-owned storage
and copies every frame before the Swift `withUnsafeBufferPointer` closure
returns (`vtx_c_mixer.c:819-825`; `CSoftwareMixer.swift:272-286`); envelopes
are copied into fixed 12-point arrays; voice release frees and zeroes the
slot, structurally preventing double-free. No borrowed pointer escapes closure
scope anywhere in the wrapper. `vtx_c_mixer.c` has no file-scope mutable
state, so the runtime core, the export's per-window mixers (background
queue), and the audition sink are fully disjoint instances. Bounds are
validated on both sides of the boundary. The runtime core's try-lock design
(`RuntimeCMixerRenderCore.swift:1019`; callback never blocks — stale-buffer
replay or zero-fill on `lock.try()` failure, counted) is deliberate and
mostly correct.

### Findings

**MIX-A1 — The CoreAudio render callback performs malloc/free and
whole-sample copies via C mixer voice lifecycle calls (high, verified
end-to-end from the AURenderCallback host).**
Files: `RuntimeCMixerRenderCore.swift`, `vtx_c_mixer.c`,
`CSoftwareMixer.swift`.
Why: the callback's own comment claims "no allocation-heavy work"
(`RuntimeCMixerRenderCore.swift:3483-3484`), yet scheduled adapter events are
applied inside the callback under the render lock: note triggers reach
`mixer.addVoice` (`:1566`) — a C malloc plus a per-sample sanitize copy of
the entire sample on the audio thread; note replacement calls
`mixer.rampDownVoices` (`:3630`), freeing completed voices; and the song-end
tail stop calls `mixer.clearVoices` (`:3139`), freeing up to 256 PCM buffers
plus four `Dictionary.removeAll` calls in one render quantum. The C header's
no-allocation guarantee covers only `vtx_c_mixer_render` itself
(`vtx_c_mixer.h:15`). Allocator contention or a large sample can blow the
render quantum and cause dropouts. This is a real-time-hygiene defect, not
memory unsafety — ownership remains correct throughout.
Fix (freeze-compatible): correct the callback-safety comment to state the
actual contract; add per-callback allocation diagnostics (in-callback
add/free counts, bytes copied) to the existing counters/snapshot; file voice
pool preallocation as future work behind tests. No DSP or scheduling change.
Tests: `RuntimeCMixerTests` — a scheduled note trigger inside a callback
window increments the new counters; song-end tail stop increments the free
counter; PCM bit-identical with instrumentation active.
Manual verification: play a module with large samples; correlate the existing
`callbackDurationWarningCount` with note-trigger-dense rows, then confirm the
new counters attribute them.

**MIX-A4 — The runtime snapshot hard-codes `callbackAllocationWarning: false`
and `callbackRealtimeSafeDiagnostics: true` (medium).**
`RuntimeCMixerRenderCore.swift:3863-3864` asserts as constants exactly the
property MIX-A1 shows is violated; anyone triaging dropouts from these traces
is misled. Fix: derive the flags from the MIX-A1 counters or rename them to
what they measure. Tests: snapshot reflects in-callback voice lifecycle
activity after a scheduled trigger; false for a pure-render session.

**MIX-A2 — C-status `precondition` aborts are reachable from the audio render
callback (medium).** `CSoftwareMixer.requireOK` (`:899-901`) turns
`VTX_C_MIXER_STATUS_VOICE_CAPACITY_EXCEEDED` (`vtx_c_mixer.c:812-813`) into a
process abort; runtime trigger paths use the aborting `addVoice`
(`RuntimeCMixerRenderCore.swift:1445, 1566`) while the offline path already
has a graceful `addScheduledVoiceWithResult` (`CSoftwareMixer.swift:336`).
Slot pressure is bounded in practice, but the failure mode is a hard abort on
the audio thread. Fix: `addVoiceWithResult` mirror + rejection counters at the
two runtime sites; rendered audio unchanged on every non-crash path. Tests:
saturate 256 slots, assert graceful rejection.

**MIX-A3 — The note-audition sink's render callback takes a blocking `NSLock`
also held during main-thread malloc/free (medium).**
`EditorNoteAuditionAudioSink.swift:282-292` blocks in the callback;
`cancelPreview` clears voices (C `free()`) under that lock while the output
unit still runs (`:257-267`); `replacePreview` does clear+add (free +
malloc/copy) under it (`:130-137`). Preview-only glitch risk — the sink is
isolated from playback by design. Fix: adopt the runtime core's try-lock +
zero-fill pattern, or stop the unit synchronously before mutating. Tests: hold
the lock, invoke render, assert zero-filled output instead of blocking.

**MIX-A5 — No teardown-during-render, true-concurrency, or payload-lifetime
tests exist for the mixer stack (medium).** The 367 tests across
`CSoftwareMixerTests`/`RuntimeCMixerTests` are strong on DSP parity and
determinism, but lock-contention coverage is single-threaded simulation
(`withRenderLockHeldForTesting`), and nothing tears down a core mid-render on
another thread or pins the payload-copy guarantee explicitly. Fix
(test-only): payload-lifetime test (scoped array freed before render, ASan),
two-thread render/configure stress (TSan), teardown-during-render test.

**Lows:** **MIX-A6** — the lock-failure stale-buffer replay reads
`lastCallbackOutputInterleavedPCM` unsynchronized (`:3501-3506, 4389`), safe
only via an undocumented audio-thread-single-writer invariant; document it and
add a DEBUG same-thread assertion. **MIX-A7** — `vtx_c_mixer_init` on an
already-loaded state would leak voice PCM (memset without free,
`vtx_c_mixer.c:984`); safe today by single-caller convention; add a header
contract comment. **MIX-A8** — zero-frame voices occupy immediately-reusable
slots (`vtx_c_mixer.c:714-716, 724-731`), so a held index can silently alias
a new occupant; document + regression-test the current semantics.

## 6. Unified Audio Export architecture recommendation

Grounding: the app ships exactly one pipeline — whole-song Float32/48 kHz WAV
through `WAVExportCoordinator` (plan via traversal + Fxx timing at `:369-397`;
windowed streamed render to an unscaled temp at `:455-481`; streamed headroom
post-process at `:496-514`). The tool exercises a richer surface (order
ranges, solo filter, pcm16/float32, gain/headroom flags) but duplicates the
duration planning shell and uses a different in-memory pipeline
(`BoundedXMRenderTool.swift:701-717`). The key enabler: **every future
feature is reachable without touching the render core** —
`PlaybackSongOfflineRenderRequest` already carries
`startOrderIndex`/`orderCount` and an `isolationFilter`
(`PlaybackSongOfflineRender.swift:39-45`), and the channel-mute adaptation
already exists in the plan layer (`plan(mutingEventsNotIn:)` /
`includedEventIndices`, `PlaybackSongOfflineRender.swift:947-957`).

Recommended shape (all export-layer; render core, DSP, parser untouched;
loaded modules read-only; Save/Save As stay disabled). This design was
adversarially critiqued during the audit; the corrections are incorporated:

- **Extend the existing types rather than inventing a parallel family.**
  Grow `WAVExportScope`, `WAVExportConfiguration`, and the headroom policy in
  place; introduce a multi-pass plan type only in the stems PR where a second
  pass first exists. A generic ExportRequest/ExportPlan/phase-weight family up
  front is over-engineering for a solo-maintainer alpha.
- **Shared render configuration, split in two steps.** 1a: extract the
  duration/tail/window planner shell (song-end frames + tail + overflow
  combine + the triplicated `frameCount` helper) inside the app target with a
  golden plan-values test; resolve the tail coupling explicitly —
  `RuntimeCMixerSongEndTailPolicy` lives in `AudioBackendSelection.swift`,
  which is excluded from the SwiftPM target (`Package.swift:64`), so either
  move the default-tail constant into the shared configuration and have the
  runtime policy consume it, or keep two constants with a cross-check test
  (state which in the PR). 1b: the tool adopts the shared planner. App
  (48k/float32/3s/64-row/auto) and tool (44.1k/pcm16/0s) defaults become two
  named profiles of one type.
- **Encoder seam.** Keep the shipped two-stage pipeline: stage one renders
  once to the unscaled Float32 temp with peak diagnostics; stage two becomes
  an `AudioExportEncoder` consuming that stream plus the resolved gain.
  Float32 WAV wraps `writeFloat32WAVApplyingGain`; PCM16 reuses the existing
  quantizer; AAC/M4A is an AVAssetWriter/ExtAudioFile conformance over the
  same scaled stream. Fix both error layers in the same PR: a
  `.formatUnsupported` plan error (today a non-float32 config throws
  `wavFileTooLarge` — `WAVExportCoordinator.swift:360-362`) and
  `formatUnsupported`/`encodeFailed` cases in `WAVExportFailure` (`:153-155`).
- **Cancellation first — it is independent of everything else and the
  highest user-value gap (EXP-3, medium).** Export runs detached with a
  titled, button-less sheet (`AppDelegate.swift:347, 2277`); the needed seams
  already throw (`PlaybackSongOfflineRender.swift:937`;
  `SoftwareMixer.swift:777`). Add an atomic token checked in both progress
  closures, a dedicated cancellation error mapped to a **new `.cancelled`
  completion case** (today's taxonomy would misreport a cancel as
  `renderFailed` with a failure alert), silent-dismiss UI, temp cleanup, and
  a stated latency bound (one window / one chunk). Fold in the weighted-phase
  progress model (EXP-4) so the bar stops resetting between phases.
- **Disk-space preflight** (missing from the current pipeline): export holds
  raw temp + final temp beside the destination simultaneously
  (`WAVExportCoordinator.swift:445-448, 594-598`), so peak disk is ~2× file
  size (~1.6 GB at the 100M-frame cap) — more for stems/AAC. Add a typed plan
  error when free space is insufficient.
- **Order-range export** is plan-layer only (EXP-5): add
  `.orderRange(Range<Int>)`, thread the range through the existing request
  initializers, and add a range-scoped counterpart to
  `validateWholeSongTraversal` (`:610`) accepting range-exhausted stop
  reasons. Define pattern scope precisely as "pattern at a given order
  position" (or synthesize a one-order in-memory song for unreferenced
  patterns) — the request type cannot express an arbitrary pattern index.
- **Stems** (EXP-6): N mute-configured full render passes via
  `PlaybackSongRenderIsolationFilter(soloChannelIndex:)` — zero C changes.
  Honest cost statement: **N+1 whole-song renders** under shared gain (the
  master pass resolves the auto-headroom gain all stems reuse; per-stem
  headroom would destroy inter-channel balance). The acceptance test is a
  tolerance-based null of summed stems against the master (float summation
  order differs; bit-exact is impossible) with a stated epsilon.
- **One facade, explicitly scheduled.** An `AudioExportPipeline` in the
  shared target serves the app coordinator and, in its own PR with a
  pre-registered byte-equivalence test (windowed-streaming vs the tool's
  in-memory path, pcm16 + float32, public fixture), the tool internals behind
  an unchanged CLI. Until that PR lands, EXP-7 (two pipelines for the same
  operation) is accepted-for-now, not solved.
- Remaining export findings: **EXP-8 (low)** — `sanitizedFilenameBase` and
  destination normalization duplicated verbatim between
  `ExportXMCoordinator.swift:202` and `WAVExportCoordinator.swift:580`; fold
  into a shared destination helper during the encoder-seam PR. **EXP-9
  (low)** — `WAVExportPlan` is `@unchecked Sendable` (`:131`) across the
  background hop; make the plan properly Sendable when it grows for
  multi-pass work. User-selectable gain/headroom needs no new machinery:
  `MixerWAVExportPolicy` already models fixed gain and dB headroom
  (`SoftwareMixer.swift:443-448`); UI is the only missing layer.

Sequenced export PR plan (each independently shippable):
1. Cancellation + `.cancelled` + Cancel UI + weighted continuous progress.
2. Shared duration/tail/window planner, app-side (1a), then tool adoption (1b).
3. Encoder seam + both error-layer fixes + shared destination helper.
4. PCM16 product export (first second format through the seam) + gain/headroom UI options.
5. Order-range export + range traversal validation.
6. (Demand-driven) stems: plan expansion, N+1 cost note, shared master gain, tolerance null test.
7. (Demand-driven) AAC/M4A encoder conformance.
8. Tool adopts `AudioExportPipeline` behind its CLI, gated on the pre-registered equivalence test.

## 7. Instrument/Sample Editor pre-implementation design review

The foundation is closer to editor-ready than expected in one important way:
**the instrument/sample model is already a pure Swift value model.** The C
parser boundary carries no instrument payloads (`module_types.h:47, 70` hold
only a first-instrument name and MOD first-sample metadata); instruments and
samples are decoded by a Swift byte reader (`PlaybackSongBuilder.swift:82-191`)
into Equatable structs (`PlaybackModel.swift:11, 166`) that `EditableXMWriter`
consumes directly. The recommended editing model is therefore the existing
`PlaybackInstrument`/`PlaybackSample` value types extended with copy-with
helpers and missing fields — not a parallel model with C-struct conversion.
The C core needs no changes, which keeps all editor work inside the freeze.

### Seams that must exist before editor UI

**EDT-A1 — No undo architecture exists anywhere in the document layer
(high, verified; both editor design docs require it).**
Files: `AppDelegate.swift`, `BlankTrackerDocument.swift`,
`docs/design/sample-editor-window.md`,
`docs/design/instrument-editor-window.md`.
Why: `sample-editor-window.md:115` mandates that each destructive op pushes a
single atomic undo step; `instrument-editor-window.md:150-151` routes edits
"through the existing document command layer" — which does not exist. A
repo-wide search finds zero `UndoManager`/`registerUndo` usage. The editable
document is a bare optional on the app delegate reassigned directly at ~13
sites (`AppDelegate.swift:12, 407, 514, ...`); the only existing funnel is the
narrow song-order path (`applyEditableSongOrderDocument`, `:732`), which has
no undo. Landing editors on this invites unrecoverable destructive sample
edits.
Fix: an `applyEdit(label:)` funnel owning all document replacement,
registering whole-document value snapshots with `NSUndoManager` (the document
is an Equatable value type; PCM arrays are CoW-shared, so snapshots are
cheap). Set an explicit `levelsOfUndo` cap (e.g. 20) so destructive PCM edits
cannot accumulate unbounded snapshots. Scope discipline: the first PR routes
only **new** instrument/sample mutations through the funnel; migrating the ~13
existing pattern-edit write-back sites is a separate mechanical PR — it is a
wide `AppDelegate` refactor, not a narrow slice.
Tests: undo/redo pairs registered; undo restores the exact prior document
value; PCM storage shared across snapshots; migrated sites keep value-equality
behavior.
Manual verification: enter a note, Cmd+Z, cell and control panel revert; redo
restores.

**EDT-A3 — The editable model cannot represent the instrument editor's
required v1 fields: sample panning, panning envelope, autovibrato (high,
verified).**
Files: `PlaybackModel.swift`, `PlaybackSongBuilder.swift`,
`EditableXMWriter.swift`, `docs/design/instrument-editor-window.md`.
Why: the design requires volume+panning envelopes, vibrato
type/sweep/depth/rate, and default pan (`instrument-editor-window.md:91-93`).
`PlaybackSample` has no panning field (`PlaybackModel.swift:11-26`); the
loader skips the panning byte at sample-header offset +15
(`PlaybackSongBuilder.swift:293-304`); the writer hardcodes center pan
(`EditableXMWriter.swift:345`), zero-fills the 48-byte panning-envelope block
(`:522`), and writes four zero bytes for vibrato (`:533-536`). Notably the
writer throws typed errors for other unsupported features but silently
normalizes these — so editable copies of loaded modules already re-export
with silent divergence (see INV-B2), and binding an editor to this model
would ship data loss.
Fix, split into three deliberate round-trip slices (0a sample panning, 0b
panning envelope, 0c autovibrato), each touching model + loader + writer +
round-trip tests. Two explicit callouts per slice: (1) Export XM bytes change
for already-loadable modules (replacing hardcoded values) — update pinned
writer tests deliberately; (2) new model fields must be **runtime-inert** —
add a regression test asserting `PlaybackSongAdapter` voice construction is
identical for two songs differing only in the new fields, which is the
concrete guard for the no-playback-change guardrail during model extension.
Manual verification: load a fixture with sample panning set, Make Editable
Copy, Export XM, verify panning survives in another tracker.

**EDT-A2 — No instrument/sample mutation seam or policy exists (medium;
downgraded on verification — total immutability is currently the *strongest*
enforcement of read-only, so this is scheduled debt, not a defect).**
`instrumentPalette` is a `let` threaded verbatim through every rebuild
(`BlankTrackerDocument.swift:655, 1191`); `EditorPatternMutationPolicy`
(`:222-231`) has no instrument analog. Fix: `updateInstrument`/`updateSample`
mutating funcs + copy-with helpers + an `EditorInstrumentMutationPolicy`
mirroring the pattern policy (editable documents yes, loaded modules no,
playback-active no — see EDT-A6).

**EDT-A4 — The writer's source-provenance guard makes editor-created,
generated, or imported samples unexportable (medium; a documented, deliberate
first-export scope decision that must be revisited before sample creation
ships).** `EditableXMWriter.swift:266-269` requires XM-derived provenance
flags that generators and WAV import can never produce. Fix: replace the
guard with an explicit per-sample export-encoding policy (preserve source bit
depth when provenance exists; default 16-bit signed delta otherwise), keeping
provenance as a diagnostic; tests prove XM-derived samples still round-trip
byte-identically.

**Remaining editor findings (medium unless noted):**
- **EDT-A5** — edits can silently leave the exportable subset; writer limits
  surface only at export time. Correction from verification: only the
  12-point envelope count throws (`EditableXMWriter.swift:238-243`); marker
  indices are silently zeroed (`:574-579`) and tick monotonicity is checked
  nowhere — which makes edit-time validation the *only* enforcement point,
  strengthening the case for a validating envelope-editing type (≤12 points,
  non-decreasing ticks, valid markers).
- **EDT-A6** — the pattern-loop refresh pushes the full rebuilt song,
  palette included, into the live engine (`AppDelegate.swift:1704`); today
  benign (palette immutable), but the moment a palette mutation API exists
  this becomes a runtime-playback leak. Land the palette-equality regression
  test **before** the mutation API, and gate palette mutation on stopped
  playback (mirroring `LoadedModuleEditableCopyCoordinator.swift:109-110`).
- **EDT-A7** — `canMakeEditableCopy` runs the full copy construction plus a
  complete `EditableXMWriter` serialization (delta-encoding every sample
  payload) during menu validation. (An audit-internal critique disputed this;
  direct code inspection confirms it: `unavailableReason` →
  `makeSupportedEditableCopy` → `_ = try EditableXMWriter().data(from:)`,
  called from `validateMenuItem` via `AppDelegate.swift:125-126`.) Fix: cache
  the verdict keyed on loaded-module identity, or use a cheap structural
  precheck for validation and keep the writer-backed dry-run at action time —
  with the INV-D1 equivalence test so availability and export can never
  disagree.
- **EDT-A8** — the audition path cannot express envelopes although the
  preview mixer already supports them (`EditorNoteAuditionAudioSink.swift:131-137`
  passes no envelope; `CSoftwareMixer` accepts `volumeEnvelope`/`panEnvelope`).
  Envelope edits would be inaudible in audition — schedule the preview-layer
  extension right after the envelope editor phase.
- **EDT-A9** — every audition keydown copies + sanitizes the full sample PCM
  into the descriptor (`BlankTrackerDocument.swift:840, 404`;
  `AppDelegate.swift:1772`); cache one sanitized descriptor per selection,
  invalidated by `applyEdit`, or explicitly accept the cost for v1.
- **EDT-A10** — `PlaybackSample` permits internally inconsistent coupled
  fields (`sampleLength` vs `pcm.count`, loop fields) that the writer rejects
  only at export (`EditableXMWriter.swift:294-301`); add validated
  `withEditedPCM` copy-helpers that derive length and re-clamp loops, and
  route all sample ops through them.
- **EDT-A11 (low)** — instrument/sample payloads come from a second,
  Swift-side XM byte parser rather than the C core; convenient for editors,
  but see INV-C1 for the drift risk. Docs note: the Swift loader is the
  canonical instrument-ingestion path for editor work.

### Recommended editor architecture and phasing

Undo: document-level value snapshots via `NSUndoManager` behind the
`applyEdit` funnel — not granular commands (the document is replaced
wholesale per mutation; snapshots are Equatable-comparable; CoW keeps them
cheap; granular inverse-op bookkeeping buys nothing at this document size).
Each destructive sample op = one atomic undo step, multi-level with a capped
depth. Sample edits: in-place destructive with undo snapshots
(non-destructive layering conflicts with the XM export model), through the
EDT-A10 validated helpers. Envelope editing: bind to `PlaybackVolumeEnvelope`
through the EDT-A5 validating wrapper. Audition: reuse the isolated
`EditorNoteAuditionAudioSink` seam; editors depend only on the sink protocol,
never `PlaybackEngine`. UI shell: follow the `SongOrderEditorWindowController`
panel pattern and the existing `VTXEditorControlFactory` primitives; note
that knob double-click numeric entry is still deferred in the control
vocabulary while the instrument editor design assumes it — include it in the
shared-controls phase.

Phases (each a narrow freeze-compatible slice): 0a/0b/0c model field slices
(panning, panning envelope, autovibrato) with runtime-inert tests → undo
funnel (new mutations only) → palette mutation API + policy + playback gate →
instrument window shell, read-only → name/defaults editing → envelope canvas
read-only, then editing behind the validating type → audition envelope
passthrough → sample window shell + min/max-scan waveform read-only →
loop/params editing → destructive ops with undo → 7a writer encoding policy,
7b generators, 7c WAV/AIFF import *only after* a written base-sample-rate
policy (the loader currently fixes 8363 Hz — what happens to a 44.1 kHz WAV
must be decided, along with an import size cap and decode-error surface).
Invariant guards to land first: instrument mutation policy tests (read-only
loaded modules), palette-equality-during-refresh test (no runtime change),
runtime-inert-fields test, and export-subset validation at edit time.

## 8. Parser / writer / editable-copy / export invariant risk audit

### Where the invariants actually live

Mostly in real code, not convention: loaded-module read-only editing is a
runtime policy check (`EditorPatternMutationPolicy.canMutatePattern` returns
false for `.loadedModule`, `BlankTrackerDocument.swift:222-229`) pinned by
tests; Export XM refuses read-only and playing contexts and re-checks at
`beginExport` rather than trusting menu state
(`ExportXMCoordinator.swift:141-159`); the editable copy is untitled and
in-memory by construction (`BlankTrackerDocument.swift:738-741`); WAV export
renders from an in-memory snapshot and writes only destination-adjacent temp
files. A quiet structural guarantee worth stating explicitly: **no export or
copy context type carries a source URL** — that, more than the disabled menu
items, is what keeps sources safe. The weakest enforcement is Save/Save As
(INV-C3 below). One boundary note: after Make Editable Copy, a user can
still point the Export XM save panel at the original file and overwrite it
with the lossy subset export — the source is protected by the user's
destination choice, not by the app.

### Findings

**INV-A1 — XM order-table `memcpy` can read up to 256 bytes out of bounds on
hostile header sizes (high, verified; reachable from every File > Open).**
Files: `core/ModuleCore/src/xm_header.c`, `tests/core/ModuleCoreTests.swift`.
Why: the parser rejects `header_size < 20` (`xm_header.c:114`) and checks
`size >= 60 + header_size` (`:117-119`), then unconditionally copies
`song_length` bytes (clamped only to 256) from offset 80 (`:139-143`) with no
check against `header_size - 20` or `size - 80`. A crafted 80-byte file with
`header_size = 20` and `song_length = 256` drives `memcpy` fully out of
bounds (the parse buffer is malloc'd at exactly file size,
`module_types.c:65-80`) — crash or heap-bytes leak into the order table on
open. `ModuleCoreTests` exercises only well-formed fixtures.
Fix (narrow validation, explicitly permitted under the freeze): clamp
`order_table_length` to `min(MC_MAX_ORDER_ENTRIES, header_size - 20,
size - 80)` before the copy. No behavior change for standard files
(`header_size` = 276 = 20 + 256).
Tests: the crafted 80-byte file parses without OOB (run under ASan) with an
empty order table; truncated-mid-table fixture rejected or clamped; normal
fixture unchanged.
Manual verification: ASan build of the ModuleCore tests + `mc_dump` on the
crafted file; before the fix ASan reports heap-buffer-overflow read.

**INV-B1 — Editable copy silently converts Amiga-frequency-table modules to
linear on playback and export (high, verified).**
Files: `BlankTrackerDocument.swift`, `EditableXMWriter.swift`,
`LoadedModuleEditableCopyCoordinator.swift`.
Why: loaded-module playback honors the flag
(`ModuleMetadataLoader.swift:46-47`;
`PlaybackSongAdapter+PitchEffects.swift:2397`), but the editable document has
no flags field: metadata hardcodes `xmFlags: 0x0001`
(`BlankTrackerDocument.swift:781`), `EditablePlaybackSongBuilder` hardcodes
linear (`:1418`), and the writer emits that flags word
(`EditableXMWriter.swift:79`). The representability gate checks only
type/patterns (`LoadedModuleEditableCopyCoordinator.swift:118`), so an
Amiga-table XM converts successfully, then plays and re-exports with
different 1xx/2xx/3xx pitch math than the source — silent semantic loss at
the one sanctioned conversion boundary, with no test or doc naming it.
Fix: gate at the copy boundary — return `.unsupportedLoadedModule` when
`!metadata.usesLinearFrequencyTable`, with the limitation named in the
message. (Carrying the flag through the document is the eventual fix but
touches editable-playback semantics; the gate is the minimal freeze-safe PR.)
Tests: Amiga-flag context refused; linear context still copies; writer
contract test pinning the flags word.
Manual verification: Make Editable Copy on an Amiga-table XM → today the
export shows Linear in another tracker and slides sound different; after the
gate the command is disabled with a reason.

**INV-A2 — Unvalidated XM `row_count`/`channels` allow multi-billion-iteration
parse loops (medium; open-file DoS).** `xm_header.c:132` (channels uncapped),
`:169` (row_count uncapped), `:183-184` (full iteration even when
`packed_size == 0` consumes nothing). A small file declaring many
64-KB-row × 64-K-channel empty patterns turns File > Open into a hang. Fix:
reject channels 0/>64 and row_count >256, matching the writer's own ceilings.
Tests: hostile fixtures fail fast; goldens still parse.

**INV-B2 — Editable-copy export silently drops sample panning, panning
envelopes, autovibrato, empty-slot keymap targets, and sample-less instrument
names (medium).** Same mechanism as EDT-A3, plus `EditableXMWriter.swift:211`
(empty-PCM slots dropped), `:359` (keymap remapped to sample 0), and
`PlaybackSongBuilder.swift:124-126` (sample-less instruments never enter the
palette). The representability dry-run passes for all of these, so the app
reports "convertible" while the export audibly diverges; docs say only "not a
full round-trip guarantee" without enumerating the lossy fields. Fix
(docs-first): enumerate the dropped/regenerated fields in
`docs/agent-current-state.md` and the user-facing copy/export messaging; add
pinning tests so any change to the lossy set is deliberate. Model support is
the EDT-A3 slices.

**INV-B3 — The parser warning channel is dropped, and the 2048-event
truncation fallback can silently feed playback and editable copies
(medium).** `module_types.h:19` caps captured events; `xm_header.c:223-229`
records the truncation only in `info.warning`, which the app never reads
(`ModuleMetadataLoader.swift:109-110` reads only `info.error`); when the
Swift full-file pattern re-parse fails, `parseXMPatterns` silently falls back
to the truncated list (`:312-315`). Fix: carry `info.warning` into
`ParsedModuleMetadata` plus a `patternsSource` flag; treat truncated-source
patterns as unsupported for editable copy; log the warning on load. Related
**INV-D2 (low)**: MOD detection accepts any four printable signature bytes
with a warning the app also never surfaces (`mod_header.c:19-27, 87-89`).

**INV-C1 — Three independent XM binary parsers must agree by convention;
divergence degrades silently (medium).** The C header/pattern parser
(exact-packed-size strictness, `xm_header.c:234`), the Swift pattern parser
(`ModuleMetadataLoader.swift:387-459`, no such check), and the Swift
instrument walker (`PlaybackSongBuilder.swift:82-191`, returns an empty
palette on any structural mismatch — the module loads silently with no
instruments). Fix: a cross-parser consistency test running every checked-in
fixture through all three and asserting agreement on pattern counts, rows,
events, and non-empty palettes; an AGENTS.md note that XM structure-walking
changes must touch all three sites plus this test.

**INV-C2 — Editable vs read-only document kind is derived from an
optional-pair convention repeated in three context builders (medium).**
`blankDocument != nil && loadedMetadata == nil` re-derived at
`AppDelegate.swift:275, 292, 379` with exclusivity maintained by hand at
every mutation site. A future path that sets both, or forgets to clear one,
silently flips a read-only module into an exportable context with no test
failure. Fix: one `currentDocumentState()` enum
(none/editable/loadedReadOnly) used by all context builders, with a debug
assertion that both optionals are never simultaneously non-nil.

**INV-C3 — Save/Save As stay disabled only via menu construction (medium).**
`ApplicationMenuBuilder.swift:70-73` builds nil-action disabled items, pinned
by menu tests — one surface. `EditableXMWriter`/`ExportXMCoordinator` will
serialize any document to any URL; the real protection is that no context
type carries a source URL, and that property is implicit and undocumented. A
future "save back" convenience threading the opened file's URL into an export
call would violate the read-only guarantee without failing any test. Fix:
an AGENTS.md invariants section (Save disabled; no export/writer context may
gain a source-path field; Make Editable Copy is the only conversion) plus a
context-shape test asserting no URL-typed members, so adding one is a
deliberate act.

**INV-D1 (low)** — the representability check honestly dry-runs the real
writer, which is a *strength* (availability and export cannot disagree); the
risk is a future "optimization" replacing it with a divergent cheap check.
Guard: an equivalence test that `canMakeEditableCopy == (makeEditableCopy
succeeds)` across supported and unsupported fixtures. The menu-validation
cost angle is EDT-A7.

Most likely future wrong turns, each with its cheap guard: wiring Save to the
writer (AGENTS.md note + context-shape test); the copy claiming the source
path for filename convenience (pinned untitled + doc note); replacing the
writer-backed dry-run (equivalence test); raising `MC_MAX_XM_EVENTS` or
"simplifying" one of the three parsers alone (cross-parser fixture test);
extending the document assuming `xmFlags` round-trips (it does not — INV-B1).

## 9. General code quality and documentation audit

### What is healthier than expected

Zero TODO/FIXME/HACK markers in active source, and the docs-tracked-deferral
convention genuinely holds. The retired AVAudio backend is deleted, not
parked (only doc comments and a guard test remain). Environment-variable
control flow is funneled through injectable `resolve(environment:)` value
types (`AudioBackendSelection.swift:43`) and documented. The WAV header is
not duplicated (the stream writer reuses the exporter's header code,
`SoftwareMixer.swift:1107`); there are no duplicated Swift/C period tables;
notification coupling is minimal. All shell scripts use `set -euo pipefail`
with quoted expansions and mktemp/trap cleanup — no guard script can silently
pass.

### Findings

**QLT-2 — The render tool's 109-test suite never executes in CI (high,
verified).** `basic-checks.yml:41` runs only `swift test --filter
ModuleCoreTests`; the Xcode step tests only the app scheme (whose shared
scheme's Testables contain only `VoodooTrackerXTests`); `release.yml` runs no
tests. `VTXRenderBoundedXMTests` (4,587 lines, 109 tests pinning the proven
render path, CLI parsing, export policy, diagnostics JSON) compiles but never
runs on PRs, and `docs/testing.md` never mentions it. Green CI falsely
implies the reference render path is protected.
Fix: add `swift test --filter VTXRenderBoundedXMTests` (or drop the filter)
to `basic-checks.yml`; document the command. Verify by breaking one assertion
on a scratch branch and watching CI fail.

**QLT-1 (medium)** — the duplicated windowed render loops; consolidated into
PAR-1/PAR-2 above. **QLT-3 (medium)** — the frame-math rounding drift;
consolidated into PAR-4 (one nuance kept: if aligning the app's rounding to
the tool's is considered runtime-adjacent under the freeze, land the shared
helper with the app's current rounding and converge at freeze exit).

**QLT-4 — `SoftwareMixer.swift` is misnamed: it hosts the live product WAV
export machinery alongside the retained reference mixer — the repo's top
deletion-bait file (medium).** `docs/architecture.md:199` calls
`SoftwareMixer` "the Swift reference/spec mixer", but 1,259 of 1,466 lines
are live shared infrastructure: `MixerRenderConfig`, `MixerWAVExportPolicy`
(auto-headroom math, `:455`), `MixerWAVExporter` (`:624`),
`MixerFloat32WAVStreamWriter` (`:1074`) — all load-bearing for product
export. The reference mixer class itself (`:1260`) is referenced outside the
file only by test cross-validation (`TestSupport.swift:1106`, used 22× in
`CSoftwareMixerTests` — it must be *split*, never deleted). An agent told to
"clean up the retired Swift mixer" — plausible given the retired-AVAudio
history — would gut the product export.
Fix: pure file split (Mixer types + WAV export machinery out; reference mixer
stays), update `Package.swift:132` and one sentence in
`docs/architecture.md`. Existing suites cover every moved type.

**QLT-5 — The Package.swift shadow target compiles 23 hand-listed app files
into the tool; the rule is undocumented (medium).** `Package.swift:45-137`:
target rooted at `"."` with a 49-entry exclude list. Referencing an app-shell
type (e.g. `WAVExportCoordinator`, excluded at `:74`) from a shared file
breaks `swift build` while Xcode stays green; CI catches the compile break,
but nothing explains the rule, so agents will discover it by CI failure and
may "fix" it by hacking the lists. Fix: expand the one-line comment into the
classification rule and add a matching AGENTS.md bullet.

**QLT-6 — AppDelegate is a ~2,350-line, ~118-function god object with no
direct test coverage (medium).** Heavy logic is correctly delegated to
tested coordinators; the glue (validation ordering, coordinator handoffs,
fifteen `songOrderEditor*` actions, a nested progress-sheet class at
`:2268`) is testable only by launching the app. Fix: extract the song-order
command cluster into a small controller mirroring the coordinator pattern —
one narrow PR, not a rewrite.

**QLT-7 — `BoundedXMRenderTool.swift` (5,713 lines) is dominated by a
4,270-line diagnostics JSON exporter with a ~725-line function (medium).**
`PlaybackSongDiagnosticsJSONExporter` spans `:1089-5365`; `jsonObject` alone
runs `:1538-2263`. Fix: pure file move of the exporter into its own file
(+ `Package.swift` sources entry); decompose `jsonObject` later behind the
existing JSON-shape tests (which QLT-2 must first make CI-real).

**QLT-8 — Release-status and WAV-export facts are restated across five docs
and have already drifted against the git tag (medium).** `v0.2.0-alpha.4` is
a tag, yet `docs/roadmap.md:12` and `docs/agent-current-state.md:20` still
say "prepared"; the export-pipeline paragraph is quadruplicated
(`agent-current-state.md:52-58, 186-203`; `README.md:123-130`;
`roadmap.md:16-20`). Fix: fix the two stale sentences; declare
`agent-current-state.md` the single owner of release status and export
behavior; replace copies with pointers.

**Lows:** **QLT-9** — `RuntimeCMixerRenderCore.swift` (4,577 lines, 27
types, one 3,559-line `@unchecked Sendable` realtime class) — split only the
supporting value types; do not restructure the class under the freeze.
**QLT-10** — `AudioEngine.swift` is a 12-line protocol file whose name
implies the deleted engine; `AGENTS.md:13` cites `docs/format-changes.md`,
which does not exist; sync-critical twin sites (the windowed renderers, the
frame math) carry no keep-in-sync breadcrumbs — the one weakness of the
zero-TODO convention. Also low, from the completeness pass: the
runtime-behavior-shaping diagnostic env keys in `AudioBackendSelection.swift`
(runtime sample-rate override at `:87`, minimal-callback and trace toggles at
`:200-205`) are not inventoried in the docs that list the other `VTX_*`
flags; they alter the very callback behavior the mixer audit examined and
belong in the documented flag table. (Docs cover ~20 of ~25 distinct keys.)

## 10. Suggested narrow PR sequence

Ordered so that measurement precedes optimization, safety precedes features,
and every optimization lands behind a byte-identity or determinism test. Each
is a small, independently shippable PR.

1. **ci: run the render tool test suite** — add `VTXRenderBoundedXMTests` to
   `basic-checks.yml`; document in `docs/testing.md` (QLT-2). Unlocks trust
   in every later render-path refactor.
2. **core: harden XM header parsing against hostile files** — order-table
   clamp + channels/row_count caps + ASan-verified hostile-input tests
   (INV-A1, INV-A2). Narrow validation, no parser architecture change.
3. **audio-export: add render/export performance instrumentation** — phase
   timers + os_signpost + payload-byte and occupancy counters on the existing
   per-window diagnostics (PERF-A4/C5, PERF-C2 step 1, PERF-C3, PERF-C6
   counters). Output-neutral by construction; every later perf PR cites its
   numbers.
4. **docs: performance measurement policy** — Release-build requirement for
   timings, `swift run -c release` in the render workflow docs,
   `scripts/bench-render.sh`, Debug-binary warning in the metrics script,
   `SWIFT_COMPILATION_MODE = wholemodule` pinned in Release (PERF-B1/B2/B3/B5).
5. **audio-export: pin app-vs-tool parity, then collapse the duplicated
   windowed loops** — byte-equality parity test first, then extract the
   shared per-window core behind it (PAR-2, PAR-1/QLT-1).
6. **audio-export: share render configuration between app export and render
   tool** — duration/tail/window planner + `frameCount` helper + shared cap
   constant + product-export profile flag, app-side first then tool adoption
   (PAR-3/4/6, EXP planner extraction; tool stop-reason diagnostics from
   PAR-5 ride along).
7. **audio-export: WAV writer bulk encode + unity-gain fast path** —
   `withUnsafeBytes` bulk conversion, vectorized peak/RMS, drop the redundant
   gain-pass copies, file-move short-circuit at gain 1.0; byte- and
   diagnostics-identity goldens gate it (PERF-A1, PERF-A2).
8. **audio-export: pre-indexed per-window scheduling** — bucket events and
   step updates once per export; window loop consumes slices; call-sequence
   and determinism tests prove bit-identical PCM (PERF-A3/C1). Buffer-reuse
   via `render(into:)` and the config-probe removal ride along (PERF-C7).
9. **audio-export: cancellation + `.cancelled` + continuous weighted
   progress + disk preflight** (EXP-3/EXP-4 + the preflight gap).
10. **app: gate Amiga-frequency-table modules at the editable-copy boundary
    and enumerate the lossy export fields** (INV-B1, INV-B2 docs+pins;
    surface the parser warning channel, INV-B3).
11. **mixer: real-time contract truth** — corrected callback comment,
    in-callback allocation counters wired to the snapshot flags,
    result-returning `addVoice` at the two runtime trigger sites,
    sanitizer-backed lifetime/teardown tests (MIX-A1/A2/A4/A5).
12. **audio-export: surface windowed boundary-cut diagnostics in the export
    result and update ADR 006** (PAR-8).
13. **app: cheap menu-validation checks** — structural prechecks for Export
    WAV and Make Editable Copy validation; full plan/dry-run only at action
    time, with the availability/action equivalence test (PERF-A5, EDT-A7,
    INV-D1).
14. **quality: de-trap the tree** — split `SoftwareMixer.swift` (QLT-4);
    move the diagnostics JSON exporter out of `BoundedXMRenderTool.swift`
    (QLT-7); document the shadow-target rule (QLT-5); fix doc drift and
    single-source the release status (QLT-8); AGENTS.md invariants section +
    context-shape test (INV-C3); `currentDocumentState()` consolidation
    (INV-C2).
15. **instrument: editor foundations** — the EDT phase-0 sequence: model
    field slices 0a/0b/0c with runtime-inert tests, `applyEdit` undo funnel,
    palette mutation API + policy + playback gate, then the editor shells
    (EDT-A1/A2/A3/A5/A6, section 7 phasing).
16. **audio-export: encoder seam + PCM16 + gain/headroom UI**, then
    order-range export; stems and AAC/M4A remain demand-driven follow-ups
    (section 6 plan).
17. **repo/docs follow-ups** — decide `legacy/` retirement (historical
    reference only; not audited), create or re-point `docs/format-changes.md`
    (QLT-10), inventory the remaining diagnostic env keys, and schedule the
    deferred read-only audit of `PlaybackEngine.swift` (section 11).

Items 1-4 are collectively small, carry near-zero risk, and convert every
subsequent performance claim in this report from "complexity-shape argument"
into "measured number".

## 11. Items explicitly not audited

- `legacy/`, `.build/`, `build/`, `build-release/`, `dist/`, DerivedData,
  and generated artifacts — out of scope by design. `legacy/` is historical
  reference only; the only recommendation is to decide its retirement
  explicitly (PR sequence item 17).
- **`PlaybackEngine.swift` (2,344 lines)** — identified by the completeness
  pass as the one file matching the audit's overlarge-file and thread-safety
  criteria that no auditor inspected (it contains a background prewarm
  scheduler declared `@unchecked Sendable` at `:71`, a blocking
  `waitForResult()` join at `:23`, and multiple runtime timers). Recommended
  as a dedicated read-only follow-up audit; nothing in this report depends on
  its contents.
- Runtime DSP correctness, effect parity, and the tracker viewport — frozen
  and covered by prior reports (`docs/reports/`); this audit treated the DSP
  as a black box and proposed no output-changing modifications.
- The `PlaybackSongAdapter+*` effect extensions were inspected only at their
  entry points and diagnostics arrays, not re-audited for effect semantics.
- Control-panel/UI view code, except the editor-control primitives consumed
  by the editor design review.
- No builds, test runs, renders, or profiles were executed; all dynamic
  claims (wall-clock dominance, allocation magnitudes) are explicitly framed
  as unmeasured and gated on the instrumentation PR.
- The diagnostic environment-flag surface in `AudioBackendSelection.swift`
  was inventoried only partially (noted in section 9).
- Private corpus modules were not used or referenced; no private filenames,
  local paths, or machine-specific details appear in this report.

## 12. Appendix: files inspected

App sources: `AppDelegate.swift`, `ApplicationMenuBuilder.swift`,
`AudioBackendSelection.swift`, `AudioEngine.swift`,
`BlankTrackerDocument.swift`, `CSoftwareMixer.swift`,
`ControlPanelDisplayState.swift`, `EditableXMWriter.swift`,
`EditorControlPrimitives.swift`, `EditorKnobControls.swift`,
`EditorNoteAuditionAudioSink.swift`, `ExportXMCoordinator.swift`,
`LoadedModuleEditableCopyCoordinator.swift`, `ModuleMetadataLoader.swift`,
`PlaybackEngine.swift` (entry points only; see section 11),
`PlaybackModel.swift`, `PlaybackSongAdapter.swift`,
`PlaybackSongAdapter+Timing.swift`, `PlaybackSongAdapter+VolumeEffects.swift`,
`PlaybackSongBuilder.swift`, `PlaybackSongOfflineRender.swift`,
`PlaybackTiming.swift`, `RuntimeCMixerAdapterEventPlan.swift`,
`RuntimeCMixerBackend.swift`, `RuntimeCMixerRenderCore.swift`,
`SoftwareMixer.swift`, `WAVExportCoordinator.swift`.

App tests: `ApplicationMenuBuilderTests.swift`,
`BlankTrackerDocumentTests.swift`, `CSoftwareMixerTests.swift`,
`EditableXMWriterTests.swift`, `ExportXMCoordinatorTests.swift`,
`LoadedModuleEditableCopyCoordinatorTests.swift`, `OfflineRenderTests.swift`,
`RuntimeCMixerTests.swift`, `TestSupport.swift`,
`WAVExportCoordinatorTests.swift`.

Core: `core/MixerCore/include/vtx_c_mixer.h`,
`core/MixerCore/src/vtx_c_mixer.c`, `core/ModuleCore/include/module_types.h`,
`core/ModuleCore/include/xm_header.h`, `core/ModuleCore/src/mod_header.c`,
`core/ModuleCore/src/module_types.c`, `core/ModuleCore/src/xm_header.c`.

Tools and package tests: `tools/vtx_render_bounded_xm/main.swift`,
`tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift`,
`tests/core/ModuleCoreTests.swift`,
`tests/vtx_render_bounded_xm/VTXRenderBoundedXMTests.swift`.

Build/CI: `Package.swift`,
`app/VoodooTrackerX/VoodooTrackerX.xcodeproj/project.pbxproj`,
`.github/workflows/basic-checks.yml`, `.github/workflows/release.yml`.

Scripts: `check-files.sh`, `scan-tracked-private-leaks.sh`, `run-golden.sh`,
`package-macos-dmg.sh`, `run-local-corpus-runtime-metrics.py`.

Docs: `AGENTS.md`, `README.md`, `docs/agent-current-state.md`,
`docs/architecture.md`, `docs/audio-comparison.md`, `docs/contributing.md`,
`docs/decisions/006-windowed-offline-candidate-rendering.md`,
`docs/design/editable-document-save-export-model.md`,
`docs/design/editor-control-vocabulary.md`,
`docs/design/instrument-editor-window.md`,
`docs/design/sample-editor-window.md`, `docs/dev-roadmap.md`,
`docs/diagnostic-tools.md`, `docs/roadmap.md`, `docs/testing.md`.

External reference (public project, consulted conceptually, no code copied):
ft2-clone `src/ft2_wav_renderer.c`, `src/ft2_replayer.c`, `src/ft2_audio.c`,
`src/ft2_mix.c`, `src/ft2_mix_macros.h`, `src/ft2_inst_ed.c`,
`src/ft2_sample_ed.c`.
