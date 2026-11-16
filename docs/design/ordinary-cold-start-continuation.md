# Ordinary cold-start continuation spike

## Status and boundary

**PROPOSED proof of concept for PR #552.** Gregory authorized investigation of a
bounded cold-start continuation after a reproducible changed-row Stop→Play wait.
This note does not accept ADR 015, change the current runtime path, or waive any
semantic, source-ID, PCM, memory, planning, or native-host gate. The first proof
must use public in-memory fixtures and remain reversible.

The observed large-song Debug path correctly changes cold origin from the played
start to the C-head row captured at Stop, then waits on another full-song plan.
Keeping the old plan would execute history from rows the new cold start skipped.
The same-origin admitted plan remains valid and should be reused unchanged.

## Proposed narrow path

1. A normal Play request selects an exact document/source generation, order, row,
   rate, and mode before work starts. A different cold origin starts with fresh
   musical state, including only the accepted structural E60 seam. Stop, seek,
   replacement, and edits revoke stale requests by the existing intent/epoch key.
2. The existing serial preparation worker builds a bounded first interval with
   `PlaybackSongTraversalPlanner`'s position reducer, the existing row interpreter,
   timing reducer, semantic folds, adapter assembly, and native batch converter.
   It prepares a successor before admitting output; Main receives only a ready
   notification and never joins a full-song constructor. This is a distinct
   normal-song transport mode of the existing two-slot native channel, not an
   explicit pattern Loop or a second effect interpreter.
3. A finite traversal follows B/D/E6/EE outcomes across order and pattern
   boundaries, including backward targets and the existing global row/cycle
   guards. An order boundary is not a musical-state reset. Each batch retains
   exact fractional timing, held channels, source-birth bindings, envelope and
   output state in the existing bounded checkpoint. Only native acknowledged
   execution advances the durable frontier. A speculative future cannot seed a
   cold seek or an edit.
4. A normal terminal batch carries an explicit successful end marker. It does
   not wrap to the selected pattern and does not ask for a successor. The C host
   completes the current song-end/tail retirement before Stop, using the current
   C-head follow authority. Missing a required nonterminal successor follows
   the already established 5 ms native retirement and reports a distinct fault;
   the test must prove no such fault in qualified ordinary workloads.
5. The current full plan remains the reference oracle and the same-origin cache
   path. No product cutover occurs until bounded batches match full-plan
   semantics, source identity, native frames, PCM, and exposed numeric event IDs.
   The family-batched ID allocator depends on future event counts. No silent
   renumbering or diagnostic compatibility change is allowed.

## Proven numeric-ID constraint

The public
[`testUnchangedEarlyOutputTargetIDDependsOnLaterNoteCount`](../../app/VoodooTrackerX/VoodooTrackerXTests/RuntimeCMixerTests.swift)
constructs two songs with identical early rows, routing, sample, event source,
frame, action and categories. One song has an extra later note. Their *early*
audible-output-target numeric IDs differ under the current whole-song planner.
The focused ordinary Debug test passes. A producer that sees only the early
prefix therefore cannot assign both legacy IDs exactly. This proof does not
measure the cost of a separate count pass.

The current ID is an ordering tie in adapter storage, a planned-event trace
field, and a raw-unique consumption key in the backend. Native Loop uses its
batch-local ID for an executed-ID bitset and combines scope, batch sequence and
event ordinal for occurrence identity. Runtime trace tests and correlators join
normal `plannedEventID` to full-plan events; Loop tooling rejects an unscoped
join. The Loop birth scope already protects native source causality, but does
not make its batch-local numeric ID equal the normal whole-song ID.

An exact pre-count would need the future family counts, including executed
note/route outcomes, semantic publications and G32 reservations. B/D/E6
traversal and effect/semantic state influence these counts; a metadata-only
count is insufficient. Its runtime cost remains unmeasured and must be tested
against the first-output goal. A versioned scoped diagnostic ID policy for
ordinary continuation needs Gregory's explicit approval, reader audit,
`docs/format-changes.md` design entry, and compatibility tests. Product cutover
waits at this decision gate.

## Minimal proof and decision gates

The no-cutover finite traversal proof now extends the existing traversal state
and splits a public two-order song into one-, two-, and three-row batches.
[`UserLoopTraversalContinuationTests`](../../tests/vtx_render_bounded_xm/UserLoopTraversalContinuationTests.swift)
compares visited source positions, B/D/E6 diagnostics, exact Fxx frames, stop
reason, and cycle/row guards with the existing whole-song planner. It also
checks that explicit user Loop still wraps at its old boundary. The focused
SwiftPM Debug suite passes all 12 tests, including the two new finite cases.
This proves only traversal/timing parity for these public fixtures. Empty-order
diagnostics, semantic folds, native frames/PCM, event IDs, and product admission
remain unproven; no playback path or diagnostic ID policy changes here.

Only after that parity passes should a second proof run the existing producer's
row interpreter/folds over a cross-order batch and compare per-tick state and
native PCM with the full-plan oracle. Production admission additionally needs:

- a finite scope and native row validator that accept exact order transitions
  without relaxing generation, sample, or source-birth checks;
- an acknowledged terminal success distinct from successor underrun, with
  current song-end/tail and Stop/Pause behavior;
- bounded first-frame and successor readiness measurements on Debug, optimized
  Release, and native arm64 ASan, with Main stall duration and actual host frames;
- unchanged same-origin constructor count, exact source/event IDs, semantic and
  PCM controls, no normal underruns, and no regression to the existing fixed
  planning gates;
- ownership evidence that two native slots and their bounded checkpoints do not
  accumulate a hidden full-song graph or materially worsen the provisional
  process memory profile.

The practical first-patch limit is traversal parity and a no-cutover producer
proof. Crossing native mode, terminal, and ID boundaries before these pass would
turn this regression repair into an unqualified runtime redesign.
