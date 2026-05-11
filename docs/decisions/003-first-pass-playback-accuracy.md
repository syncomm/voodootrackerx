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
- `7xy` tremolo
- `8xx` set panning
- `9xx` sample offset
- `Gxx` global volume
- `Hxy` global volume slide
- `Pxy` panning slide
- `E9x` retrigger note
- `ECx` note cut
- `EDx` note delay
- `EEx` pattern delay

The current audio backend uses `AVAudioEngine`, `AVAudioPlayerNode`, and per-channel `AVAudioUnitVarispeed`. This keeps playback stable and avoids running Swift tracker logic inside a CoreAudio render callback.

## Decision

Current playback is first-pass XM-compatible, not FastTracker II period-accurate.

The project will keep the current `AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend while stabilizing playback behavior and effect state. Exact FT2 period math, sample-accurate scheduling, exact envelope quirks, interpolation, and full effect semantics remain future mixer work.

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
- Tremolo uses a first-pass sine waveform that modulates the channel volume scale; alternate XM tremolo waveforms and FT2 waveform quirks are not implemented.
- Global volume is applied as a safe multiplier on top of per-channel volume state.
- Global volume slide is tick-driven and bounded to the XM `0...64` volume range, but does not emulate every FT2 memory or mixed-nibble edge case.
- Panning uses XM `0...255` channel state and maps that to the current AVAudio `-1...1` pan control. Channels default to a conservative tracker-style spread of approximately half-left, half-right, half-right, half-left (`64, 191, 191, 64`) repeated by channel.
- Panning slide is tick-driven with simple effect memory; the high nibble slides right and the low nibble slides left, with mixed nibbles treated conservatively by preferring the high nibble.
- Initial XM speed/BPM now comes from the XM header and `Fxx` updates speed for
  `01...1F` or BPM for `20...FF`; scheduling is still timer-driven.
- Linear-frequency note triggering uses note, sample relative note, and finetune
  to compute a first-pass frequency/rate for the AVAudio backend. Amiga-period
  frequency-table playback remains approximate.
- Scheduled AVAudio buffers are created at the backend audio buffer sample rate
  (currently 44.1 kHz by default), so traced `computedRate` is based on
  `targetFrequency/audioBufferSampleRate` rather than using the source sample
  rate as the denominator.
- Sample length and loop metadata are decoded into PCM sample-frame units.
  Forward sample loops are implemented in the current AVAudio backend by
  scheduling the intro/first-loop region once and then scheduling the loop
  region with AVAudio's buffer loop option.
- Ping-pong sample loops are implemented as a first-pass AVAudio scheduling
  approximation. The backend builds a derived loop buffer from the forward loop
  frames plus the reversed loop interior, then schedules that derived buffer
  with AVAudio's buffer loop option. This avoids duplicate turnaround endpoint
  frames, but it is not a full FT2 mixer implementation and does not emulate
  every loop-position/sample-offset edge case.
- Sample offset uses a clamped PCM sample-index offset of `xx * 256`, not exact byte-level FT2 sample-address semantics.
- Retrigger, note cut, and note delay are applied on playback ticks through the existing timer-driven engine, not sample-accurate audio scheduling.
- Note delay values outside the current row speed are skipped safely instead of being carried into later rows.
- Pattern delay holds row advancement for additional row durations in the existing playback timer; it is not sample-accurate and does not implement full FT2 delay quirks.
- XM volume envelopes are first-pass only. Playback reads volume envelope
  points/type flags/sustain/loop/fadeout from XM instrument headers, advances
  one envelope tick per playback tick, interpolates linearly between points,
  holds basic sustain until key-off, wraps basic envelope loops, and applies
  fadeout after key-off. Panning envelopes and exact FT2 envelope quirks are
  not implemented.
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
