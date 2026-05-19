# Local Audio Comparison Findings

This template is safe to commit while blank. Filled reports that include local
module paths, generated WAV paths, comparison output, traces, screenshots,
listening notes, or findings derived from private/local XM modules must stay local and out
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
- Candidate diagnostics JSON path:
- Sample rate:
- Channels:
- Export gain:
- Export headroom dB:
- Pre-export Float32 peak:
- Pre-export per-channel peak:
- Pre-export overrange sample count:
- Pre-export RMS:
- Post-gain peak:
- Post-gain per-channel peak:
- Post-gain RMS:
- PCM16 clipping/clamping count:
- Post-gain PCM16 clipping detected:
- Clipping recommendation:
- Requested frames or duration:
- Bounded order range:
- Bounded row range:
- Normal note cells:
- Scheduled events:
- Skipped notes:
- C mixer scheduled voice capacity:
- C mixer active voice capacity:
- Scheduled voice attempts:
- Scheduled voice accepted:
- Scheduled voice rejected:
- Scheduled capacity rejects:
- Active capacity rejects:
- Invalid scheduled voice rejects:
- Rejected event coordinates:
- Long-render scheduling note:
- Windowed render enabled:
- Window rows:
- Window count:
- Windowed total scheduled events:
- Windowed total accepted events:
- Windowed scheduled capacity rejects:
- Windowed carried voices:
- Windowed released/fadeout carryovers:
- Windowed boundary continuations:
- Windowed boundary drops:
- Windowed may contain boundary cuts:
- Windowed unsupported carryover reasons:
- First windows with rejects:
- Window-boundary state/carryover notes:
- Volume/panning state updates total:
- Volume/panning state updates applied:
- Volume/panning state updates deferred:
- Active voice volume/panning updates:
- Empty-note volume-column set-volume applied/deferred:
- Empty-note volume-column set-panning applied/deferred:
- Cxx set-volume applied/deferred:
- 8xx set-panning applied/deferred:
- Axy volume slide applied/deferred:
- Hxy global volume slide applied/deferred:
- Sample-map selections:
- First-playable fallback selections:
- Fallback-after-invalid-map selections:
- Skipped-no-valid-sample selections:
- Missing/deferred sample-map selections:
- Bxx position jumps:
- Dxx pattern breaks:
- EEx pattern delays:
- Fxx speed/BPM timing changes:
- E9x retriggers:
- Other E-command diagnostics:
- Total traversal hazards:
- First traversal hazard coordinates:
- Traversal hazards before/in top mismatch windows:
- Top skip reasons:
- First skipped coordinates:
- Suspected missing-note cause:
- Suspected traversal/timing cause:
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

## Correlation Run

- Tool:
- Command:
- Correlation report path:
- Label:
- Metadata:
- Correlation notes:
- Effect-frequency summary present:
- Volume-column frequency summary present:
- Event-coverage summary present:
- Capacity summary present:
- Pattern traversal / timing hazard summary present:
- Volume/panning state-update summary present:
- Recommendation heuristic present:

## Click / Discontinuity Run

- Tool:
- Command:
- Discontinuity JSON path:
- Discontinuity Markdown path:
- Jump threshold:
- Top jump count:
- WAV peak:
- WAV RMS:
- PCM16 clipping count:
- Jumps above threshold:
- Jumps per second:
- Largest adjacent-sample jump:
- Largest jump frame/time/channel:
- Largest jump before/after sample values:
- Top nearby event categories:
- Gain/pan update clustering:
- Volume/panning state-update clustering:
- E9x retrigger clustering:
- ECx note-cut clustering:
- EDx note-delay clustering:
- Loop-boundary / looped-voice clustering:
- Window-boundary / carried-voice clustering:
- Key-off/release/fadeout clustering:
- Discontinuity evidence notes:

## Top Mismatch Windows

| Rank | Time Range | Frame Range | RMS Difference | Max Abs Difference | Likely Rows/Channels/Events | Local Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |

## Correlated Event Notes

- Top overlapping rows/channels/events:
- Recent preceding events when no overlap:
- Pitch-step / frequency-table clues:
- Sample-selection / keymap clues:
- Volume-column / panning clues:
- Volume/panning active voice update clues:
- Fxx / row-timing clues:
- Envelope / fadeout / key-off clues:
- Loop metadata clues:
- Event coverage / skipped-note clues:
- First skipped coordinates:
- Capacity / rejected-event clues:
- Pattern traversal / timing hazard clues:

## Effect / Volume Frequency Summary

- Pattern traversal / timing hazards:
- First traversal hazard coordinates:
- Traversal recommendation signal:
- Deferred effect commands in worst windows:
- Applied effect commands in worst windows:
- Ignored/no-op effect commands in worst windows:
- Unknown effect commands in worst windows:
- Deferred volume-column commands in worst windows:
- Applied volume-column commands in worst windows:
- Ignored/no-op volume-column commands in worst windows:
- Unknown volume-column commands in worst windows:
- Applied volume/panning state updates in worst windows:
- Deferred volume/panning state updates in worst windows:
- E9x retriggers: applied / E90 no-op / no-active / out-of-row:
- ECx note cuts: applied / no-active / out-of-row:
- EDx note delays: applied / no-note / out-of-row:
- Overall deferred command frequency in bounded render:
- Overall command frequency notes:

## Observed Likely Mismatch Categories

Mark only categories supported by comparison output, listening checks, traces,
or source-to-synthetic diagnostics.

- [ ] timing / `Fxx` / row duration
- [ ] order traversal / pattern break / position jump / pattern delay
- [ ] panning / volume-column behavior
- [ ] volume slides / envelope / fadeout / key-off
- [ ] pitch / finetune / relative note / linear frequency
- [ ] sample map / keymap / selected sample metadata
- [ ] remaining interpolation / resampling / reference-render settings
- [ ] sample offset / retrigger / note cut / note delay
- [ ] output headroom / clipping / render gain policy
- [ ] click / discontinuity / adjacent-sample jump clustering
- [ ] loop behavior
- [ ] unknown / needs trace correlation

## Evidence Notes

- Metric summary:
- Output peak / clipping summary:
- Largest adjacent-sample jump summary:
- Trace or diagnostics correlation:
- Event coverage summary:
- Capacity summary:
- Rejected event coordinates:
- Sample selection summary:
- Top skip reasons:
- Suspected missing-note cause:
- Correlation report summary:
- Pattern traversal / timing hazard summary:
- Click/discontinuity summary:
- Largest jump correlation summary:
- Subjective listening notes:
- Local reproduction notes:

## Possible Next PR Candidates

Choose one narrow follow-up. Do not combine unrelated fixes.

- [ ] Adapter Support for Specific Effect X:
- [ ] Focused Pitch/Period Accuracy Pass:
- [ ] Additional Volume-Column Semantics:
- [ ] Loop/Interpolation Investigation:
- [ ] Gain/Pan Update Micro-Ramping:
- [ ] ECx Cut Micro-Ramping:
- [ ] Loop Boundary Click Mitigation:
- [ ] Envelope/Fadeout Smoothing:
- [ ] Bounded Order Traversal Improvement:
- [ ] Minimal Pattern Delay EEx for Bounded Offline Renders:
- [ ] Mixer Output Headroom / Clipping Diagnostics and Render Gain Policy:
- [ ] Redistribution-Safe Audio Fixture Corpus:
- [ ] Feature-Flagged Runtime Backend Skeleton only after enough offline confidence:

## Likely Next PR

- Recommended next PR:
- Why this evidence supports it:
- Recommendation heuristic rationale:
- Manual review / listening notes that agree or disagree:
- What this report does not prove:

## Artifact Safety Checklist

- [ ] Private/local XM modules were not committed, copied into fixtures, uploaded, or used in automated tests.
- [ ] Candidate/reference WAVs remain local and out of git.
- [ ] JSON/Markdown comparison reports remain local and out of git.
- [ ] JSON/Markdown click/discontinuity reports remain local and out of git.
- [ ] Candidate diagnostics JSON and correlation reports remain local and out of git.
- [ ] Playback traces, screenshots, logs, and listening notes remain local and out of git.
- [ ] The committed PR contains only source, tests, templates, and documentation intended for review.
