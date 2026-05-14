# Local Audio Comparison Findings

This template is safe to commit while blank. Filled reports that include local
module paths, generated WAV paths, comparison output, traces, screenshots,
listening notes, or findings derived from `_DARKL.XM` must stay local and out
of git. Prefer `/tmp/vtx-local-reference-comparison` or another ignored local
output directory.

## Run Summary

- Date:
- Operator:
- Purpose:
- Module path used locally:
- Bounded target:
- Local artifacts directory:

## Reference Render

- Renderer:
- Renderer version:
- Command/settings:
- Reference renderer command/workaround:
- Sample rate:
- Channels:
- Bit depth / output format:
- Interpolation / ramping / compatibility settings:
- Bounded duration or range:
- Reference WAV path:

## Candidate Render

- VoodooTracker X branch/commit:
- Candidate render path:
- Render helper:
- Candidate render helper command:
- Candidate WAV path:
- Sample rate:
- Channels:
- Requested frames or duration:
- Bounded order range:
- Bounded row range:
- Adapter notes:

## Comparison Run

- Tool:
- Command:
- Comparison JSON path:
- Comparison Markdown path:
- Seconds analyzed:
- Window size:
- Top window count:
- Format compatibility notes:

## Top Mismatch Windows

| Rank | Time Range | Frame Range | RMS Difference | Max Abs Difference | Local Notes |
| --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  |
| 2 |  |  |  |  |  |
| 3 |  |  |  |  |  |
| 4 |  |  |  |  |  |
| 5 |  |  |  |  |  |

## Observed Likely Mismatch Categories

Mark only categories supported by comparison output, listening checks, traces,
or source-to-synthetic diagnostics.

- [ ] timing / `Fxx` / row duration
- [ ] order traversal / pattern break / position jump
- [ ] panning / volume-column behavior
- [ ] volume slides / envelope / fadeout / key-off
- [ ] pitch / finetune / relative note / linear frequency
- [ ] interpolation / resampling
- [ ] sample offset / retrigger / note cut / note delay
- [ ] loop behavior
- [ ] unknown / needs trace correlation

## Evidence Notes

- Metric summary:
- Trace or diagnostics correlation:
- Subjective listening notes from Gregory:
- Local reproduction notes:

## Possible Next PR Candidates

Choose one narrow follow-up. Do not combine unrelated fixes.

- [ ] Adapter Support for Specific Effect X:
- [ ] Focused Pitch/Period Accuracy Pass:
- [ ] Local Trace-to-Comparison Correlation Report:
- [ ] Additional Volume-Column Semantics:
- [ ] Loop/Interpolation Investigation:
- [ ] Bounded Order Traversal Improvement:
- [ ] Feature-Flagged Runtime Backend Skeleton only after enough offline confidence:

## Artifact Safety Checklist

- [ ] `_DARKL.XM` was not committed, copied into fixtures, uploaded, or used in automated tests.
- [ ] Candidate/reference WAVs remain local and out of git.
- [ ] JSON/Markdown comparison reports remain local and out of git.
- [ ] Playback traces, screenshots, logs, and listening notes remain local and out of git.
- [ ] The committed PR contains only source, tests, templates, and documentation intended for review.
