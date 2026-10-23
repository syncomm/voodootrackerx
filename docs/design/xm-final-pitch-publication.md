# XM semantic pitch and ordered physical publication proposal

Status: proposed, awaiting Gregory's architecture review in
[issue #488](https://github.com/syncomm/voodootrackerx/issues/488).
Clock prerequisite baseline: `ad359d2c3f30b7b28b471caef5082a17721f803d`;
bounded G31 remains closed. G32A-2A is separately authorized for coordinates only;
complete capture, final pitch migration and G32 behavior remain unauthorized.
The supplied G32 preflight is characterization evidence:
208 reference renders / 519,120 oracle assertions, not rerun for this proposal.
Existing code, accepted ADRs and the [effect contracts](../xm-effect-support.md)
remain authoritative. This is not an accepted ADR.

**Superseding architecture clarification (proposed):** unconditional final-only
physical coalescing is rejected. C14 retains requests 10963 then 10835 Q16 at
frame 7680: epsilon .003 holds 10963 with ordered delivery, versus 10835 with
last-only delivery. One semantic effect-output period does not authorize removing
an intermediate physical request. Raw calculations, admitted ordered requests,
runtime accepted scheduling latch and physical C state/cursor are distinct.
Semantic ownership, carried selection, source generation and conversion provenance
also differ. Meaningful source-less pitch is not numeric zero; uncaptured pitch
is not an implemented `.unavailable` result.

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
Those diagnostics and every admitted ordered request remain observable. Bx then
4xy/6xy can produce two policy-relevant requests on one tick: semantic output
may be one final period while runtime holds an earlier accepted request.

**Depth-off consumer boundary:** preserve runtime seven-family fanout and initial
holds, event IDs/categories/order/counts, epsilon 0…0.01/default 1e-5,
whole/window/indexed/scan scheduling, continuations and strict-before source
histories. Inclusive cuts, provisional fine/extra-fine and ordinary delayed Bx
admission stay authoritative. The companion supplies neither physical history
nor source eligibility. No final-only consumer or history switch is proposed.

## Alternatives

| Design | Benefit | Cost / disposition |
| --- | --- | --- |
| Candidate A: semantic versus physical ownership | Separates one semantic output from zero-or-more ordered physical intents. | Selected direction for further proof; complete production capture remains unimplemented. |
| Candidate B: final-only physical compaction | Reduces physical requests. | Not authorized: C14 disproves policy neutrality. Lossless ordered spans need their own contract. |
| Candidate C: surgical native capture/composition | Captures facts at existing arithmetic, selection and birth boundaries. | Preferred technique within A's ownership model; judge correctness, coverage, ordering and cost, not line count. |

## Proposed construction and ordering

G32A-2A installs one immutable two-Int clock run per traversed row during the
existing traversal, sharing Fxx timing and row-channel diagnostics. Pure queries
derive valid tick/channel coordinates, including blank and source-less cells.
No row-exit or terminal tick is added. Coverage/isolation copies and cached Play
preserve the companion; envelope-tail extension does not extend this clock.
There is no native period/owner/reset query, hidden oscillator or phase advance.

The separately authorized G23 childless-invocation companion observes only actual
instrument-only nonzero EDx/F0 tone-handler calls with no numeric children. Compact
runs retain original row commands and existing diagnostic indices; queries project
real invocation ticks through the canonical clock and preserve each diagnostic's
status, policy and generation association. Legacy row-scope diagnostic coordinates
remain unchanged. This partial evidence supplies no pitch, ownership, lifecycle,
source-eligibility or physical-delivery authority and does not accept this proposal.

G32A-2B requires separate approval for native period, ownership/conversion and
actual dispatch/reset capture before physical admission. Use incoming scalar seeds,
not end-of-row snapshots as tick-zero state, and never invert Q16 or filtered C
pitch. Generic source-less vibrato may advance legacy phase without calculating
new output; held and newly calculated output must remain distinguishable.
Reduce newly captured row facts with bounded scalar workspace and a pending
prior-row boundary after established arpeggio/vibrato exit subsumption. Producer
references follow actual fanout creation order; helper-call/effect-name order
does not establish runtime order. Cold and runtime comparators remain distinct.
Keep one semantic channel/tick result or sparse held interval separately from
all ordered requests and distinct generations/frame integration boundaries.
No additional song pass, full-control/PCM copies, per-tick heap storage, callback
clock or eighth effect authority is proposed; the envelope clock is not universal.

Future enabled composition is **canonical base → ordered effect-output intents
→ one automatic delta per canonical tick → existing Linear/Amiga conversion →
each admitted intent or folded birth**. Automatic-only publication on no-writer
ticks and new causal admission require separately approved policy. Waveform,
sweep, reset arithmetic and compatibility choices remain unresolved. Depth-off
coordinates neither recompute closed G30A/B nor implement audible G32.

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
Last-only equality alone never proves an existing ordered request redundant.
Original DOS FT2 bit reduction is separate from the consulted clone's Float32
output; neither proves the other's PCM policy. GPL source/tables must not enter
MIT VTX. Tests use independently authored cells, PCM and an arbitrary period
offset for birth folding, with no autovibrato waveform/sweep implementation.

Parser isolation, MOD/XM read-only loading, exact 96-note/S01...S16 routing,
ADR 012–014, editable Undo, preview, XM export/reopen and source URL ownership
remain protected. Accepted ADR 012 Policy B and ADR 014 remain authoritative;
the deployed absent-map discrepancy stays OPEN. This proposal changes no document,
format, effect, C DSP, runtime host, UI or roadmap boundary.

## Proof and remaining gates

[FinalPitchPublicationShadowTests](../../tests/vtx_render_bounded_xm/FinalPitchPublicationShadowTests.swift)
extracts existing diagnostic writers in test memory, pins the raw runtime plan
steps, and compares coalesced/raw/indexed strict-before cursor positions, source
eligibility and isolated C pitch PCM. It covers both modes/rates, Bx→4xy,
6xy, E4, all seven families, lifecycle routes, cold zero births and Amiga zero
hold/resume. Product whole/window PCM is also compared with a `1e-7` tolerance.
The ordinary priority ordering and positive birth folding use actual storage,
event construction and C cursor observation; they do not execute the runtime host.

That allocating oracle establishes only its bounded default-policy cases.
G32A-1C/1E C14 counterevidence rejects universal coalescing. The separate bounded
1E Candidate A proof preserves ordered delivery alongside native semantic output
in selected lifecycle/birth/hold cases; it proves neither a production constructor
nor complete source-less capture, ordering, storage or enabled composition.
No full green Xcode suite is claimed for that archived RED evidence branch.
G32A-1F identifies the clock prerequisite followed by separately approved complete
capture. Clock-only work cannot label uncaptured pitch unavailable.

R02 ordinary replacement-retirement pitch parity is closed for the public
Linear/Amiga, 44.1/48 kHz controls in `OrdinaryReplacementOfflineParityTests`
and `R02ReplacementParityTests`. Offline scheduling and continuation histories
now preserve runtime's cancellation of old-generation pitch writes at replacement
frame N, holding the pre-N physical step while advancing the retiring cursor.
Whole/window/indexed/scan, loop direction, zero hold/resume and completed-source
controls retain the existing 32-frame policy. G21/Rxy retirement debt, G03's FT2
overlap policy and broader epsilon-policy parity remain separate; G23 tolerance
is unchanged. No generic parity exclusion or relaxed PCM gate is authorized.
Issue #488 remains OPEN and this document remains proposed. Complete capture,
enabled behavior and compatibility decisions require their own approvals/proofs.

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
