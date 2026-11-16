# User pattern Loop: executed-state continuation

## Status and scope

**CLOSED — bounded PR contract; acceptance remains conditional.** Cold live
entry, executed user Loop and precise C-head transport use the behavior below.
Implementation and local suite qualification are complete. The observed mixed
resource profile is provisionally authorized for PR submission/native CI only;
it establishes no memory budget or whole-app improvement. Codex owns required
green final submitted-head native arm64 ASan/Release CI. Gregory owns final
Loop-on composition/listening review and merge acceptance. Issue #516 disposition,
low-end-memory qualification, Phase 2/v0.5 release gates and backend freeze remain
OPEN. ADR 015 remains **PROPOSED**. This separate focused authorization preserves
ordinary non-Loop full-song planning and grants no new performance exception.

## Cold entry and traversal

Normal Play and reset-seek resolve the selected order/row before preparation.
Reuse requires the same source, origin, rate and mode; full traversal bounds
preserve later backward jumps. Explicit user Loop interprets the selected-row
suffix first, then starts subsequent pattern occurrences at row 0.

The existing row interpreter, traversal reducer and semantic folds own effects.
E6 anchors/counters survive batch splits and reset at natural pattern entry.
Accepted G38B remains pattern-local: E6x uses that channel's applicable E60 or
implicit row 0 in the current pattern. The existing same-pattern/channel
structural E60 cold-entry seam is preserved. E64 does not return to a previous
pattern. G38A B/D/E6/EE writer precedence and same-row Fxx timing are unchanged.

Same-order forward B/D targets remain represented. An outgoing order transition
or existing finite traversal guard completes the selected user-loop iteration;
explicit Loop then starts row 0. Original refusal/guard diagnostics remain
visible. This transport policy does not broaden module-defined indefinite replay,
header restart behavior or FT2 parity.

## Precise playback-head authority

Normal full-plan and explicit user-Loop playback derive live transport position,
effective speed/BPM and follow presentation from one C-head observation. UI timers
choose publication cadence; they do not advance an independent musical timeline.
The same value updates Engine state and UI, including held EE/Fxx ticks and jumps.
Legacy timer traversal remains available to non-C/mock outputs.

Stop/Pause first quiesce the existing host and capture the native head before
Core reset destroys its geometry. Stop supplies that position through the existing
stopped-navigation callback; Pause publishes the captured follow and retains its
resume context. A newer load/seek/Play intent wins reentrant teardown/publication.
Editable active follow stays transient; stopped navigation uses its existing
coordinator without a content edit or Undo entry.

Raw runtime frame means the next unrendered C sample, not the CoreAudio device
or audible clock. After fault retirement completes, further silence buffers do
not advance that C frame. Row intervals are right-open;
there is no frame-minus-one correction. Normal follow retains its mapped planned
frame separately from raw runtime frame. A normal end timer only wakes service:
Stop requires the actual mapped head to reach the existing song-end plus tail
frame, preserving the established tail/grace policy. The capture result distinguishes captured, notRendered and unavailable. Terminal
fault follow clamps the last musical coordinate with explicit status; unavailable
capture is tagged as last-known and keeps that row as Pause's fallback resume
context, without claiming a fresh exact head. See the
[diagnostic status contract](../format-changes.md#native-c-playback-head-diagnostics).
This uses the current DefaultOutput host and C mixer; no AUv3 implementation or
new callback/effect interpreter is introduced.

## State and native continuity

Each batch uses fresh bounded interpreter scratch. Its checkpoint carries terminal
channel/global memories, exact speed/BPM and fractional frame accumulator,
envelope segments/key/fadeout, held/base/output pitch and modulation clocks.
Required source lookup records preserve exact instrument/keymap/sample identities
and eligibility. Scalar input observations retain their original scoped
provenance; they are not executed selections, resets or source births.

No checkpoint retains a parent context, plan, growing event history or checkpoint
chain. Full row captures retire after semantic extraction and before native event
assembly; ordinal ownership survives for inspection of runtime results. Native
C voices preserve their fractional cursors, interpolation, onset and retirement
progress through wrap and batch admission. Only actual commands change them.

## Identity and delivery

Numeric event/source IDs remain immutable plan-local keys. Ordinary full-plan
allocation and existing JSON/PCM controls retain their meanings. Additive document,
source, transport, rate/mode and batch scope distinguish occurrences; carried
commands bind to the exact earlier birth sequence/index. Lookup import never
emits a note trigger, and stale commands are not redirected by channel.

The existing serial preparation worker owns one active native batch and at most
one preparing/ready successor. It reserves the successor slot before interpreting
or allocating its native storage. Exact scope, predecessor state and contiguous
native frames govern admission. The render owner acknowledges actual consumed
intervals independently of UI notifications; speculative checkpoints never advance
that frontier. Disposal and PCM-cache retirement occur off audio after native
acknowledgement or host quiescence and C reset.

The callback consumes immutable native-ready commands and row/follow metadata.
It does not interpret effects, construct graphs, sort events or dispose batches.
The fixed occurrence ring reports dropped observations explicitly, and the existing
consumed counter retains its raw-unique-ID meaning. See the
[additive trace compatibility contract](../format-changes.md#native-user-loop-runtime-trace-scope).
Broader callback real-time-safety debt remains separately owned.

## Edits, cancellation and faults

Compatible editable pattern revisions coalesce into one current request. The
worker selects the first safe eligible natural boundary under measured replay/build
readiness and mandatory-fallback reserve guards. Native delivery admits only that
exact boundary/token for the latest ready request, retaining actual executed prefix
state and original source births. This can be later than the first raw natural
boundary observed after readiness. A newer request revokes stale candidates
immediately; readiness/deadline misses retain valid ordinary fallback delivery
while the latest request retries under those guards. Incompatible scope, catalog,
shape or initial-tempo changes stop explicitly and require cold reload/retry. Live Fxx cell edits retain executed
warm timing. Stop and reset-seek revoke pending work and preserve document recovery.

A real exact-boundary missing successor seals admission, completes the existing
C-owned 5 ms source retirement, then silences. Planning-underrun Stop is published
asynchronously after that retirement; late successors are rejected. This is fault
handling. Supported qualified ordinary workloads have zero unintended underruns.
A ready successor is admitted even when MainActor follow/service is delayed.

## Qualification boundary

The four-row selected-row-2 counterexample now matches independently expanded
execution, including the former frame-18,241 stale-source divergence. Both
frequency modes/rates, every-tick state/source/native frames/PCM, held Fxx/EE and
accepted B/D/E6 traversal, envelopes, modulation, completion, replacement tails,
rapid edits, cancellation and injected producer failures have focused coverage.
Unrelated-order scaling and long-run checkpoints demonstrate bounded live roots
and capacities; whole-app retained/peak measurements remain distinct from those
component bounds.

Coupled Session/native-delivery runs on public in-memory fixtures compare PCM
with an uninterrupted oracle while sampling producer/checkpoint, slot and cache
roots at acknowledged phases and after Stop. They demonstrate bounded plateaus
and release. Component ownership evidence remains distinct from process RSS,
physical footprint and cumulative allocator measurements. New resource costs from
this contract remain in scope for matched qualification: broader historical RSS
debt grants no waiver for material regressions, and component bounds do not
replace whole-process resource evidence or the original gates.

[Precise live/Stop/Pause lifecycle tests](../../app/VoodooTrackerX/VoodooTrackerXTests/LoopEngineLifecycleTests.swift),
[Production semantic tests](../../tests/vtx_render_bounded_xm/UserLoopProducerSemanticTests.swift),
[production PCM tests](../../tests/vtx_render_bounded_xm/UserLoopProducerPCMTests.swift),
[native batch/Core tests](../../app/VoodooTrackerX/VoodooTrackerXTests/RuntimeLoopNativeBatchStoragePCMTests.swift)
and [edit cutover tests](../../app/VoodooTrackerX/VoodooTrackerXTests/RuntimeLoopNativeEarlyCutoverTests.swift)
pin this bounded contract. Original full-planning p50 gates remain 972 ms sentinel
planning, 1,000 ms sentinel First Play and 2,333 ms registered accepted-heavy
planning. Local suite qualification is complete. Focused source/native/PCM and
coupled-ownership proofs do not replace required green final submitted-head
native arm64 ASan/Release CI (Codex) or Gregory's Loop-on composition/listening
review and merge. The mixed resource profile is provisionally accepted only for
PR submission/native CI, without a new memory, p95, cancellation or deadline
budget. Broader low-end-memory qualification and release gates remain OPEN;
PR-branch bounded closure does not waive these acceptance obligations.
