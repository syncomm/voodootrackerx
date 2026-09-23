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

## Ordinary target cadence: measured contract

Independent constant-PCM probes through the same unchanged pinned reference
cover rising, falling and flat segments, held sustain, release from sustain,
fadeout with and without an envelope, reset followed by advancement/release,
quiet sample/channel/global volume, static center/non-center pan, and coincident
volume/pan/global writes. Each render reloads its generated XM. The reference
profile remains stereo Float32, Linear frequency mode/interpolation,
amplification 10, master 256, ramping on, Precise BPM off. Only external
observation/stimulus code changes; no reference implementation text, tables or
assets enter VTX. Source provenance is checked against the pinned archive.

| Rate / BPM | Ordinary target interval and ramp duration | Reset duration |
| --- | ---: | ---: |
| 48000 / 125 | 960 frames | 240 frames |
| 44100 / 125 | 882 frames | 220 frames |
| 48000 / 250 | 480 frames | 240 frames |
| 44100 / 137 | 804 frames | 220 frames |

For these probes the ordinary interval/duration is
`floor(sampleRate * 2.5 / BPM)`. A BPM command changes that interval on its own
row; changing speed changes ticks per row, not the tick interval. This measures
the reference's **Precise BPM off** profile, not permission to replace VTX's
accepted fractional frame timeline or change Fxx behavior.

At tick frame `N`, semantic processing precedes target publication. Changed
envelope/fadeout targets interpolate final L/R over that tick, using the
previous target at `N` and reaching the new target at `N + D`, within Float32
accumulation error. Identical targets produce no new ramp; flat/sustain output
holds. On leaving sustain without fadeout, the release tick retains the sustain
value; the following tick publishes the next segment value. Fadeout can change
the release tick's target even when the envelope value is unchanged.

For a rising `(0,16), (4,64)` envelope at 48000/125, envelope target factors
at frames `0, 960, 1920, 2880, 3840` are
`0.25, 0.4375, 0.625, 0.8125, 1`. The ramp published at 960 starts at 0.25;
its quarter, half and three-quarter factors are `0.296875, 0.34375, 0.390625`,
and it completes at 1920. The falling control reverses those factors. These
are target-domain values, before channel/global volume and pan.

The prior reset probe now has a pinned handoff: publish 1 at 17280, ramp from
0.25 for 240 frames, hold through 18239, then publish 0.75 at 18240 and ramp
for 960 frames. There is no return to a continuously evaluated audible
envelope at 17520. Semantic advancement must remain independent of this hold.

### Target composition and coincident writers

Measured reference targets combine the channel's current output volume,
envelope, released fadeout, the global volume visible while processing that
channel, and static pan. FT2 does not multiply sample/header volume a second
time. VTX's proposed target must retain its own composition:

```text
plannedGain = sample/header * outputChannelVolume/64 * globalVolume/64
targetL/R = plannedGain * semanticEnvelope * semanticFadeout * existingPanLawL/R
```

Retain current clamps, VTX sample ownership and profile pan laws. XM pan-envelope
offsets remain zero. Downstream headroom is absent from the voice target.

Coincident `C20` uses the new volume and envelope value in **one quick target**
(240/220 frames); an ordinary `8xx` or same-channel `Gxx` uses the tick-length
target. A reset plus volume-column volume and `8xx` includes both new values
in its quick target. Therefore neither an unconditional tick ramp nor applying
the old scalar/pan micro-ramps beneath a final-output ramp matches these cases.

Cross-channel `Gxx` is order-sensitive in the reference: a reset on channel 0
sees the old global value when channel 1 changes it later that tick; reversing
the channels includes the new global value immediately. At 48000/125 with
channel volume 32, pan byte 224 and `G20`, the former reset targets L/R
`0.17677307 / 0.46770477`; the latter targets
`0.08838654 / 0.23385239`. Both see the new global value on the following tick.
This is separate ordering evidence, not authorization to redesign VTX global
volume or channel traversal.

An instrument-only cell with `K00` does not exercise an envelope reset in the
reference: the envelope retains its position and release/fadeout runs. Do not
use that cell to infer ordering for an explicitly injected reset plus release,
or implement deferred instrument-only behavior from this characterization.

### Interruption is not an assumed continuity rule

At the tested valid tempos, ordinary ramps finish by the next tick and quick
ramps finish earlier. To observe overlap independently, an external driver
also delivers the next ordinary tick after rendering only part of the previous
tick. This is a controlled early-delivery experiment, not a reachable XM tempo
claim. The unchanged reference rebases from the **previous target**, not its
currently interpolated gain, even when the next target is unchanged.

For the reset above, delivering the next tick after 120 frames starts the new
L ramp at `0.70710754` toward `0.53033066`; the last rendered L multiplier was
`0.43973341`. Interrupting an ordinary falling ramp halfway likewise starts
at its previous target `0.57452488`, not the last rendered `0.64095573`.
Do not substitute a smoother rebase rule and call it measured reference parity.

## Stop boundary: semantic targets precede output implementation

The audible cadence is pinned, but publishing the existing VTX semantic values
at ticks cannot meet the reference target contract. Three independent controls
expose semantic prerequisites:

| Control | Reference observation | Current VTX authority |
| --- | --- | --- |
| Flat envelope, fadeout 1024, release at 11520 (48000/125) | Fadeout target is `31/32` on release, then `30/32`, `29/32`, etc.; each change ramps for 960 frames. | Release begins at 1; C subtracts per frame using `1024 / 65536 / 960`. One tick later the carried value is about `0.98437876`, rather than the reference's next target `0.9375`. |
| Same fadeout with envelope disabled | Key-off also sets base/output volume to zero; output reaches zero in 240 frames. Fadeout continues semantically. A later `C40` exposes its reduced value again. | Key-off retains channel volume and audibly fades with the same continuous approximation as the enabled-envelope case. |
| Carried envelope across `FFA` (125 to 250 BPM) | Envelope advances one tick every 480 frames after the command. | Points were converted to frames at trigger; the C clock still advances through those original frame distances. Sampling it at new tick boundaries advances only half a former tick. |

These are not errors that an output ramp can repair without changing semantic
targets or introducing a second envelope/fadeout authority. Non-integral
segments also show reference tick-value quantization: `(0,64), (3,32)` yields
Q8 values `16384, 13654, 10924, 8192`, distinct from VTX's continuous linear
evaluation. Derive any eventual arithmetic independently from observations;
do not import reference tables or implementation structure.

The shared-target foundation therefore stops before production changes under
its output-only boundary. The smallest next prerequisite is a focused design
and correction of **shared XM tick-domain envelope/release/fadeout targets**,
using the existing frame plan and preserving generic synthetic frame envelopes,
reset identity/cursor guarantees, sample/header ownership, and existing gain/pan
families. Do not silently turn that prerequisite into this output-only change.

The eventual output implementation additionally needs explicit transition
intent: current C gain/pan events erase whether a scalar write came from `Cxx`,
slide, tremolo or global volume, though observed durations differ. Multiplying
an interpolated base ramp by an interpolated envelope ramp introduces a product
term; it is not linear final-L/R interpolation. Simply stacking ramps or
switching all these writers to one duration is not a sufficient design.

Continuation must carry final L/R start/target, progress/duration, publication
frame and generation, alongside independent semantic state. Fold events
strictly before a window boundary and queue boundary events at local zero.
Neither current semantic envelope position alone nor an old scalar ramp
reconstructs an in-flight final-output ramp. Keep completed/stale voices
excluded and share the eventual C output authority between runtime and offline.
No such carried state or implementation is delivered by this characterization.

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
