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
   The family-batched ID allocator depends on future event counts; if exact IDs
   require a full traversal pass, stop the spike and seek an explicit identity
   decision. No silent renumbering or diagnostic compatibility change is allowed.

## Minimal proof and decision gates

The first proof extends the existing traversal state with a finite-song mode and
splits a public two-order song into deliberately short batches. It compares the
concatenated visited source positions, Fxx frames, B/D/E6 outcomes, stop reason,
and guard behavior against `PlaybackSongTraversalPlanner.plan` from the same
cold order/row. It must also show that an explicit user Loop still wraps at its
old boundary. This proof does not enable playback.

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
