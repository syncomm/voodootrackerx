# XM final pitch publication proposal

Status: proposed, awaiting Gregory's architecture review in
[issue #488](https://github.com/syncomm/voodootrackerx/issues/488).
Baseline: `f6d5d9a4c7303d4e333d0ce8f368fc88e0cda9e6`; bounded G31 remains closed.
This note and its test-only shadow experiment authorize no production migration
or G32 behavior. The supplied G32 preflight is characterization evidence:
208 reference renders / 519,120 oracle assertions, not rerun for this proposal.
Existing code, accepted ADRs and the [effect contracts](../xm-effect-support.md)
remain authoritative. This is not an accepted ADR.

## Current ownership and consumer map

All Swift filenames below are under `app/VoodooTrackerX/VoodooTrackerX/`.
`PlaybackSongAdapter.swift:appendEvents` stages whole-row effect planning,
followed by delayed/Rxy and other nonzero-tick work. It is not already a single
channel/tick finalization loop. Empty-cell bypass and next-row vibrato restoration
must survive. `ChannelState` keeps base period, held vibrato output, semantic
instrument and active source separately; its baseline stride is 1152 bytes.

| Diagnostic family, in existing fanout order | Runtime loop in `RuntimeCMixerAdapterEventPlan.make` | Offline scheduling helper in `PlaybackSongOfflineRender.swift` |
| --- | --- | --- |
| `tonePortamentoEffects` (3/5/column F) | tone loop | `scheduleTonePortamentoStepUpdates` |
| `portamentoSlideEffects` (1/2) | regular slide loop | `schedulePortamentoSlideStepUpdates` |
| `finePortamentoUpEffects` (E1) | fine-up loop | `scheduleFinePortamentoUpStepUpdates` |
| `finePortamentoDownEffects` (E2) | fine-down loop | `scheduleFinePortamentoDownStepUpdates` |
| `extraFinePortamentoEffects` (X1/X2) | extra-fine loop | `scheduleExtraFinePortamentoStepUpdates` |
| `arpeggioEffects` (0xy) | arpeggio loop | `scheduleArpeggioStepUpdates` |
| `vibratoEffects` (4/6/Bx) | vibrato loop | `scheduleVibratoStepUpdates` |

Fine/extra-fine birth adjustments are already folded into triggers; runtime
skips `appliedToInitialPlaybackStep`. Their histories ignore updates at birth.
Bx then 4xy can execute twice on one tick, with separate phase/memory results.
Those diagnostics must remain visible even if only the last step reaches C.

| Consumer / exact call site | Required future switch |
| --- | --- |
| `RuntimeCMixerAdapterEventPlan.swift:make`, seven loops and initial-hold loop | Final step references and trigger intent replace pitch delivery fanout; diagnostics/categories retain writer provenance. |
| `PlaybackSongOfflineRender.swift:PlaybackSongOfflineRenderSession.init` | Whole-song delivery uses the same final values. |
| `PlaybackSongOfflineRenderer.renderWindowedCore`, scan scheduling | Window-local frames derive from the shared values. |
| `windowSchedulingUpdateCandidates`, `schedulePreindexedWindowUpdates`, `preindexedStepUpdate` | Index final publication references, rather than resolving seven families independently. |
| `sampleStepUpdates`, `sourcePositionState`, `continuations` | Scan/continuation pitch and strict-before cursor integration use final values. |
| `PitchSourceHistory.init`, `advancedPosition`, `hasActiveSource` | Replace the existing seven-family extraction; retain cuts, lifetime and exact integration. |
| `PlaybackSongAdapter.swift:admitFinePitchPublications` | Source eligibility must use the shared candidate prefix without circularly requiring admitted output. |

## Alternatives

| Design | Benefit | Cost / disposition |
| --- | --- | --- |
| 1. Compact projection during existing row planning | Has effect results, route facts and births before consumer fanout; can reserve value storage once. | Preferred, conditional on row-edge and eligibility proofs below. Requires explicit finalization after all staged writers, not a new planner. |
| 2. Immutable index built near plan assembly | Convenient common consumer API and existing source-prefix storage. | Reject a new post-plan song fold. Accept immutable storage only as the result of design 1 and replacement input to the existing history build. |
| 3. Adapter/trigger coalescing alone | Small local change; birth folding is straightforward. | Reject as sole authority: it is downstream of fine eligibility and offline/history consumers. Building it separately for each consumer multiplies work and can diverge. |

The preferred seam is row-local projection plus shared immutable storage, not
an eighth diagnostic family, an envelope-timeline expansion or a C waveform engine.
Raw family diagnostics remain immutable and observable. Final delivery records
identify the winning writer; intermediate diagnostics must not claim a C write
that coalescing removed. Any trace projection happens during planning, not in C.

## Proposed construction and ordering

1. In the existing `adapt` row iteration / `appendEvents`, mark new diagnostic
   spans and capture only incoming held-period/source scalars. After the row's
   staged writers, visit those new spans once in existing family/writer order.
   Do not refold prior rows or use end-of-row `ChannelState` as tick-zero input.
2. Use a reusable scalar row workspace, bounded by actual channel count/effective
   speed, plus pending boundary writes. Seed births from existing event mappings;
   retain source-event indices as generation keys. Resolve by frame, existing
   tick ordering, family and writer ordinal before selecting the final value.
   Fold previous-row vibrato exit into the next frame's group only after its
   writers are known; preserve G17/G18 exit subsumption and the terminal boundary.
3. A proposed value record contains frame/tick identity, channel, source-event
   identity, source-or-birth intent and final step; provenance refers to existing
   diagnostics. Emit at most one record per channel/frame/generation after
   ordering is resolved. Keep distinct-frame integration boundaries even for
   equal steps: removing them can change sequential Double rounding. Do not add
   a record on every plain depth-off tick merely to express a held value.
4. Feed this storage into the existing `PitchSourceHistory` construction instead
   of scanning seven families there. Retain provisional fine/extra-fine candidates
   for its strict-before prefix; existing admission suppresses only ineligible
   publications. Freeze admitted references during that existing admission walk.
   Prove removal cannot change any earlier eligible prefix; no second song fold.
5. Runtime, whole/window/scan/indexed delivery and continuation queries must
   switch together. Store once per immutable plan; reuse cache and loop storage.
   No callbacks, clocks, PCM buffers or document values are added by consumers.

The future enabled sequence is **canonical base → existing effect-output period
→ automatic delta once per canonical tick → existing G30A conversion → source
step or birth intent**. Linear uses its current units; Amiga automatic deltas
are native units, projected to VTX's 4x domain at the existing converter boundary.
Effect output is never reconstructed by inverting a quantized step. In the
depth-off prerequisite, reuse existing converted steps exactly; do not recompute
closed G30A/B or alter any family implementation to generate the projection.

Automatic metadata/phase/sweep eventually belong to channel semantic ownership,
not PCM lifetime. A later compact channel sidecar can hold phase/amplitude/ramp;
no state is added here. Source identity only authorizes delivery and selects the
existing source conversion inputs; a refused new owner can modulate retained PCM.
The semantic owner must not silently substitute a new sample's base rate.

Births carry a positive final step in their trigger before its first mixed frame.
Ordinary priority-0 updates precede priority-2 triggers and cannot initialize
the new generation. Zero births retain the existing positive placeholder plus
`initial_pitch_hold` after-trigger update before mixing: `SyntheticTrackerEvent`
and C source creation currently require a positive initial step. No sanitizer or
C API change is proposed. A future composed zero birth uses that same atomic
creation/hold intent. Existing zero-step sources retain their cursor and resume.

## Lifecycle obligations

| Case | Preserved contract / later G32 obligation |
| --- | --- |
| Ordinary explicit birth / note-only birth | Existing admission, keymap and cursor-zero generation remain; explicit resets versus note-only automatic carry stay distinct. |
| Refused note / instrument-only | Retain PCM generation/cursor. Follow actual semantic owner/reset invocation, not carried instrument or selected sample alone. |
| ED0 / in-row EDx / out-of-row EDx | Preserve actual dispatch frame and pre-delay held output; delayed note-only reset differs from immediate note-only carry. Out-of-row creates no delayed birth/reset. |
| Nonzero E9 / E90 / Rxy | Preserve their existing source events and counters; later automatic E9 resets versus instrumentless E90/Rxy carry are separate from source restart. |
| Cold / completed / declared empty / unavailable | Keep meaningful semantic pitch and eventual clock progression without fabricating a voice; unavailable routes gain no fallback. Fine admission and inclusive empty cuts stay authoritative. |
| Replacement / released / retiring source | Generation keys never collapse into channel keys. Preserve release, cursor, retirement and existing stale/unmatched-source rejection; do not drop retiring writes by assumption. |
| Empty rows / Fxx / order boundaries / new plan | Do not skip future enabled clocks on empty cells; use canonical Fxx frames. Rebuild state cold on invalidation; cached Play reuses an immutable plan. |

## Compatibility disposition, separate from architecture approval

**A — intended eventual G32 target:** independent channel-semantic phase/sweep,
sine/square/two ramps, meaningful sweep and normal reset/carry, phase continuing
after release, and composition after effect output. G32A implements none of it.

The supplied preflight observations, pinned
[replayer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c)
and [instrument sanitizer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_inst_ed.c)
support the distinctions below. Metadata ranges do not specify every arithmetic
or malformed-byte edge. Observed clone behavior is evidence, not approval.

| B — review before approval | Audible consequence / evidence | Compatibility value versus harm; disposition |
| --- | --- | --- |
| Raw-byte playback sanitation | Preflight sanitizer controls map type >3 to sine, depth >15 to 15, rate >63 to 63. | Predictable unusual-input playback versus changing preserved bytes or adopting unproven DOS malformed-input policy. Playback-only interpretation if approved; **UNRESOLVED B/C**, no parser/writer normalization. |
| Signed integer rounding | Negative small products floor to a nonzero negative delta while positive ones may truncate to zero; sweep-255 controls distinguish it. | Exact period/phase matching versus asymmetric low-depth tuning. **UNRESOLVED B**, explicit numeric policy required. |
| UInt16 final-period / unsigned ≥32000 gate | Preflight zero/underflow/high-word controls show real cursor holds and later resume; base/effect output remains unchanged. | Preserves composed extreme behavior versus abrupt holds/pitch jumps. **UNRESOLVED B**, not a harmless refresh and not permission to reopen G30B. |
| High-byte sweep overshoot | Sweep-16/255 traces exceed depth's nominal Q8 amplitude before snapping back. | Reference envelope-of-pitch match versus audible overshoot/discontinuity and unintuitive controls. **UNRESOLVED B/C**; do not approve merely because reproduced. |
| Released unfinished sweep uses increment, not stored amplitude | Early note97/Kxx controls infer a suddenly smaller effective amplitude while stored amplitude freezes and phase continues. | Reproduces release pitch change versus an abrupt vibrato collapse that conflicts with coherent retained-amplitude behavior. **UNRESOLVED B/C**, manager disposition mandatory. |
| Rate-zero square | Enabled depth at fixed phase produces a constant negative period offset; sine stays neutral. | Compatible sustained detuning versus users expecting rate zero to disable modulation. **UNRESOLVED B**, distinct from depth-off. |

**C — intentionally omit:** redundant period-refresh flags and period writes to
inactive mixer slots when state/output equality is preserved. No phantom source
or redundant C callback work. Meaningful zero-step holds are not classified C.
Original DOS FT2 bit reduction is separate from the consulted clone's Float32
output; neither proves the other's PCM policy. GPL source/tables must not enter
MIT VTX. Tests use independently authored cells, PCM and an arbitrary period
offset for birth folding, with no autovibrato waveform/sweep implementation.

Parser isolation, MOD/XM read-only loading, exact 96-note/S01...S16 routing,
ADR 012–014, editable Undo, preview, XM export/reopen and source URL ownership
remain protected. This proposal changes no document, format, effect, C DSP,
runtime host, UI or roadmap boundary.

## Proof and remaining gates

[FinalPitchPublicationShadowTests](../../tests/vtx_render_bounded_xm/FinalPitchPublicationShadowTests.swift)
extracts existing diagnostic writers in test memory, pins the raw runtime plan
steps, and compares coalesced/raw/indexed strict-before cursor positions, source
eligibility and isolated C pitch PCM. It covers both modes/rates, Bx→4xy,
6xy, E4, all seven families, lifecycle routes, cold zero births and Amiga zero
hold/resume. Product whole/window PCM is also compared with a `1e-7` tolerance.
The ordinary priority ordering and positive birth folding use actual storage,
event construction and C cursor observation; they do not execute the runtime host.

This deliberately allocating, post-plan test oracle is not the proposed
construction algorithm. It proves bounded coalescing algebra, not row-workspace
cost or installation. **UNPROVEN FUTURE MIGRATION GATES:** shared production
runtime/offline/source-index consumption; provisional/admitted prefix sharing;
all cross-family row-edge ties, order/nonzero-start and retirement interactions;
no-source period reconstruction for the eventual automatic clock; runtime-core
and actual-host applied frames; optimized layout/allocation/cache measurements.
Existing tests supply bounded regression evidence, not completion of these gates.

The next proposed **single implementation contract**, only after manager approval,
is a behavior-neutral depth-off publication projection and simultaneous consumer
switch at the call sites above. No autovibrato, new effect state or G33 work.
Prove exact current steps, generation/cursor/frame and PCM identity, retain
diagnostic intermediates and source eligibility, then separately seek G32 approval.

Measure existing `event_generation`, `fine_pitch_source_history_build`,
`fine_pitch_source_eligibility`, cold ordering/materialization and runtime queue
profile fields, plus projection records/bytes/visits and allocation counts. Avoid
per-tick heap objects, PCM copies, full control snapshots or widened ChannelState.
The 1152-byte state/8-byte row-reference baseline must be remeasured on migration.
Stop before production work if another song pass, planner replacement, broad
seven-family rewrites, C/host work, costly snapshots or unjustified >~500 lines
are required.

Later implementation retains fresh paired alternating process-cold ordinary
optimized Release products, two five-pair batches where feasible, public heavy
synthetic input and strict `cached_reuse`. Optional `xm-corpus-011` requires a
dynamically supplied map, never a default private path. Hard pooled medians remain
972 ms planning / 1000 ms first Play / 2333 ms heavy planning. Report distributions,
counts above one second and attributed trends even below ceilings; no +15 ms
failure rule. G31 numbers are historical, not reusable executables. Full Xcode,
actual host, reference audio, Release benchmarks and listening are not established
by this proposal's shadow test. The external handoff report records executed
checks. No private inventory, listening or corpus curation is needed here.
