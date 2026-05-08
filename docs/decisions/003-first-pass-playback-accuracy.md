# ADR 003: First-Pass XM Playback Accuracy

## Status

Accepted as guidance for current playback work.

## Context

VoodooTracker X now has audible XM playback, stable Play/Stop lifecycle behavior, tracker follow, and first-pass support for a small effect subset:

- `Fxx` speed/tempo
- `Bxx` position jump
- `Dxx` pattern break
- `Cxx` set volume
- `0xy` arpeggio
- `Axy` volume slide
- `1xx` portamento up
- `2xx` portamento down
- `3xx` tone portamento
- `4xy` vibrato
- `5xy` tone portamento plus volume slide
- `6xy` vibrato plus volume slide

The current audio backend uses `AVAudioEngine`, `AVAudioPlayerNode`, and per-channel `AVAudioUnitVarispeed`. This keeps playback stable and avoids running Swift tracker logic inside a CoreAudio render callback.

## Decision

Current playback is first-pass XM-compatible, not FastTracker II period-accurate.

The project will keep the current `AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend while stabilizing playback behavior and effect state. Exact FT2 period math, sample-accurate scheduling, loop behavior, envelopes, interpolation, and full effect semantics remain future mixer work.

## Rationale

The current backend is appropriate for proving:

- real audible sample triggering
- deterministic transport lifecycle
- visible tracker follow
- simple tick-driven effect updates
- safe behavior on unsupported or malformed effect parameters

`AVAudioPlayerNode` keeps scheduling and playback lifecycle straightforward. `AVAudioUnitVarispeed` gives the current backend a safe way to apply first-pass pitch changes to active voices without rewriting audio rendering.

The tradeoff is accuracy. XM playback eventually needs a dedicated tracker mixer that owns sample stepping, period-to-frequency conversion, channel state, loops, envelopes, interpolation, panning, and sample-accurate event timing. That mixer should be introduced behind the existing playback/audio boundary rather than embedded in UI code or mixed with parser cleanup.

## Known Approximation Areas

- Portamento uses a semitone-per-tick approximation, not XM period math.
- Tone portamento slides toward note targets in semitone space rather than FT2 period space.
- Arpeggio cycles semitone offsets through the current varispeed path rather than recalculating exact tracker periods.
- Vibrato uses a first-pass sine waveform through varispeed pitch offsets; alternate waveforms and FT2 waveform quirks are not implemented.
- Sample looping is not implemented.
- Instrument envelopes are not implemented.
- Interpolation is minimal and not tracker-accurate.
- Effect memory supports only simple safe cases and does not emulate all FT2 edge cases.
- Tick and sample scheduling are timer-driven and not sample-accurate.
- Unsupported effects are intentionally ignored or logged instead of partially emulated.

## Consequences

Positive:

- playback remains stable and reviewable
- effect behavior is isolated from tracker rendering
- UI code stays out of DSP and scheduling details
- the future custom mixer path remains open

Tradeoffs:

- real-world XM files may sound different from FT2
- pitch slides and arpeggios are approximate
- modules relying on loops, envelopes, or complex effect memory will not play correctly yet
- some current code will be replaced or moved behind a custom mixer later

## Future Direction

Future playback accuracy work should happen in small PRs:

- add focused regression tests for each supported effect family
- improve period/frequency handling before adding broad new effects
- add loop and envelope handling behind playback/audio boundaries
- move toward a dedicated tracker mixer when `AVAudioPlayerNode` scheduling becomes the limiting factor
- preserve parser architecture and tracker viewport behavior unless a PR is explicitly scoped to those areas
