# ADR 015: Playback Planning, Historical State & Resource Budgets

## Status and purpose

**PROPOSED — not accepted; no redesign authorized.** Assessment dated
2026-11-09 (local), source base `79823358363ab1903d73c62856902fec627a03db`,
after Gregory merged [PR #545](https://github.com/syncomm/voodootrackerx/pull/545).
This is a living decision proposal, not an implementation description or a
replacement for accepted ADRs. No final planning architecture is selected.

VTX is a musical composition and performance instrument: selecting a position,
auditioning, editing a playing pattern loop, stopping and restarting must remain
responsive and musically coherent. A deterministic file render alone is
insufficient. This review asks how much advance preparation those contracts need.
It does not authorize ORIGIN1B/C, callback changes, a new format, parser/effect/DSP
changes, AUv3/iPad implementation, altered gates, or closure of
[#516](https://github.com/syncomm/voodootrackerx/issues/516).

[ADR 005](005-software-mixer-core-language-boundary.md) preserves Swift
orchestration and the narrow C mixer boundary;
[ADR 006](006-windowed-offline-candidate-rendering.md) owns offline windows;
[ADR 009](009-xm-linear-period-sample-base-rate.md) owns adapter pitch conversion;
[ADR 010](010-whole-document-edit-undo.md) owns edit/Undo;
[ADR 011](011-post-v1-auv3-tracker-instrument-direction.md) owns post-v1 direction;
[ADR 012 Policy B](012-from-scratch-instrument-sample-composition-model.md#accepted-superseding-routing-clarification-policy-b)
and [ADR 014](014-loaded-xm-editable-copy-planning.md) preserve routing and loaded
source ownership. Their existing gaps are not silently repaired by this proposal.

## 1. Verified current architecture

Source keys below identify concrete owners at the base above; symbol names are
the stable navigation targets. The manager handoff seals detailed reader searches,
historical receipts and source notes outside git. Those local artifacts are
supporting evidence, never required build/test inputs.

| Key | Source and principal owners |
| --- | --- |
| P | [PlaybackSongAdapter.swift](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter.swift): `PlaybackSongSyntheticAdapter.adapt`, `appendEvents`, `AdapterRowContext`, `PlaybackSongSyntheticPlan` |
| T | [Traversal](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+Traversal.swift): `PlaybackSongTraversalPlanner.plan` / `nextPosition`; [timing](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+Timing.swift): `PlaybackSongFxxTimingPlanner`, `PlaybackSongFxxRowTiming.frame`, `PlaybackSongCanonicalTickClock` |
| H | [Envelope semantics](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackXMEnvelopeSemantics.swift): immutable `PlaybackXMChannelRow`, `PlaybackXMEnvelopeTimeline`; [audible targets](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackXMAudibleTargets.swift): `PlaybackXMAudibleTimeline` |
| A | [Adapter event plan](../../app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerAdapterEventPlan.swift): `make`, `assemble`, `RuntimeCMixerAdapterPlanAssembly.finish`, `RuntimeCMixerAdapterEventStorage` |
| E | [PlaybackEngine.swift](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackEngine.swift): `load`, `play`, `prepareRuntimeAdapterEventPlanIfNeeded`, prewarm request/job/result/scheduler, isolated-loop restore and editable-loop refresh |
| R | [RuntimeCMixerRenderCore.swift](../../app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerRenderCore.swift): `configureAdapterEventSchedule`, `render`, `applyQueuedAdapterEventLocked`, `appendNextAdapterEventLoopIterationLocked`, render lock; E owns seek orchestration and B owns runtime offset/follow |
| B | [RuntimeCMixerBackend.swift](../../app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerBackend.swift): `RuntimeCMixerAudioEngine`, `RuntimeCMixerDefaultOutputUnitHost`; [CSoftwareMixer.swift](../../app/VoodooTrackerX/VoodooTrackerX/CSoftwareMixer.swift): native bridge; [vtx_c_mixer.c](../../core/MixerCore/src/vtx_c_mixer.c): voice allocation/copy/free and render |
| O | [PlaybackSongOfflineRender.swift](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongOfflineRender.swift): `PlaybackSongOfflineRenderer`, source eligibility, continuation indexes, window scheduling |
| D | [PlaybackSongDiagnostics.swift](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongDiagnostics.swift), [RuntimeCMixerDiagnostics.swift](../../app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerDiagnostics.swift), [trace writer](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackTraceWriter.swift): diagnostic/inspection consumers |

**Observed flow:** metadata/parsing → `PlaybackSongBuilder` value model → T's
bounded executed traversal → Fxx exact-frame row timing → P's channel/effect
interpretation, source selection, release results and immutable row capture →
semantic pitch/envelope/audible timelines and source-eligibility indexes → A's
family event expansion, small-key sort and in-place permutation → R's lightweight
ordered queue references → native C mixer commands → DefaultOutput render.
Offline export consumes the same semantic plan but schedules bounded windows;
windowed *rendering* currently does not imply incremental *planning*.

E.load invalidates generations, stops/reset state, stores the song and immediately
schedules order-0 prewarm. The real serial worker checks cancellation around an
entire synchronous A.make. E.play first prepares/awaits/takes that plan, then
resolves its selected order/row. A.make still adapts `0..<song.orders.count`.
Generation/job identity and canceled-result checks prevent some stale publication; they do not
stop obsolete construction inside make. Pending jobs/results and restore state
are additional retention roots. A synchronous fallback can also build a plan.
ORIGIN1A's `initialPosition` seam is not yet supplied by normal live Play.

The alias `c_mixer`/`c_mixer_coreaudio` names one CoreAudio host; retired `av_audio`
falls back with diagnostics. It is not another candidate architecture. R maintains
runtime state/source generation, held output and cursor independently of UI timer
follow; E keeps transport and isolated-loop restore state. Loop edits build a
coalesced replacement and activate at the existing boundary. Explicit reset-seek
and restore have different owners from direct cold construction.

### Reader / owner / lifetime matrix

“Audio input” means a current execution dependency, including a producer of native
commands; a name containing “diagnostic” does not imply dispensability. Arrays use
CoW and shared immutable objects: a second reference is not necessarily a copy.

| Allocation / fields | Builder → current readers and purpose | Lifetime / rederivation / role |
| --- | --- | --- |
| Parsed song, patterns, instruments, exact keymaps and PCM | `PlaybackSongBuilder` → P, E, O, preview, editors/writer | Document generation; PCM must outlive native borrowing/copying. Parsing stays isolated; full event expansion is rederivable. Essential source values. |
| Traversal rows, loop anchors/counters, visited set and guard diagnostics | T → timing and P; diagnostics → D | Workspaces until adaptation, published mappings/diagnostics for plan. Can replay deterministic traversal; occurrence identity cannot be replaced by structural row identity. |
| Row exact frames/Fxx, row mappings, canonical tick clock | T/P → H/A/O, E/R follow/end/loop/seek, D | Plan lifetime through shared storage. Exact accumulator and occurrence order are execution inputs; complete future arrays are a representation choice. |
| `ChannelState` and immutable captures | P/effect producers → H, audible/pitch composition, A/O | Live mutable state lasts through construction; immutable `xmChannelRows` survive in the synthetic plan. Source identity, nil carry, silent clocks and writer order affect audio. Replay requires complete semantic state. |
| Selection facts, row-entry/delayed-reset facts, row exits, native writer spans, held/semantic pitch projections | P observations feed semantic/automatic pitch composition during construction; completed sparse evidence → provenance resolvers, diagnostics/tests and whole-plan copies | Retained by the synthetic plan; some records reference original children. Their presence is not evidence that the callback reads them, or permission to remove promised observations. |
| `xmChannelRows` grouping/history indexes and carried-instrument projection | H rebuild locals → envelope clock/state queries | Shared snapshot references; grouping/history indexes are temporary to rebuild, while original row objects survive in the plan. Present nil differs from absent row/final-tail fallback. Compact projection plausible; no safe deletion inferred. |
| Birth events / `eventMappings`, sample-buffer cache | P → A, H, eligibility and O continuation; D | Plan and indirect trigger values retain sample/mapping references. Birth `eventIndex` owns a generation, not an array position after sorting. Audio plus inspection. |
| Key-off/cut/retrigger/pitch/volume/global-volume families and release annotations | P effect helpers → A/H/O; D/tests | Audio-producing histories. Release is decided causally once, then projected backwards mechanically. Removing the projection requires every mapping/trigger/export reader to retain equivalent values. |
| Envelope/audible timeline arrays and per-event indexes | H → A native semantic/final-LR commands, O continuation, D | Plan lifetime; property observers can rebuild projections during construction. Sparse state may replace history only after exact frame/state proof. |
| Runtime plan's `plan: PlaybackSongSyntheticPlan?`, `events`, event storage/order entries, category union, loop metadata | A → E cache/restore, R preparation/loop, B offset/follow/diagnostics, O/test inspection | Shared immutable graph; queue replacement/reset must retain payload and references together. Main/worker/job/restore aliases can prolong roots after Stop. Full synthetic history survives because runtime reads timing/loop/diagnostic projections. |
| `id`, `scheduledFrame`, priority, `activeEventIndex`, action payload | A family writers → A ordering and R/native application/trace; O/tests | Numeric ID is plan-local and observable; source birth identity is separate. Current family-batched IDs depend on future counts. Exact frame/action/order required; do not renumber opportunistically. |
| `source`, channel, `syntheticTick`, categories, effect/parameter/volume bytes | P/A → ordering, R event/burst handling, B start filtering/follow/trace; D/full-JSON tests | Source/channel/tick are execution coordinates. Categories also affect initial-pitch-hold priority and burst classification; they cannot be stripped as logs. Command bytes and lexical category union serve inspection/exact tests; removal needs a reader/compatibility proof. |
| Queue descriptors, generation↔voice tables, active/retiring voices, native PCM | R/B → callback event dispatch and C render; capture/snapshot readers | Through consumption, release tails and quiescence; stopping document transport alone does not establish disposal. Native data/cursors essential; queue future horizon need not be song-sized. |
| Offline sample-payload cache and continuation indexes | O → fresh window mixers, continuation/capacity diagnostics | Offline session; immutable C-owned payload survives referencing voices. Current runtime still copies per voice. Not a runtime sharing guarantee. |
| Trace/capture/profiling arrays, strings, JSON and WAV buffers | D/R/O instrumentation → writers/comparison tooling | Session/flush/export lifetime; optional for normal audio. R's bounded diagnostic ring retains full event/indirect PCM references until drain/reset and belongs in retirement accounting. Callback capture uses preallocated storage. Do not confuse these with H's audio-producing histories. |

No history/diagnostic field is proposed for deletion. The sealed reader searches
cover repository consumers (including test/tool readers); dynamic host behavior
and a future removal-specific audit remain separate proof obligations.

### Thread and real-time boundaries

| Boundary | Current work and resource consequences |
| --- | --- |
| Main/UI → load/Play/Stop | Model/value refresh, cache admission/reset and synchronous make fallback can allocate, release aliases or wait. Main-actor completion admits by generation. None belongs inside render. |
| Serial prewarm/refresh worker | T/P/H/A allocate arrays/objects/dictionaries/sets, expand families, sort keys, permute storage and build indexes; ARC/CoW and rejected-result destruction occur here or at owning consumers. Cancellation only around make leaves long uninterruptible phases. |
| Control → R preparation | A builds ordering keys; B builds the sorted row resolver and filtered loop storage; R converts descriptors and protects install/reset with the render lock. Cache/restore/job/diagnostic aliases can keep old data alive during replacement construction. |
| CoreAudio callback → R → C | Try-lock; contention may replay the cached previous block or leave silence when unavailable/admission-silenced. Event lookup/Swift action dispatch and same-frame burst handling; loop refill allocates/appends descriptor arrays without sorting. Native trigger admission mallocs/sanitizes/copies PCM; source-stop/retirement paths can free native PCM. Dictionary mutation, ARC and loop-array disposal remain risks. Output/capture copying uses preallocated buffers; envelope attachment uses fixed C storage. C DSP is distinct from admission. |
| Offline/export | Worker/session allocation, caches, indexes, fresh mixers, PCM output and I/O are allowed off RT; not evidence that the runtime callback is safe. |

These identified boundaries are evidence of the open `VTX-D1-001` debt, not a
formal exhaustive RT audit. Any production candidate must move preparation,
sort, locks, allocation, logging and final disposal out of callback under a
separately approved contract; no Swift dynamic planner/DSP is proposed there.

## 2. Seven decision questions

| Question | Required / beneficial / implementation legacy / unknown |
| --- | --- |
| 1. Why plan? | **Required:** exact, ready commands/data before their render deadline; deterministic export and repeatable semantic state (ADR 005/006, P/T/A/R/O). **Beneficial:** lookahead absorbs producer jitter, checkpoint replay speeds seek, diagnostics explain effects. **Implementation legacy:** complete future graph before first sound, eager order-0 load prewarm, timer scheduling ancestry (ADR 003/004, E). Edit/Undo needs immutable document generations, not all future events (ADR 010). UI follow needs frame/occurrence mapping, not a full audio graph. Loops require state and ordered transitions, not whole-song lookahead. **Unknown:** sufficient horizon for qualified workloads/hardware and future hosts. |
| 2. What must be precomputed? | **Required before first sound:** selected origin/admission key, initial musical state, precise first frames, source routing/PCM ownership, initial envelope/output state, callback-ready commands and capacity for the admitted horizon. Preserve fractional timing arithmetic, birth/action ordering and execution-dependent categories. **Beneficial:** horizon checkpoints and producer slack. **Implementation legacy:** future per-tick histories, global sort and display-only category union before frame 0. **Unknown:** minimum global ID/count information needed to preserve A's observable family IDs without complete expansion. |
| 3. What may be incremental? | **Beneficial hypothesis:** tick/row state transitions, order traversal, sparse effect updates, event/window generation, local indexes, diagnostic projection and bounded checkpoints. **Required:** carry pending B/D/E6/EE state, exact clocks, channel turn order, tail/release state and identity across every split. An order boundary is not a reset. **Implementation legacy:** retaining every transition after consumption. **Unknown:** whether current family IDs and backward release projections admit bounded publication without a count pass or additional approved identity contract (A/H, `G32EventIDGuardrailTests`). |
| 4. What is playback history? | **Required:** only executed musical state influences continuous playback; a cold selected position uses fresh defaults. Same-pattern/same-channel E60 structural lookup is the narrowly accepted exception, without executing skipped cells. Warm continuation preserves Fxx, traversal/effect memories, carried instrument/source, pitch/volume, envelopes, cursor/direction, held output and release tails. **Beneficial:** deterministic replay/checkpoints. **Implementation legacy:** treating an order-0 future graph as selected-origin history. **Unknown:** complete warm resume/seek product policy beyond current bounded contracts; see invariants below and E/T/R. |
| 5. Future AUv3? | **Required accepted direction:** preserve headless deterministic engine and host-adapter separation under ADR 011; macOS first, iPadOS later. **Beneficial:** bounded per-instance prepared data and reproducible discontinuity handling. **Implementation legacy:** assuming standalone host/timer or application singleton owns time. **Unknown:** host-sync/Fxx policy, seek reconstruction limits, lifecycle admission and instance budgets. Apple APIs below specify render/resource/context behavior, not VTX's seek semantics or a whole-song planning requirement. |
| 6. Acceptable budgets? | **Required:** keep existing absolute gates and exactness; distinguish API return, planning, first audible sample, retained RSS, peak/overlap and callback deadlines. **Beneficial proposed targets:** Section 4. **Implementation legacy:** optimizing median make alone or counting reusable RSS as released graph proof. **Unknown:** approved tail/low-end/instance targets, acoustic latency, worker cancellation bounds and complete peak attribution. Historical reports E0–E5 do not answer them. |
| 7. Why select an architecture? | **Required:** matched semantic/native/PCM oracles, worst-case resource evidence, migration/rollback and explicit manager decision. **Beneficial:** A as a low-risk comparator, B/C/D as falsifiable spikes. **Implementation legacy:** selecting hybrid because it sounds balanced. **Unknown:** final winner; current evidence establishes costs and defects, not an optimal horizon or a measured alternative. |

## 3. Behavioral invariants and future assumptions

Cold entry and allowed traversal range are separate. Use full-song bounds when
later B/D may jump before the entry; a selected suffix bound must not silently
forbid that jump. Entry row is an array index; emitted coordinates retain source
row labels. Invalid explicit origins fail, without clamping. Cold frame 0 starts
from initial timing/channel defaults: unplayed Fxx/instrument/envelope/pitch state
cannot enter through prewarm, restore or a structural lookup. E60 anchors remain
pattern/channel scoped; counters start fresh. Once a skipped row is actually
reached through a loop/jump, its commands execute normally.

PR #545 and [ColdEntryTests](../../tests/vtx_render_bounded_xm/ColdEntryTests.swift)
qualify this direct seam. Older wording in the
[G38B discussion](../xm-effect-support.md#bounded-g38b-pattern-local-loop-and-traversal-policy)
that says every unplayed E60 is inert describes the general executed policy,
but omits the accepted cold-cursor structural exception. This proposal records
the distinction; scope forbids editing that authority or the historical issue.
Reconcile the wording in an authorized integration change; do not undo #545.

For warm continuation, a checkpoint must capture *semantic and physical* state:
document/revision, mode/rate, origin and traversal occurrence; exact-frame residue,
tick/held-row position, loop anchors/counters and pending position; instrument and
effect memories, silent envelope clocks, global volume/channel turn state;
source generations, fractional cursor/direction, ramp/envelope/fadeout/release
and final held pitch/LR targets. A musical checkpoint alone cannot restore C
voices or overlapping retirement tails exactly. Structural coordinates alone
are ambiguous after revisits.

Whole-song duration currently serves display and song-end scheduling (E/B and
AppDelegate). An incremental candidate must supply an explicit end marker/tail
policy and get approval for any initially unknown duration display; it cannot
silently discard that consumer. The diagnostic enum value `hybrid` in A describes
event-source attribution, not an implemented rolling/hybrid planning architecture.

Proposed reproducible resume rule: restore a compatible acknowledged checkpoint
on the *same executed path*, then replay off-thread without output to the target
occurrence/frame; otherwise report unavailable or use an explicitly requested
cold reset. Reset-seek must state its reset policy and never inherit an arbitrary
cached prefix. Seeking an unexecuted target has no unique warm history when
branches/loops revisit it: product policy is undecided, not “infer from order 0.”
Checkpoint identity includes semantic version and document generation; edits,
rate/mode/origin changes invalidate incompatible state. This is a proposed
future rule, not a claim that current snapshots implement full serialization.

Preserve same-row Fxx from tick 0, EEx's real held ticks/one fresh entry, B/D/E6
channel-write precedence, current finite traversal guards and intentional G38B
differences. Preserve strict-before source eligibility, exact missing-map
identity, release-at-execution decisions, source-less clocks, event IDs, stable
equal-frame writers and held/output state. Never lose a release/tail at a window
edge. Runtime/offline command frames and protected full values/PCM remain exact
within their existing qualified scopes; no new epsilon or tolerance is granted.
Relevant oracles include [FxxTimingTests](../../tests/vtx_render_bounded_xm/FxxTimingTests.swift),
[TraversalPrecedenceTests](../../tests/vtx_render_bounded_xm/TraversalPrecedenceTests.swift),
[CausalReleaseResultTests](../../tests/vtx_render_bounded_xm/CausalReleaseResultTests.swift)
and [G32EventIDGuardrailTests](../../tests/vtx_render_bounded_xm/G32EventIDGuardrailTests.swift).

### Apple obligations versus product choices

Apple's [renderBlock](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/renderblock)
supplies events for the render interval; the implementation provides
[internalRenderBlock](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/internalrenderblock).
The host sets [maximumFramesToRender](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/maximumframestorender)
before resource allocation and cannot change it while those resources remain
allocated. These APIs motivate prepared bounded buffers, not preplanning a song.
Apple's optional [transport context](https://developer.apple.com/documentation/audiotoolbox/auhosttransportstateblock)
reports timeline sample position and cycle bounds; its
[musical context](https://developer.apple.com/documentation/audiotoolbox/auhostmusicalcontextblock)
reports tempo/beat information. Retrieval can fail. VTX must design its own
absence/discontinuity policy. Apple [reset](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/reset())
addresses transitory rendering state at discontinuities such as seeks; it does
not specify XM effect-memory reconstruction.

ADR 011's host sync, internal-XM time, phrase triggering, project recall and
offline bounce require later mode decisions. Tempo ramps versus Fxx, PPQ anchor,
host-loop versus E6 state, arbitrary seek, sample-rate reallocation and suspend/
resume remain explicit unknowns. Multiple instances multiply private working
sets; immutable PCM might be shared only after ownership proof. No iPad memory
limit, AU instance count guarantee or host-ready implementation is inferred.

## 4. Resource budgets: fixed gates and proposals

| Status / endpoint | Threshold and interpretation |
| --- | --- |
| Existing, unchanged | Optional externally authenticated sentinel: planning p50 ≤972 ms, first-Play API p50 ≤1,000 ms. Accepted-heavy/public-heavy planning ≤2,333 ms where registered. Ordinary public modules near/under 1 s remains the expectation. Preserve original input/config/estimand; missing optional inputs are gaps. |
| Existing stress comparison | Versioned dense p50 3,629.260 ms misses its registered 2,333-ms comparison ceiling. Do not hide this or promote the pathological fixture into a new universal release gate. No Phase 2 performance closure follows. |
| Proposed nonregression screens | Historical +25-ms upper paired planning-CI and +32-MiB retained/peak screens remain campaign-specific proposals, not adopted absolute budgets or permission to fail a fixed gate. |
| Proposed study, initial audible output | On the eventually approved low-end desktop: small/representative workloads p50 ≤100 ms, p95 ≤250 ms, observed maximum ≤500 ms from gesture to first expected nonzero host output. Report silent lead separately; no acoustic/DAC claim without loopback. Stress latency remains separately reported, not waived by asynchronous API return. These are UX hypotheses, not current gates. |
| Proposed bounded graph / desktop | Carry forward ARCH1 study targets: event/history/window/checkpoint owners ≤128 MiB retained /192 MiB construction peak, including retired-but-owned buffers and diagnostics. Document PCM/native copies are separate explicit owners; proposed total app RSS ≤768 MiB retained /1,024 MiB fresh-process peak on an 8-GiB desktop includes them. Report loaded baseline and physical footprint separately. No arbitrary input-size guarantee. |
| Proposed producer / callback study | Test 250/500/1,000-ms windows; p99 production+publication+jitter <half the ready horizon, including density spikes. Cancellation p95 ≤50 ms /observed maximum ≤100 ms to quiescence and acknowledged retirement. Target callback worst observed time <half `frames/rate`, zero deadline misses, locks/allocations/disposals absent in a separately hardened callback. No new RT safety claim from a timing percentile. |

Measure total worker CPU, allocations/bytes and peak simultaneous old/new roots;
amortized producer work must stay below consumed audio time with the above slack.
RSS can remain high after freeing live allocations. Typed ownership, live malloc,
RSS, physical footprint and child `rusage` high water are different metrics.
No currently accepted absolute memory, cancellation, p95/tail, low-end hardware
or first-audible budget was found. Manager ratification and actual hardware
measurements are required before using the proposals as acceptance/rejection gates.

## 5. Alternatives, failure modes and kill criteria

All candidates preserve parser/read-only/edit/Undo boundaries, the C render core,
effect semantics, source identity, existing protected output and diagnosis.
No candidate is allowed to fix a deadline by doing dynamic Swift planning in RT.
Let N be visited channel/tick work, W the prepared horizon, C live state and D the
document/PCM. Loop guards remain global to traversal, not restarted per chunk.

| Candidate | Benefits / source seam / resource shape | New invariants, risks and measurable rejection conditions |
| --- | --- | --- |
| A. Optimized whole-song | Keep P/T/H/A semantics and global ID order; compact row values/indexes, narrow retained snapshots, reduce transient mapping/observer work and old/new overlap. Lowest semantic/migration risk; strongest immediate comparator. Time/storage still grow with N. Preserve full diagnostic visibility. | Prove every reader's value, avoid equivalent sidecars and CoW copies. Current 1,376,256 ×192-byte logical event payload alone is 252 MiB; actual backing ~369 MiB, excluding indirect triggers. Current dense row objects ~288 MiB. A 1,536→256-byte row target arithmetically saves at most 240 MiB before auxiliaries; no CPU/RSS saving measured. A hypothetical 32-byte command projection would use 42 MiB for those events, but fits no demonstrated schema and omits histories/PCM. Reject A as final only if authorized compact-owner results still miss fixed/ratified startup/peak targets or scaling, not merely because current structs are large. |
| B. Rolling execution window | A serial off-RT state machine traverses T/P by tick/row, fills callback-ready immutable byte-capped windows, publishes before low-water deadline. Local sort/index and diagnostics are window scoped. Ideal graph storage O(W+C), plus D and bounded retirement/checkpoints. Potential fastest startup and smallest future graph. | B/D/E6 choose next executed path, including backward jumps; no prefix replay or order reset. Byte cap as well as time cap handles dense short rows; tail/source state survives eviction. Test 250/500/1,000-ms horizons with cadence before half-horizon depletion. Reject if worst-case throughput/jitter lacks slack, identities require an unacceptable whole-song startup pass, callback work grows, or memory silently spills to full histories. Underflow policy must be approved: proposed explicit stop/silence at deadline with reported reason, never skip musical events, fabricate state or plan in callback. No such runtime behavior is authorized now. |
| C. Hybrid executed-state + windows | Separate compact durable semantic state/checkpoints from materialized execution windows; replay/offline analysis need not retain a future graph. Best provisional long-term study hypothesis for composition/seek and multiple instances. P/H's causal release and immutable-row seams are useful, but not already a resumable engine. | Distinguish producer speculative state from acknowledged executed frontier. Commit checkpoints only for a compatible path/generation; include physical/held/tail state or deterministic reconstruction. Bound checkpoints/history/indexes and optional diagnostic retention as well as windows. Family-batched future-count IDs, global volume writers and release back-projection are major obstacles. Reject if checkpoint/sidecar roots recreate O(N), native state cannot restore exactly, full-pass IDs defeat startup, or overhead/complexity fails to outperform A under ratified budgets. |
| D. Checkpoints + on-demand suffix | Keep qualified A assembly for a suffix reconstructed from sparse checkpoints. Smaller incremental step and potentially fast warm seeks; E/R/O restore seams provide a comparator. | Cold first Play has no executed checkpoint. Never use checkpoints from unplayed rows; suffix retains O(N) worst-case work/space, branches invalidate coordinate-only caches. Numeric IDs may still need prefix counts. Reject as final if checkpoint gaps or backward jumps reproduce full startup/peak, cache invalidation is ambiguous, or it requires two large graphs. Useful intermediate experiment even if not final. |

### Proposed event identity policy

**Current compatibility:** exact physical numeric IDs, skipped/reserved slots
and C14/G32 ordering are protected by existing tests and diagnostics. A/B/C/D
prototypes initially preserve these IDs and existing output unless and until
separately authorized. A assigns whole-plan family batches, including G32
intervals from future publication/request counts; a chronological counter alone
does not preserve those values.

**Fundamental product invariants:** deterministic musical state, source/voice
causality, stable writer ordering, unique trace correlation, precise planned/
applied frames and exact qualified PCM remain mandatory. Whether the particular
numeric encoding belongs to a public/documented interface is an open contract
question requiring a complete consumer/reader review, not an irrevocable musical
requirement established by this proposal.

Compare two feasibility lanes for rolling/hybrid complexity and latency:
(i) preserve current IDs through bounded counting/state and measure any unavoidable
whole traversal (O(N) startup CPU even with bounded storage); (ii) research a
separately versioned deterministic identity mapping, trace/diagnostic compatibility,
migration and tests. Lane (ii) is research only; no ID change is authorized.

**Decision gate:** before any revised-ID implementation, require a dedicated
manager/Gregory decision, complete reader-proof, compatibility plan and exhaustive
semantic/native/PCM regression evidence. No silent renumbering, output
normalization or weakening protected tests to make a prototype pass is authorized.

B/C must retain bounded execution evidence and support off-thread deterministic
replay/optional collection for full inspection/export, without a hidden live
whole-song diagnostic graph. D provides suffix evidence plus replay of omitted
history. If existing complete-plan APIs cannot preserve promised observations
under that separation, count the retained storage honestly or seek a separately
approved tooling contract. Bound both checkpoint count and retired-window count;
time lookahead alone does not bound density, PCM or long-lived release tails.

A/B/C/D have reversible in-memory prototypes behind existing seams; reversal
cost rises sharply after persisted checkpoint/identity formats or host recall
depend on them. No persisted schema is proposed. Keep A as oracle/fallback during
an authorized experiment without concurrent full graphs in production. Roll back
a candidate on exactness/lifecycle failure before tuning. Semantic state-machine
extraction, callback hardening, live-origin wiring and representation changes
remain separate reviewable contracts, not a combined engine rewrite.

## 6. Evidence ledger

F = source or sealed historical observation; I = inference; H = unmeasured
hypothesis; U = undecided requirement. Local detailed reports/raw receipts are
indexed in the ARCH2 handoff; missing historical inputs are explicitly excluded.
No benchmark, reference renderer, app, build or production test ran for ARCH2.

| ID / kind | Claim → provenance | Confidence / limitation |
| --- | --- | --- |
| E0 / F | R0 REPORT: parse/song 5–13 ms, load 16–31 ms, queue conversion 4.6–4.9 ms versus heavy full make seconds. Source E/A/R explains eager prewarm. | Medium, n=2 baseline; overlapping timings cannot be summed; not release qualification. |
| E1 / F | [R1 PR #541](https://github.com/syncomm/voodootrackerx/pull/541), sealed R1 REPORT: event stride 248→192 bytes; accepted-heavy planning p50 2,290.02→2,184.90 ms, old public-heavy 4,187.37→3,951.69 ms. [R2 PR #542](https://github.com/syncomm/voodootrackerx/pull/542)/REPORT: ~72 MiB category allocation removed, public timing CI includes zero. | High as historical statements, not current-base measurements. R1/R2 32 alternating pairs each; heavy strata n=8/10, small controls n=2. Retention/allocator effects differ across inputs; R2's sealed HOLD remains historical. |
| E2 / F | [R3B PR #544](https://github.com/syncomm/voodootrackerx/pull/544), R3A/R3B REPORTs: dense p50 3,832.581→3,629.260 ms; paired median −200.290 ms, 95% CI [−223.661,−153.582]; child malloc 288→141 MiB. | High historical, 10 dense pairs; 20,000 paired bootstrap draws, seed 20261109. Native x86_64 iMac20,2/i9-10910, 64 GiB, optimized Xcode Release, instrumentation off. Accepted-heavy CI crosses zero; broader effects mixed. No arm64/AU result. |
| E3 / F/I | R3A + ARCH1 owner inventories: row-object malloc 1,536 B; dense rows ~288 MiB; events ~369 MiB backing at capacity 2,015,274. Dense retained RSS ~2,819.53 MiB, child high water ~2,819.55 MiB in R3B. | High owner observations, medium extrapolation. Child peak includes helper processes; RSS sampled after Plays, not full heap attribution. 252-MiB exact-count event floor is arithmetic for current representation only. Snapshot compaction and candidate memory savings remain H. |
| E4 / F | ORIGIN1 Stage A WITNESS-SUMMARY/REPORT: normal Play inherits unplayed F01/instrument state. At Linear 48 kHz rows expected [0,5760,11520,17280], actual [0,960,1920,2880]; first PCM16 difference 961. E60 controls pass. | High actual Debug host evidence; 48 normal-Play captures across both modes/rates, 16 E60 controls; separate reset captures. Instrument case is source-identity evidence even when silent. Applied-frame deltas zero do not prove semantic correctness. No audible-latency measure. |
| E5 / F | PR #545, ORIGIN1A REPORT and ColdEntryTests: correct direct initialPosition, complete default-origin equality, both modes/rates. Live make/Play unchanged; versioned witness still gives six births rather than three. | High source/test evidence plus historical host captures. No ARCH2 execution or live fix; direct test pass cannot close #516. |
| E6 / F | A/H/O/E/R reader audit and source matrix: histories build audio; global IDs depend on future counts; callback has allocation/lock/disposal debt. | High identified dependencies; not an exhaustive RT proof or license to delete every unlisted field. |
| E7 / I/H/U | Complete future planning is not demanded by product contracts; bounded state/windows may improve startup/instances. Final horizon, identity solution, budgets and arbitrary warm seek remain unknown. | Medium inference about requirements, low confidence about implementation performance until matched experiments. Apple/ADR 011 do not choose the architecture. |

The absent historical R2 public-heavy XM is not silently replaced. The versioned
dense fixture is a different input. Typed headless malloc, app retained RSS,
child peak and instrumented nested CPU phases remain separate. In particular,
do not add inclusive row/event/publication timers or claim the accepted 147-MiB
child saving again. Historical R4 missing outputs remain gaps, not recovered data.

## 7. Provisional preference and reversal conditions

**Prefer investigating C, with low-to-medium confidence; retain A as the strongest
competing architecture and near-term comparator.** Whole-song future materialization
is incidental to most product requirements, while compact executed state is
valuable for composition/resume. This is a requirements inference, not measured
superiority. Current sources do not prove that a hybrid can preserve numeric IDs,
all physical state and sparse diagnosis with a bounded startup/working set.

The manager's hybrid preference is therefore premature as a final decision.
If A meets ratified latency/peak targets at acceptable complexity after compact
owner work, prefer A for standalone v1. If a count pass erases B/C's latency
benefit, physical restore needs whole histories, or sparse checkpoints duplicate
the graph, reject the hybrid. If checkpoints have no product benefit beyond
bounded sequential state, B may be simpler. If future host recall/seek requires
more state, obtain a specific product/API contract rather than expanding C by
assumption. No candidate wins by relabeling a partial plan as the old full-plan gate.

## 8. Minimal ARCH2 acceptance measurement plan — future authorization required

Preregister source/image/input hashes, build flags, exact endpoints, AB/BA order,
pair counts, bootstrap estimand/seed, exclusions and machine-pressure stop rules
before measurement. Preserve every attempt/outlier/failure; stop the registered
run rather than retune fixtures/gates or replace slow samples. Use uninstrumented
optimized Release for timing; allocation/profile overlays are separate campaigns.

| Axis | Minimal registered cells and evidence |
| --- | --- |
| Architectures/scenarios | Verified post-#545 baseline; authorized A compact-owner comparator; isolated B/C identity/state/window proofs; D warm-seek comparator if justified. Open-without-Play, cold Play immediately/after fixed delay, repeated Play, nonzero order/row, explicit reset, warm checkpoint replay, loop refresh, rapid origin/edit/rate invalidation and Stop during each expensive phase. |
| Mode/rate/block | Linear + Amiga; 44.1/48 kHz; VTX product and qualified FT2 diagnostic profiles kept separate; host blocks 64/128/256/512 plus irregular partitions. Offline full/window/native command events and actual host captures share bounds/settings; do not mix unmatched gain/tail/interpolation. |
| Hardware/scale | Historical native x86_64 machine for continuity; actual maintainer-approved low-end 8-GiB Mac and native arm64 qualification. Record CPU/OS/compiler/power/thermal/background load and actual host block size. Future 1/4/8 isolated instance projections are proposed stress cells, not AU promises; no iPad budget without approved device. |
| Small realistic | Committed public basic-instrument-sample, effect-memory and envelope-release-fadeout-timing fixtures; stopped selection, silent lead, held notes and resets. Small controls alone do not represent large composition. |
| Representative composition | Public pack routing, pattern loops/B/D/EE, delayed/retriggered sources, silent envelopes/global-volume writers and sustained tails; pin chosen filenames/hashes from the reviewed manifest. A larger sparse musical workload needs an original versioned public recipe before campaign admission; no private-derived synthetic conversion. |
| Pathological/dense | planner-dense-vibrato-v1; adversarial short-row/high-BPM loops, backward jumps, held rows, density bursts at split edges and long tails via separately reviewed recipes. No unlimited-allocation fallback. Optional private corpus uses externally supplied map/input and anonymous labels only; never mandatory CI or public provenance. |
| Timing/CPU sample plan | Proposed 30 independent fresh-process AB/BA pairs per primary workload/scenario; 100 starts for exploratory p95/maximum, disclose wide uncertainty and insufficient p99 support. 20,000 whole-pair bootstrap draws with preregistered seed/median estimator. Report p50/p95/max, all raw attempts and total/phase CPU. Continuous producer/deadline soak with density transitions is additional to startup sampling. |
| Memory/lifecycle | Sample load baseline, construction, ready, first sound, sustained run, edit overlap, cancellation, Stop and retirement acknowledgement. Record typed live/capacity bytes, indirect payloads, PCM/native copies, live malloc, app RSS/footprint and process high water; trace graph/chunk aliases and active/queued/retired roots. Never subtract unmatched process measurements. |
| Correctness / visibility | Exact causal state/source IDs, plan/event IDs and same-frame writer order, commands/planned/applied frames, full diagnostic values and PCM across partitions/windows. Compare matched pinned ft2-clone behavior under existing intentional differences; reference study may inform semantics but supplies no copied implementation. Replay/checkpoint differential tests include silent state/tails and invalidation. |

Instrument existing `AdapterPlanProfileSession`, playback lifecycle recorder,
runtime event trace/capture and native counters for producer phases/admission/
retirement. Future first-audible instrumentation must correlate gesture, make,
publish, first render, first expected nonzero sample and device/loopback time;
current API timings and PCM16 capture are not DAC latency. Callback duration,
lock/allocation/disposal probes must avoid contaminating release gate timings.
Required artifacts: preregistration, source/image/input receipts, raw paired rows,
all outliers, event/PCM diffs, memory ownership/high-water series, cancellation
latencies, callback/deadline logs and a sealed decision report under `/private/tmp`.

Reproducible mandatory recipe identities (generator
`scripts/generate-synthetic-xm-fixtures.py`, output under a newly verified
`/private/tmp/vtx-...` root):

| Manifest / version | Regeneration arguments / XM SHA-256 |
| --- | --- |
| [basic pack](../../tests/reference-xm/source/basic-instrument-sample.manifest.json), schema pinned by file | `--manifest tests/reference-xm/source/basic-instrument-sample.manifest.json --output-dir "$VTX_EVIDENCE_ROOT/basic" --write-xm --verify`; basic-instrument-sample `79d1643434db33e9f268cd25ac3135b2b3049ae9f00a46526eec8212bf8ea957`, effect-memory `0e20804e0bbf9aba449c58b76ab97ba93ec02429c5fa056ed26d8a118c43f168`, envelope-release-fadeout-timing `a83c9bc00d869b1415c886877ddc57094ec049db2d67b7973af4523b5712a60e`. Existing committed bytes checked in ARCH2. |
| [cold-entry-v1](../../tests/reference-xm/source/cold-entry-v1.manifest.json), fixture v1/schema 2 | `--manifest tests/reference-xm/source/cold-entry-v1.manifest.json --output-dir "$VTX_EVIDENCE_ROOT/cold" --validate --write-xm --verify`; `cf9255e9280ea6254177dbd4eea9ce66ef6defbb9192c1002226c9a00e9af7cc` (766 B). Pinned hash read; not regenerated in ARCH2. |
| [planner-dense-vibrato-v1](../../tests/reference-xm/source/planner-dense-vibrato-v1.manifest.json), generator revision 1/schema 3 | `--manifest tests/reference-xm/source/planner-dense-vibrato-v1.manifest.json --fixture planner-dense-vibrato-v1.xm --output-dir "$VTX_EVIDENCE_ROOT/dense" --write-xm --verify`; `f845b2b695db526fdcbef4924a598920779fd2b3f6d2028ac0559b67b554cd67` (983,959 B). Pinned hash read; not regenerated in ARCH2. |

Prefix each recipe with `env TMPDIR=/private/tmp TMP=/private/tmp TEMP=/private/tmp
python3 -B`; create and validate the absolute evidence root before running it.
Amiga flags variants need separate immutable receipts. Follow the
[public fixture provenance instructions](../../tests/reference-xm/README.md#versioned-performance-workload).
Future mandatory representative recipes require reviewed versions/hashes before
they become campaign dependencies; they are a named readiness gap today.

Decision gates, in order: approve requirements/budgets and missing recipes;
prove reader/state/ID equivalence; measure A's remaining floor and B/C's throughput,
startup and bounded ownership; pass exact protected runtime/offline/host evidence;
qualify cancellation, overlap and separately hardened callback; obtain manager's
explicit architecture decision. A proposed study or a faster API return passes
none of these by itself. Preserve the legacy full-plan planning measurement and
fixed ceilings alongside any new horizon-ready endpoint pending approved equivalence.

## 9. ORIGIN1B/C and later work

ORIGIN1B's **ownership contract is architecture-neutral**: immutable document/
revision/rate/origin/mode/version key, one active producer and one latest scalar
request, cooperative abort, stale-result admission, bounded outstanding roots,
quiescence and off-RT retirement acknowledgement are needed in A/B/C/D.
Its original **full-plan mechanism is not neutral**: threading cancellation
through every whole-song builder/observer and global sort/permutation, keeping a
graph-valued pending result, or restoring another complete graph could become
throwaway machinery or harden the wrong ownership model.

Recommend an intervening bounded identity/state/ownership design investigation
before authorizing a broad ORIGIN1B implementation. Specify producer/retirement
tests independently of full-plan versus window results; retain real-worker tests
and cancellation at expensive phase boundaries. Do not claim a serial queue or
pre/post token check bounds cancellation. Reject comparator exceptions as a
shortcut for canceling a mutating sort. Reuse required lifecycle mechanisms, but
keep whole-plan result/cache policy replaceable. This recommendation revisits
the earlier split's design only; it authorizes no patch.

ORIGIN1C remains necessary whatever candidate wins: resolve authoritative selected
origin before preparation, admit by the qualified key, avoid wrong-origin prewarm
and duplicate graphs, integrate reset/loop/edit paths and verify actual Play,
source/frame/PCM and memory. ORIGIN1A does not close it. Compact-row snapshots
need their own reader/value proof and allocation accounting; a streaming spike
needs its own ID/frontier/physical-state proof. Neither is silently bundled into
origin correctness, callback safety, effect semantics or AU preparation.

**NO-GO:** no architecture accepted; no live-origin fix or callback change; #516
and Phase 2 resource/release gates remain open. No runtime/test/roadmap/AGENTS or
other ADR changes, benchmark campaign, commit, PR, issue mutation, push or merge
is authorized by this document.

## 10. Living decision log

| Date / state | Decision scope / evidence that permits a change |
| --- | --- |
| 2026-11-09 local / PROPOSED | Independent post-#545 assessment. C is a study preference; A remains strongest comparator. New budgets and checkpoint/underflow rules are proposals only. |
| Pending / not accepted | Gregory/manager may ratify requirements and a minimal campaign, recording exact input/hardware/endpoint scope and fixed versus new gates here. |
| Pending / no architecture selected | Record A/B/C/D result and rejection reasons only after identity/state/resource/callback decision gates; retain contrary evidence and uncertainties. Accepted ADR amendments or persisted identity/state changes require their own approval and compatibility contract. |

Update this record when requirements or decisive evidence changes, not with PR
chronology. Every change must label facts, inferences, hypotheses and approvals;
an accepted decision must state residual owners, rollback boundary and gates.
