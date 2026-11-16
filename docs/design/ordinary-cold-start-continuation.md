# Ordinary cold-start continuation

## Status and authority

**CLOSED on the PR branch; acceptance gates remain explicit.** This bounded PR #552 repair
prepares a changed ordinary Play origin off Main through the existing native
two-slot channel. Gregory approved its versioned finite-song diagnostic IDs,
conditioned on source, timing, ordering and PCM preservation. That decision is
accepted; compatibility, semantic/PCM controls and local Debug/Release workflow
qualification are complete. Acceptance requires green final submitted-head
normal/native CI and Gregory's composition/listening review and merge.
ADR 015 remains PROPOSED. No memory waiver, backend freeze or wider release
closure follows from this contract.

An unchanged admitted full plan remains reusable at its compatible cold origin.
A different order/row needs fresh cold semantics, including only the accepted
same-pattern structural E60 seam. Reusing unplayed history to force a cache hit
is not permitted. Navigation and editor focus preserve an unchanged editable
snapshot's identity; a real content edit leaves the snapshot stale.

SONG TIME is document metadata, separate from the selected-origin mixer plan.
Open and editable timing changes schedule the shared traversal/Fxx reducers on a
metadata worker, retaining scalar timing state and no sample payloads or mixer
events. A brief pending `--:--` is replaced by the exact whole-song, pre-tail total
for finite traversal; ordinary playback Loop does not change that total. The
48 kHz row-end floor matches the legacy duration arithmetic. No estimate is
presented as exact. Missing/no-playable content, cycles, traversal guards and
overflow remain unknown; an explicit B/D exit beyond the final order is finite.
Navigation, focus, sample-only changes and transport controls retain the value.
Timing changes, Undo/Redo and document replacement reject stale worker results.
Current rows and ticks continue to come only from the C playback head.

## Preparation and admission

Product `requestPlay` resolves document/source generation, cold order/row, rate
and mode before scheduling the existing serial preparation worker. Main returns
while the bounded first interval and successor are prepared. A finite terminal
first batch needs no successor. The UI exposes preparation and keeps Stop
available; it does not synchronously join a full-song constructor for a changed
ordinary origin.

Request identity, transport epoch, source generation and the current document
admission predicate protect the asynchronous result. Stop, seek, replacement,
newer Play and content changes reject stale work. Reentrant callbacks cannot let
an older request cancel a newer admitted source. An installed but superseded
native generation is quiesced before its replacement session is prepared.
Ordinary same-origin full-plan reuse and explicit user Loop retain their
established paths.

The existing traversal reducer, row interpreter, timing reducer and semantic
folds execute finite B/D/E6/EE/Fxx traversal across orders, including backward
targets and the existing row/cycle guards. An order boundary is not a musical
state reset. Bounded checkpoints carry fractional frames, held channel/global
state, modulation, envelopes and original source-birth bindings. Only native
acknowledged execution advances the durable frontier.

## Native rows, ownership and successful end

`RuntimeLoopNativeScope.transportKind` distinguishes `explicitLoop` from
`finiteSong`. Scope/generation/epoch/rate/mode and predecessor/frame continuity
remain exact. Explicit Loop retains its current-pattern validation and wrap;
finite delivery validates each row against the exact source order and pattern.
The producer supplies one bounded row-array index per executed row. Storage
checks that index against the corresponding source row label, preserving
nonidentity labels without a second song graph or a full-song label index.

`Batch.endFrame` is the exclusive musical/checkpoint boundary.
`Batch.runtimeEndFrame` adds the explicitly supplied existing song-tail duration
only for a finite terminal batch. Its native `finiteSongEndFrame` marker keeps
those boundaries distinct. Final prepared commands include the musical-end
writer and any admitted tail writers; follow holds the final musical coordinate
through the tail. The default tail remains three seconds, with the existing
configuration policy unchanged.

At the actual tail deadline, Core uses the ordinary song-end/tail-stop operation
to clear C voices **before** the channel publishes retirement and permits PCM
owner reclamation. Admission reports `.completed`, separately from successor
failure. `consumeRuntimeSongContinuationCompletion()` yields one scalar scope /
musical-end / runtime-end receipt off audio. Cleared-C silence continues the
normal sample clock after that boundary; the final follow survives payload
retirement. No new end-of-song fade is introduced.

A missing required nonterminal successor still seals admission, performs the
existing five-millisecond C retirement and reports a fault. Successful finite
completion never enters that fault path. All command preparation, allocation,
source-domain validation and payload disposal stay off the callback. The same
one-active / one-successor ownership bound remains in force.

## Approved diagnostic compatibility

The public
[`testUnchangedEarlyOutputTargetIDDependsOnLaterNoteCount`](../../app/VoodooTrackerX/VoodooTrackerXTests/RuntimeCMixerTests.swift)
pins why a bounded prefix cannot reproduce every legacy whole-song numeric ID:
identical early output targets receive different legacy IDs when a later note
changes family counts. The accepted resolution is explicit versioning, not a
silent rewrite of the existing ID domain or a second future-counting pass.

Finite continuation records use `schemaVersion: 2` and
`nativeTransportKind: "finite_song"`, with exact scoped occurrence and source-birth
keys. Numeric event IDs remain immutable within their bounded plan; full scope,
batch sequence and original event ordinal distinguish occurrences. A carried
source keeps its original generation/epoch/birth-sequence/index, independently
of the successor's local lookup. No synthetic trigger or identity substitution
is allowed.

Legacy full-plan records and explicit Loop v1 records remain unchanged. The
scope transport-kind field is omitted for explicit Loop. Readers partition the
versioned finite domain and reject an unscoped full-plan identity oracle for it;
raw numeric IDs alone cannot join those domains. Source routing, effect writers,
command order, actual native frames and PCM retain their existing contracts.
See [format compatibility](../format-changes.md) and
[trace interpretation](../playback-trace.md).

## Qualification and acceptance

Public in-memory controls compare finite traversal, exact Fxx/fractional timing,
per-tick semantic state, source births, event payload/order and PCM with the
existing full-plan oracle. Producer controls include both rates and pitch modes,
irregular row caps, E60/E61, B/D, carried pitch/global memory and the terminal
writer through the default tail. Native controls cover terminal versus underrun,
exact C clearing before owner retirement, post-deadline silence/clock, retained
terminal follow and cross-order labelled-row rejection controls.

Local qualification covers repeated actual-app workflows on ordinary Debug and
optimized Release, responsive Main during preparation, constructor/cache evidence,
first actual C-host output timing, finite automatic tail Stop after a real edit,
and absence of native delivery faults. The unchanged Release workflow includes
at least ten cached replays. Codex owns final submitted-head native arm64
ASan/optimized Release with protected expected traps and normal CI; Gregory owns
physical composition/listening acceptance, including Open-time duration and edit
refresh. Existing 972 / 1,000 / 2,333 ms planning and First Play
API p50 gates remain unchanged; API return is not audible output or a DAC clock.
Component ownership bounds do not establish an absolute whole-app memory budget
or erase the provisionally disclosed mixed resource profile.

Gregory retains final hands-on composition/listening acceptance and the merge
decision. Those obligations remain open after automated qualification.
