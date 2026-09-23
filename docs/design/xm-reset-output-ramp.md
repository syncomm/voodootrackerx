# XM Non-retriggering Reset Output Contract

This is a reference characterization and an unresolved design constraint, not
an implemented ramp or a claim of broad FT2 mix parity. Semantic resets remain
owned by [XM volume ownership](xm-volume-ownership.md). Instrument-only dispatch,
note-only routing, and audible XM panning envelopes remain deferred.

## Current gain path

| Stage | Authority and behavior |
| --- | --- |
| Tracker base/output volume | Base writes synchronize output; tremolo can change output independently. Both use `0...64`. |
| Planned scalar gain | The shared adapter multiplies sample/header volume, output volume, and global volume. Explicit note+instrument initialization also loads the mapped sample default into base/output. |
| Gain/pan updates | C independently interpolates scalar gain and channel pan over 32 frames, using `(position + 1) / 32`. Slides, tremolo, and global writes use this path. |
| Envelope and fadeout | C evaluates the volume envelope and released fadeout every frame **after** the gain ramp. Reset changes their semantic state immediately. |
| Stereo output | The envelope/fadeout product is multiplied by the pan-law gains. Sample pan initializes channel pan. Parsed XM pan-envelope metadata advances a neutral clock; it has no audible offset. |
| Output policy | Mixer profile scaling follows voice summation. Runtime fixed `-12 dB` headroom and product WAV auto-headroom to `-1 dB` remain separate downstream policies; runtime auto-headroom is disabled. |

The reset therefore bypasses the existing scalar ramp. Replacement separately
ramps the old voice's scalar gain to zero over 32 frames; the new voice starts
at its supplied gain without a C onset ramp. VTX note cuts use immediate zero
gain or voice retirement. Key-off releases envelope sustain and starts the
existing per-frame fadeout. None of these families is changed by this note.

Runtime splits rendering at planned event frames and applies the same C state
operation as bounded offline rendering. Gain/pitch updates precede cuts and
triggers, then reset precedes `Lxx`; trigger-owned release follows queued state
events. Windowed rendering reconstructs scalar gain/pan ramps separately from
envelope clocks, key-on, and Float32 fadeout. Events exactly on the boundary
remain queued at local frame zero. There is no carried final-output ramp state.

## Independently measured reference

Reference: [ft2-clone revision
87be42543dac82cf802b5bddad917bda62ace131](https://github.com/8bitbubsy/ft2-clone/tree/87be42543dac82cf802b5bddad917bda62ace131).
An external observer executes its unchanged loader, replayer, mixer, and WAV
tick path. The source matches a freshly downloaded pinned archive. Only
observed states and PCM inform this contract; no reference implementation,
comments, tables, sample assets, or test vectors are incorporated into VTX.

Independent XM probes use a generated constant sample (`8192 / 32768`), a
256-frame forward loop, Linear frequency mode/interpolation, speed 6, volume
ramping on, amplification 10, master volume 256, and Precise BPM off. BPM 125
and 250 have integral tick lengths at both tested rates. An ordinary native
instrument-only cell at row 3 supplies the non-retriggering reference reset.
VTX probes inject the merged reset primitive into a prepared plan; they do not
enable instrument-only dispatch.

Cases cover descending and ascending envelopes, a released/faded voice,
unchanged base volume, same-cell `C20`, sample default 24, global volume 32,
static pan bytes 32/128/224, and same-cell `8E0`. No audible panning envelope is
needed to distinguish the domains.

| Property | Observation |
| --- | --- |
| Start/order | At frame `N`, the clocks/key/fadeout already have their reset values, with no sample trigger. Same-cell volume/pan writes are included in the target. |
| Domain | Final left/right multipliers, including output volume, envelope, fadeout, global volume, and static pan. A simultaneous pan change distinguishes this from scalar-volume interpolation followed by pan interpolation. |
| Duration | 240 frames at 48 kHz; 220 at 44.1 kHz, at both BPM values. This is consistent with a 5 ms duration truncated to whole frames, not a tick or a fixed frame count. |
| Interpolation | For each side, `current(N + k) = start + (target - start) * k / D`, within Float32 accumulation error. The first sample uses `start`; the endpoint is reached at `N + D`. |
| After completion | The target is held through the rest of that tick. Subsequent envelope targets ramp over a tick (960 or 882 frames at BPM 125). |
| Unchanged target | A flat-envelope reset with unchanged volume/pan needs no output ramp. |

Sample defaults enter FT2's channel-volume state; they are not an additional
independent multiplier there. VTX's retained sample/header multiplication is a
separate known ownership difference. The observed stereo endpoint law also
differs from VTX's non-center comparison-profile pan law. Neither difference is
permission to change those domains in a reset-ramp implementation.

## Why a reset-only overlay is insufficient

Consider envelope points `(0,64), (3,16), (20,16)` with a reset at row 3,
BPM 125. The old envelope is 0.25; the semantic initial value is 1. At 48 kHz,
the reset is frame 17280 and its reference ramp ends at frame 17520.

VTX's semantic envelope has already decreased to 0.9375 after those 240 frames.
A ramp that reaches the initial target and then returns to the existing mixer
must jump from 1 to approximately 0.9375. A ramp to the advancing VTX target
instead changes the measured FT2 endpoint and interpolation law. Freezing the
semantic envelope to avoid this would violate exact reset-state progression.

The independently generated constant-PCM probe makes this measurable without
sample-phase differences. Values below are left-channel PCM with matching
center pan and comparison scale, before downstream headroom:

| 48 kHz probe | Maximum adjacent jump |
| --- | ---: |
| Current VTX at reset | 0.04143204 |
| FT2 reset ramp | 0.00017264 |
| Rejected isolated ramp, returning to VTX one frame after its endpoint | 0.00346706 |

At 44.1 kHz the corresponding rejected return jump is 0.00346050. This is an
external falsification experiment, not a shipped candidate or listening
acceptance. FT2 holds its initial target until the next tick, then ramps toward
0.75. VTX immediately follows its continuously advancing envelope. Extending
the isolated ramp only moves the unresolved return boundary.

The smallest prerequisite is a design for **audible envelope/fadeout output
target cadence and its continuation state**, separate from semantic clocks.
It must explain the handoff after a reset and interactions with subsequent
gain/pan updates, release, `Lxx`, cuts, and replacement, using one runtime/offline
authority. A reset-specific permanent second envelope mode would leave those
interactions dependent on voice history. Do not introduce it implicitly.

## Cuts and retained boundaries

The reference `EC0` control sets semantic volume to zero immediately but ramps
audible output over the same 240/220-frame quick interval. Thus `EC0` is not
evidence that every semantic cut must be an instantaneous PCM stop. VTX's
existing immediate cut remains a separate compatibility boundary; this finding
does not authorize changing it or applying reset smoothing to transport stops.
The reference's explicit `stopVoice` control produces zero PCM from its exact
application frame, confirming that an immediate-stop path is distinct from
the `EC0` volume command.

The 32-frame gain/replacement ramps, onset behavior, per-frame envelope/fadeout
approximations, headroom policies, and explicit-trigger default-volume behavior
remain unchanged. No final-output implementation is ready until the cadence
and continuation design resolves the demonstrated return discontinuity and
the resulting implementation passes exact-frame parity and maintainer listening.
