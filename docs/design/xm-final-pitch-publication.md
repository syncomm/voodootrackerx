# XM native pitch composition and ordered physical publication

Status: Gregory accepted Candidates A/C and rejected Candidate B on October 24,
2026 (America/New_York), for the depth-off semantic publication foundation only.
[Issue #488](https://github.com/syncomm/voodootrackerx/issues/488) remains OPEN
pending independent manager review; its older proposed status does not revoke
this limited approval.
Clock prerequisite baseline: `ad359d2c3f30b7b28b471caef5082a17721f803d`;
bounded G31 remains closed. G32A-2C1 authorizes physical/event/PCM-neutral native
semantic capture and publication. Consumer migration, enabled automatic pitch
and an eighth pitch stream were outside that foundation's approval. Gregory's
October 25 approval below supersedes the earlier UNAPPROVED disposition of the
six G32 playback policies only; audible implementation remains subject to the
composition-boundary and physical-delivery preflight gates.
The supplied G32 preflight is characterization evidence:
208 reference renders / 519,120 oracle assertions, not rerun for this proposal.
Existing code, accepted ADRs and the [effect contracts](../xm-effect-support.md)
remain authoritative. This is not an accepted ADR.

**Accepted depth-off architecture clarification:** unconditional final-only
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
| Candidate A: semantic versus physical ownership | Separates one semantic output from zero-or-more ordered physical intents. | ACCEPTED for the depth-off foundation; native semantic publication remains separate from ordered physical delivery. |
| Candidate B: final-only physical compaction | Reduces physical requests. | REJECTED: C14 disproves policy neutrality. Lossless ordered spans need their own contract. |
| Candidate C: surgical native capture/composition | Captures facts at existing arithmetic, selection and birth boundaries. | ACCEPTED within A's depth-off ownership model, with no additional whole-song pass. |

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
source-eligibility or physical-delivery authority and does not prove complete capture.

The accepted G32A-2C1 foundation covers native period, ownership/conversion and
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

`PlaybackSongSemanticPitchProjection.swift` implements the depth-off companion
at this traversal seam. Canonical queries retain base, held output and causal
producer references; capture failures remain explicit `notCaptured` results.
Physical consumers continue to use their existing seven diagnostic families.

Future enabled composition is **canonical base → ordered effect-output intents
→ one automatic delta per canonical tick → existing Linear/Amiga conversion →
each admitted intent or folded birth**. Automatic-only publication on no-writer
ticks and new causal admission are authorized by the audible G32 task, subject
to its ordering/admission proof. The six playback policies below now govern
waveform, sweep and compatibility interpretation. Depth-off
coordinates neither recompute closed G30A/B nor implement audible G32.

Automatic metadata/phase/sweep belong to channel semantic ownership,
not PCM lifetime. Source identity only authorizes delivery and selects the
existing source conversion inputs; a refused new owner can modulate retained PCM.
The semantic owner must not silently substitute a new sample's base rate.

### Depth-off instrument clock foundation

`PlaybackSongInstrumentAutovibratoClock` retains sparse owner/reset/release
anchors inside the existing semantic row reducer. Queries derive before/after
8-bit phase and elapsed ticks from the canonical traversal, including empty
rows; rendering, window continuation and cached Play never advance another clock.
Metadata follows the semantic owner, independently of carried instrument and
source generation/conversion. Natural clock facts include depth-zero metadata;
they establish no audible eligibility. No waveform ordinate or period is computed.

Row-entry and instrument-only EDx resets reuse actual #503/#504 observations.
Additional delayed-note and refused resets are captured beside actual native
reset calls. E9 automatic resets follow admitted source/empty dispatches; they
are new automatic lifecycle anchors, not invented per-tick observations of the
legacy aggregated effect-phase reset. Instrumentless E90/Rxy carry the clock.
Applied release excludes its own tick from key-on elapsed time, freezes that
elapsed fact and continues phase. `sweepReached` means nominal raw duration
completion, never rounded integer amplitude completion. Total and key-on elapsed
ticks remain separate; no released amplitude is selected. Malformed bytes,
sweep-255 and rate-zero square retain raw metadata with `policyPending` status;
malformed metadata yields no numeric phase. These are the foundation's inert
query results, not a disposition of the now-approved audible policies below;
public raw queries retain the foundation contract. Enabled publication consumes
an interpreted view of the same phase/reset/release anchors; a visibility bit
preserves legacy malformed-phase absence without adding another clock.

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

On October 25, 2026 (America/New_York), Gregory explicitly answered **"Approved
all six"** to the intended-behavior proposal. This supersedes this document's
earlier UNAPPROVED wording for these six **G32 playback policies only**. It does
not amend persisted parser/writer bytes, accepted ADRs, global G30 arithmetic or
unrelated effects. Issue #488 remains OPEN for independent complete-G32 review.

**A — G32 target:** independent channel-semantic phase/sweep,
sine/square/two ramps, meaningful sweep and normal reset/carry, phase continuing
after release, and composition after effect output. The enabled implementation
below follows the approved VTX policies; complete G32 closure remains open.

The supplied preflight observations, pinned
[replayer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c)
and [instrument sanitizer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_inst_ed.c)
support the distinctions below. Metadata ranges do not specify every arithmetic
or malformed-byte edge. Observed clone behavior is evidence, not approval.

| Approved G32 playback policy | Historical artifact / evidence | Required VTX interpretation |
| --- | --- | --- |
| Malformed raw metadata | Sanitizer characterization uses type 0...3, depth 0...15 and rate 0...63. | Playback alone maps invalid type to sine and caps depth at 15/rate at 63. Sweep retains raw 0...255; persisted bytes stay exact. |
| Signed modulation rounding | Negative small products can floor while positive products truncate to zero. | Deterministic round-to-nearest, ties-away-from-zero, with sign symmetry and explicit half-tie tests; omit the negative-only bias. |
| Composed period boundaries | Historical word wrapping and a ≥32000 gate can hold or jump pitch. | Derive mode/source-aware final bounds from unchanged G30 conversion and representable steps before production clamps. Preserve native base/effects and meaningful exact-zero hold/resume; stop if these obligations cannot be reconciled. |
| Sweep 255 | High-byte traces can exceed requested depth, then snap back. | Sweeps 0/1/16/255 ramp to at most requested depth, with explicit tick, saturation and release tests. |
| Release during unfinished sweep | Historical release can use an increment in place of reached amplitude. | Retain amplitude reached at release and continue oscillator phase; do not reduce or reinitialize it. |
| Rate-zero square | Fixed square phase can produce constant detuning. | Rate zero is neutral for every waveform; depth zero is physically inert. |

These are VTX composition semantics. Negative-only rounding bias, sweep
overshoot/snapback, released-amplitude collapse and rate-zero-square detuning are
intentional non-emulations. Reference observations do not authorize importing
GPL code/tables or weakening regression tolerances.

### Composed-boundary preflight

[InstrumentAutovibratoBoundaryPreflightTests](../../tests/vtx_render_bounded_xm/InstrumentAutovibratoBoundaryPreflightTests.swift)
pins unchanged G30 conversion before choosing production clamps. With retained
source rate 8363, Linear period 9216 produces Q16 step 194/178 at 44.1/48 kHz;
9217 produces zero. Period 14080 is also zero, whereas 14081 produces
6357427/5840886. These are existing exponent/word conversion boundaries, not a
new G32 clamp. Ordinary C-0 → 2C0 → X21 reaches 9217 without a new source;
X11 returns to 9216 and resumes the same C cursor. Native base and semantic
effect output retain these exact values.

Positive-step bounds also depend on the sounding source's conversion inputs.
At source rate 1, Linear's initial positive interval ends at 5045/4954 and
Amiga's at native 2544/2337 at 44.1/48 kHz. At source rate 8363, Amiga remains
positive through native 65535 (VTX 262140); native 65536 wraps to zero in the
unchanged converter. A universal 31999 bound is therefore unjustified.

For the continuation, the isolated composition kernel chooses a conservative
interpretation of "surprise high-period freezes": only an ordinary output within
the retained source's initial continuous positive-step interval receives new
modulation. New output saturates to native `0...upper`; exact zero remains a hold.
An existing output outside that interval keeps its original G30 conversion,
including existing zero regions and positive high branches. Delta zero is exact
identity. Linear's hard upper edge is 9216, Amiga's is native 65535; source/output
Q16 quantization can reduce either bound. Unusual Linear source ratios with
internal coefficient-word aliases remain outside this automatic domain. Bounds
are cached conversion values, never changes to canonical base/effect history.
The row materializer invokes this kernel before existing physical consumers.

[InstrumentAutovibratoDeliveryPreflightTests](../../tests/vtx_render_bounded_xm/InstrumentAutovibratoDeliveryPreflightTests.swift)
uses an arbitrary fixed offset to probe blank-tick C step delivery, folded
positive births, exactly-once zero birth hold/resume, and separate ordered
Bx→4xy/6xy intermediates in both modes/rates. This is test-only construction,
not product automatic publication, whole/window history parity or host proof.
Existing Xcode C14 controls separately pin runtime generation/epsilon admission.

### Isolated composition arithmetic

`PlaybackSongInstrumentAutovibratoComposition` interprets a value copy of raw
metadata; it never rewrites parser/writer records. It consumes the existing
clock's phase-after and key-on sweep elapsed values, without owning another clock.
Its authored quarter-sine ordinates are `round(32768*sin(pi*i/128))`, `i=0...64`;
quadrant reflection gives negative sine on the first phase half. Square is -1
below phase 128 and +1 thereafter. Raw type 2 uses `signed8(phase)/128`; raw type 3
uses `signed8(-phase)/128`. Positive period delta lowers pitch, so the existing
waveform names describe pitch direction. Native amplitude equals interpreted depth; Amiga delivery
scales the resulting native period by four through the existing conversion seam.

For Q15 ordinate `w`, depth `d`, sweep duration `s` and frozen-at-release key-on
elapsed `e`, the delta is nearest integer to
`w*d*min(max(e,0),s)/(32768*s)`, with half ties away from zero. Sweep zero uses
full amplitude immediately. Integer quotient/remainder rounding gives
`round(1/2)=1`, `round(-1/2)=-1` and `round(±1/32768)=0`, without signed floating
conversions. The bounded elapsed fraction cannot overshoot requested depth.
Continuing oscillator phase with the same `e` preserves reached release amplitude.

The mathematical Q15 sine can differ from reference ordinate quantization as well
as historical signed rounding. These differences require separate reference-audio
classification; reference-identical normal audio is not claimed. Focused kernel
tests cover numeric policies; publication and runtime controls separately cover
enabled behavior. The clock's raw malformed `policyPending`/nil-phase queries
remain unchanged while its interpreted view uses bounded playback metadata.

### Enabled physical materialization

The materializer reuses the existing semantic owner/generation/clock capture and
actual native producer facts. A bounded per-source ordinary-intent latch records
the birth mapping or last actual writer's native output, separately from both the
semantic effect latch and epsilon-filtered C state. Current numeric childless
fine/extra-fine/tone invocations can supply an auto-only basis when that source
has no physical writer at the tick; held semantic references cannot silently
retune a newly born generation. There is no second native resolver, song pass,
full control snapshot or per-tick heap object.
The materializer composes each existing ordered diagnostic child's physical step
from that child's own native output; captured original children and native period
fields remain raw. Prior-row exits wait for incoming-row subsumption and use the
incoming canonical tick's delta when that channel has a canonical tick. A sparse
row's actual exit uses the last canonical delta and updates the retained intent
without creating a clock tick or request. Terminal ordinary restoration keeps the last
canonical automatic value without advancing an envelope-tail oscillator.

Births use their ordinary mapping's native input, including existing same-cell
fine folds, even when E9/Rxy initially copied an already composed event. Inactive
owners preserve ordinary birth/hold behavior exactly, including legacy zero-E9
placeholder behavior. Automatic-only requests target real source generations on ticks
without an ordinary writer; held-value equality deduplicates them. A change to
depth/rate zero restores a previously affected retained source once. Existing
strict-before source history admits these requests alongside fine pitch before
runtime/offline/window scheduling. Auto-only requests and introduced zero-birth
holds receive IDs after existing events; original hold/writer IDs stay unchanged.
G05 admission preserves this rule at native event construction. Let `P` be the
existing prefix size, `L` the preexisting audible publication-slot count observed
in the same generation fold, and `G` the automatic-request/introduced-hold capacity.
The physical interval starts at `P + L`; its cursor advances only for accepted
events. Current output ordinal `j` receives `P + j` below `L`, otherwise
`P + j + G`, leaving that physical interval reserved. Output IDs remain strictly
monotone, so the existing cold/runtime priority and source-order comparators
preserve every action's order. Pruned or guarded-out slots may leave unused IDs.
These plan-local keys are distinct from storage indices, source generations and
request ordinals. No existing event is renumbered after construction, and the
slot count never participates in musical target or source-lifetime decisions.
Its one inline `Int` adds eight bytes per plan (current stride 1104), with no
per-target storage or change to channel, request, event or C voice strides.
The seven ordinary families and their order remain physical authority. Capture
failure refuses new automatic row/tail work, preserving the already proven
prefix and ordinary intents; existing capture-failure diagnostics remain visible.

G34 clarifies the comparison boundary: numeric IDs are plan-local. Newly
supported T behavior can create genuine ordinary-family reset metadata and
audible publication slots, changing `P`, `L` and absolute numbers across
implementations. It does not renumber an already constructed event. Matching
candidate plans preserve source generations, G32 pitch-request tuples, frames,
IDs, priority and delivery order; G34 leaves no-T physical IDs, frames and PCM
byte-identical. The accepted G05/G32 allocation and ordering rules above remain
unchanged.

The immutable causal carrier is 32 bytes. Its Array reference and the introduced-hold
provenance Set change plan stride from 1080 to 1096 bytes. ChannelState remains 1152, native records 48,
reset runs 24 and clock anchors 48 bytes. Bounds are 32-byte cached values,
pruned to retained channel generations. Row scalar workspaces are temporary;
the existing semantic reducer and its 32-byte transient boundaries are unchanged. Modified
diagnostic children can require COW storage beside captured raw children.
Profile fields expose request/bounds capacity growth, row workspace capacity and
changed-array capacity proxies; these are not measured malloc counts.

Earlier G32 controls observed the runtime E9/Rxy old-voice tail versus an immediate
offline cut, with strict PCM equality outside the retirement windows and matching
new-generation step/cursor delivery inside them. G21's separate bounded
[offline retirement contract](xm-reset-output-ramp.md#g21-offline-e9r-outgoing-source-retirement)
now preserves that native 5 ms tail in offline delivery. G32 changes no tolerance
or DSP policy; retirement remains independently owned from instrument modulation.

**C — intentionally omit:** redundant period-refresh flags and period writes to
inactive mixer slots when state/output equality is preserved. No phantom source
or redundant C callback work. Meaningful zero-step holds are not classified C.
Last-only equality alone never proves an existing ordered request redundant.
Original DOS FT2 bit reduction is separate from the consulted clone's Float32
output; neither proves the other's PCM policy. GPL source/tables must not enter
MIT VTX. The original shadow tests used independently authored cells, PCM and an arbitrary
period offset for birth folding; those tests did not implement a waveform or sweep.

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
controls originally retained the 32-frame policy. The bounded G03
[song-retirement contract](xm-reset-output-ramp.md#g03-same-channel-outgoing-source-retirement)
extends those same R02 proofs through the full 5 ms tail without reopening the
old pitch stream. G21 separately closes offline E9/Rxy retirement through that
same native policy. G03/G21 acceptance and broader numerical qualification remain
separate from G32; G23 tolerance is unchanged. No generic parity exclusion or
relaxed PCM gate is authorized.
Issue #488 remains OPEN for independent manager review. The depth-off A/C
architecture is accepted; complete capture, neutrality and cost require their
independent verification gates.
The October 25 task authorizes enabled composition under the six policies above;
it still requires independent behavior, physical-delivery and performance proof.

Measure existing `event_generation`, `fine_pitch_source_history_build`,
`fine_pitch_source_eligibility`, cold ordering/materialization and runtime queue
profile fields, plus projection records/bytes/visits and allocation counts. Avoid
per-tick heap objects, PCM copies, full control snapshots or widened ChannelState.
The 1152-byte state/8-byte row-reference baseline must be remeasured on migration.
Composition must not introduce another song pass, planner replacement, broad
seven-family consumer rewrites, C/host work or costly snapshots.

Validation requires fresh paired alternating process-cold ordinary
optimized Release products, two five-pair batches where feasible, public heavy
synthetic input and strict `cached_reuse`. Optional `xm-corpus-011` requires a
dynamically supplied map, never a default private path. Hard pooled medians remain
972 ms planning / 1000 ms first Play / 2333 ms heavy planning. Report distributions,
counts above one second and attributed trends even below ceilings; no +15 ms
failure rule. G31 numbers are historical, not reusable executables. Full Xcode,
actual host, reference audio, Release benchmarks and listening are not established
by the shadow tests. The external handoff report records executed
checks. No private inventory, listening or corpus curation is needed here.

## G36 E3x tone-output glissando

Gregory accepted the qualified eight-WAV listening study. This bounded contract
is CLOSED for the submitted post-merge state; publication requires green CI,
maintainer review and Gregory's merge into main.

The bounded contract uses the unchanged native observer at ft2-clone
`87be42543dac82cf802b5bddad917bda62ace131`. E30 disables and every nonzero
nibble enables one persistent channel control. Ordinary notes, instrument resets,
release and source completion preserve it; a fresh playback state starts disabled.
The control itself publishes no pitch. E30 therefore holds the last snapped output
until the next actual tone invocation restores continuous movement.

3xx, 300, 5xy and volume-column Fx retain their continuous period, exact latent
target, direction and speed. After each actual movement/clamp, enabled output uses
the existing bounded arpeggio inverse projection with offset zero and the current
pitched channel's finetune. Relative note is already included in the period.
Linear zero-finetune 4575 projects to 4544, while the tie at 4576 chooses 4608;
Amiga native 1663 projects to 1616, while 1664 chooses 1712 (VTX units are x4).
This is the established bounded grid, including its upper edge, rather than an
unbounded nearest-note approximation. E5 can change current tuning without
rewriting an old target: Linear target 3056 with new finetune -128 emits 3072.
An equal target admitted with direction none remains inert; a historically
latched direction continues projecting the reached target on actual invocations.

Immutable pitch children retain raw arithmetic periods and compact optional
finetune provenance. Semantic base references read those raw periods; output
references and the existing G32 composer consume the projected native intent.
Physical output uses the existing conversion and C step events, preserving source
generation/cursor and the one final pitch authority. Channel state remains 1152
bytes and pitch children 144 bytes; no C, callback or sample-metadata change is
involved. [GlissandoTests](../../tests/vtx_render_bounded_xm/GlissandoTests.swift)
pin numeric output, toggles, aliases, E5, Fxx, EEx, source lifetime and G32 delivery.
Live qualification starts at order zero. Direct cold selected-range plans ignore
unplayed earlier E31 controls; product cached live selected-order integration
remains OPEN under [#516](https://github.com/syncomm/voodootrackerx/issues/516).
G38 traversal conflicts, G39 broader modulation, G40/G41 and the later integrated
planning/memory/UI/CI audit retain their separate ownership.
