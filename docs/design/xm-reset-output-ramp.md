# XM Non-retriggering Reset Output Contract

This note owns the implemented XM semantic tick, ordinary audible final-L/R,
and non-retriggering 5 ms reset contracts.
It does not claim broad FT2 mix parity. Volume/reset ownership is described in
[XM volume ownership](xm-volume-ownership.md#instrument-only-cached-defaults-and-reset).
Instrument-only dispatch reuses these contracts. Ordinary note-only carries
their semantic state into the new route. G06 adds the existing pan segment's
audible factor through this same final-output authority.

## Current gain path

| Stage | Authority and behavior |
| --- | --- |
| Tracker base/output volume | Base writes synchronize output; tremolo can change output independently. Both use `0...64`. |
| Planned scalar gain | The shared adapter consumes output volume once with global volume. The sample header initializes/restores base/output defaults, with no independent song multiplier (G01). |
| Semantic envelope/fadeout | `PlaybackXMEnvelopeTimeline` publishes instantaneous state at canonical Fxx tick frames, separately from audible interpolation. |
| Final output targets | `PlaybackXMAudibleTimeline` combines typed factor writes with volume/pan-envelope and release targets. `VTXCMixerOutputState` alone interpolates their final mono/L/R gains. |
| Gain/pan updates | For managed XM voices, scalar/pan writes update factor metadata without a second 32-frame ramp. Generic voices retain the existing independent 32-frame gain/pan path. |
| Stereo output | Sample pan initializes channel pan. G06 consumes the existing semantic pan segment in the final target; static conversions/profile laws remain G40. A neutral pan clock alone does not enable final-output management. |
| Output policy | Mixer profile scaling follows voice summation. Runtime fixed `-12 dB` headroom and product WAV auto-headroom to `-1 dB` remain separate downstream policies; runtime auto-headroom is disabled. |

Plain voices retain generic gain/pan behavior until their first release or a
reset with changed audible factor inputs. Neutral resets leave unfinished
generic ramps untouched. At activation, existing generic ramp reconstruction
supplies the current audible factors to the shared C state, preserving earlier
audio without creating another final-output interpolation formula.

The target amplitude is `output/64 * global/64 * envelope * fadeout`; L/R
additionally multiply the existing pan-law factors. Mono retains
its established pan-independent amplitude. The pan-envelope factor changes only
the target pan; it adds no C envelope clock or interpolation state.

### G06 panning-envelope factor

`PlaybackXMEnvelopeTimeline` publishes its already-carried pan segment value
alongside the logical clock and the existing row's exact channel panning state.
The C semantic snapshot stores that value for parity/diagnostics only. The
planning layer composes it into `PlaybackXMAudibleUpdate.pan`; the existing C
final mono/L/R tuple owns interpolation, reset, deduplication and window carry.

Independent constant-source controls against the unchanged pinned reference
at 44.1/48 kHz establish the byte-domain rule. For static byte `P`, envelope
value `E` and `reach = min(P, 256 - P)`, the displacement is
`floor((E - 32) * reach / 32)`. Negative displacement rounds down, rather than
toward zero. The reference loader limits pan points to 63; the output factor
caps its existing semantic value at 63 without changing preserved metadata or
segment progression. Center 128 with envelope 16/32/48 yields 64/128/192;
static 64 yields 32/64/96. Static zero cannot move, and 255 with envelope zero
yields 254. These are project-authored stimuli, not copied reference vectors.

VTX retains the current static baseline: add the difference between the existing
sample-byte conversion at `P + displacement` and at `P` to the current static
pan, then clamp to `-1...1`. This isolates envelope displacement from the
retained header/8xx conversion and stereo profile-law differences (G40).
Zero displacement returns the original pan exactly. Pan-only voices enter the
existing managed path only when the audible factor first changes, or through
an already-supported release/reset. Earlier generic audio remains unchanged.

`XMPanningEnvelopeTests` supplies public constant-loop model controls for
neutral/left/right, static edges, sustain/loop/release, silent and completed
routes, note-only carry, instrument-only reset, Lxx and both-rate window parity.
`RuntimeCMixerTests` applies the same loop/reset/static-write/tempo/release
control and the existing public envelope fixture through the runtime render core.
No reference audio or corpus-derived artifacts are committed.

This closes the audible-factor contract, not all pan-envelope parity. Existing
Float segment interpolation and slopes through stored point 64 remain distinct
from reference Q8 arithmetic and loader normalization. VTX retains its logical
release from pan sustain; the pinned sustained control keeps its pan value held
after release. Neither clock/arithmetic difference is corrected here. G07 adds
positioning to this same pan segment; static pan law (G40) remains open. Preview
is isolated.

### G07 Lxx panning-envelope positioning

`Lxx` retains its existing volume-position behavior and also positions an enabled
pan envelope when the sounding envelope instrument's raw volume type has the
sustain bit (`0x02`) set. Volume enable and loop bits do not participate in that
gate. An instrument-only selection does not replace the sounding instrument for
the gate. Silent declared routes carry the same semantics without creating a
voice. Existing resets and release happen before same-cell positioning; Lxx
does not revive key-on or reset fadeout.

The command selects the requested byte position and samples the existing Float
segment on that exact canonical tick frame. A position at or beyond the final
point holds its value while the clock advances. Selecting exactly a loop end
wraps immediately to its start, except for a released sustain point at that end.
A jump past the loop end traverses the tail instead of wrapping; instrument reset
restores normal loop progression. Gate-off leaves ordinary G06 pan progression
unchanged. The positioned value feeds the unchanged G06 combination rule and
existing final-L/R writer; no new clock or callback semantics are introduced.

Project-authored constant-loop controls pin all eight raw volume-flag combinations,
L00, interior/end/beyond positions, loops, sustain/release, trigger/reset ordering,
silent routes and exact instrument carry. Command-frame position/value matches
the unchanged pinned reference at 44.1/48 kHz. Whole/window/runtime-core tests
verify semantic state, final targets, PCM and zero planned/applied frame delta.

The bounded G07 Lxx panning-envelope positioning contract is `CLOSED` by
maintainer acceptance of the automated controls and external verification below.
G06 remains closed. G31 fractional/Q8 envelope arithmetic, G40 static/header/8xx
final pan law and the pan-sustain/release difference remain explicitly open;
this is not overall panning-envelope parity.

The maintainer reported `** TEST SUCCEEDED **` for the full canonical repo-root
Debug Xcode test action with `-derivedDataPath build` and `CODE_SIGNING_ALLOWED=NO`.
This is external verification supplied by the maintainer, not reproduced by
Codex. Prior `com.apple.testmanagerd.control` and `_RegisterApplication` failures
are classified as execution-environment failures, not VTX/G07 failures.

The maintainer also reported correct listening for `xm-corpus-023` at zero-based
order 0, pattern 8, row 0, channel 1 (`L35`), and for regression sentinel
`xm-corpus-011`, with no unrelated level, pitch, timing, routing or stereo
regression observed. This records maintainer listening, not subjective listening
by Codex; no private filename or path is included.

## Shared audible target implementation

At each semantic publication, the adapter coalesces accepted factor writes into
one target candidate for that trigger generation. C compares the complete
mono/L/R tuple exactly; identical targets leave progress and duration unchanged.
For a changed ordinary target at frame `N`, the prior target renders at `N`,
linear interpolation uses `k / D`, the new target renders at `N + D`, and output
holds until another changed target. `D = max(1, floor(sampleRate * 2.5 / BPM))`
uses that publication's BPM. Speed changes ticks per row, not ramp duration.
The existing fractional Fxx publication frames remain authoritative.

The independent early-delivery evidence below is the explicit exception to
current-value rebasing: changed ordinary publications start at the **previous
target**, even if interrupted. Valid ordinary ticks finish the previous ramp.
Exact duplicate targets remain no-ops under VTX's explicit deduplication rule;
the artificial early-delivery unchanged-target reference quirk is not adopted.

Typed `Cxx`, volume-column set-volume, instrument-only default restoration
(including K00), and no-envelope key-off writes select
`max(1, floor(sampleRate * 0.005))` frames (240/220 at 48/44.1 kHz). A coincident
envelope/pan change shares that one final target. Other existing factor writes
on managed voices join the ordinary tick target; no effect handler, memory or
clamp policy changes. Same-channel `Gxx` is visible immediately; a later-channel
`Gxx` reaches an earlier channel's target on the next tick, matching the measured
channel-turn ordering. The adapter's global semantic state is unchanged.

G08 ordinary `6x/7x` channel writes join the existing nonzero-tick target with
its tick duration. They add no gain factor, quick-volume reset or second ramp;
fine `8x/9x` keep their existing tick-zero publication.

G09 `Dx/Ex` updates supply current stored pan on those same nonzero frames.
G06 composes its envelope displacement with that pan through the existing
final-L/R target; G07 positioning and envelope arithmetic are unchanged.
`D0` forces zero and `E0` leaves pan/conversion intact. No new output ramp or
callback decoding is added; G11/G33/G40 retain their separate boundaries.

G11 supplies `16 * nibble` for column Cx at tick zero, with C8 = 128 and
CF = 240. Existing factor/semantic publications consume that corrected base;
G06/G07 clocks and arithmetic, output ramps and G40 conversion/profile law are
unchanged. Sample/header and 8xx bytes keep their existing paths.

First publication initializes immediately, preserving VTX trigger onset and
source position. A later explicit non-retriggering reset changes semantic state
at frame `N` and publishes through the same C output state with
`D = floor(sampleRate * 0.005)`: 240 frames at 48 kHz, 220 at 44.1 kHz, and 160
at 32 kHz, independent of BPM/speed. Its start is the **current audible** mono/L/R
value before publication, including unfinished ordinary interpolation. Same-frame
accepted volume/pan/global writes contribute to its target with the ordering
above. Each side renders `start + (target - start) * k / D`, reaching the target
at `N + D`, then holding until the next changed publication. Exact duplicates
do not restart a ramp. The next ordinary target retains its established
previous-target rule and tick duration through this same authority; no reset
overlay or return to a second output path exists. Instrument-only dispatch
publishes this existing reset; ordinary note-only instead carries semantic state
and uses the unchanged immediate source-onset path.

Runtime applies targets after trigger/reset/`Lxx` and semantic state, at the
planned C mixer frame. Offline rendering splits at those same frames. Both use
the same C publication/value/advance operations. C state is fixed-size; these
operations allocate nothing and perform no locks, logging, I/O or UI access.
The existing callback-safety debt is outside this change.

Window reconstruction folds publications strictly before the boundary using
those same C operations. It carries start/target, duration/progress and retirement
state alongside independent semantic state and source position. The plan owns
publication frames and trigger generation; boundary publications remain queued
at local zero. Runtime checks generation/channel ownership and C rejects
completed or retiring voices. Imports never reactivate a completed source.

Replacement snapshots current final output and uses the existing `(k + 1) / 32`
retirement convention, identity and lifetime. Its old scalar timer still owns
retirement, while only the final-output state supplies managed PCM. This avoids
double multiplication. New note onset is unchanged; neither path claims FT2
onset/replacement parity. Hard ECx zero remains immediate and separate.

Constant-PCM tests pin rising/falling stereo interiors, unchanged-target holds,
quiet headers, global volume, same-frame volume/pan, replacement windows, and
both rates/profiles. The existing public semantic fixture supplies runtime
application and release/tempo regression coverage. Independent observations
across 68 public-generated controls measured 1,140 changed targets: all observed
ramp durations matched the pinned reference, maximum VTX linear-gain error was
`9.14e-8`, and constant-source window error was zero. Fractional envelope point
arithmetic and Precise-BPM-off absolute-frame differences remain the known
semantic/timing boundaries below, not reasons to rewrite this foundation.

### Reset verification

Independent public controls cover 28 reset transitions in 26 rate/case pairs at
48/44.1 kHz and BPM 125/250, including release, coincident volume/pan, quiet
headers and later tempo changes. All durations match the pinned reference.
Maximum constant-source linear PCM error is `6.24e-9` for VTX and `1.34e-7` for
the reference's Float32 accumulation. The measurement baseline retained
duplicate sample/header scaling; G01 corrects that factor separately.
Non-center pan endpoint differences remain outside this contract.

For the center-pan falling control at 48000/125, L and R PCM before downstream
headroom are identical: `N = 17280`, `D = 240`, start `0.013810679`, target
`0.055242717`. Quarter/half/three-quarter values are
`0.024168687 / 0.034526698 / 0.044884704`; completion is frame 17520. The target
holds through 18239 and starts the next ordinary ramp at 18240 unchanged.
The largest adjacent jump near reset falls from baseline `0.04143204` to
`0.000172634` (reference `0.000172633`); completion is `0.000172637` and ordinary
resume `0.000014387`, without the rejected rejoin jump. At 44.1 kHz, reset,
completion and resume are 15876/16096/16758, with a 220-frame transition.
Baseline/candidate peaks are unchanged across these controls.

Tests import the existing shared state before/on reset, inside the transition,
at completion, during hold and at ordinary resume; another case crosses a row
boundary mid-transition. Constant-source windows and runtime/offline PCM match
exactly, with zero planned/applied runtime frame delta. The public sine control's
maximum window error is `7.46e-9`, within the existing `1e-7` tolerance. Duplicate,
interrupted, stale/completed and ping-pong cursor cases preserve their contracts.

## Shared XM semantic tick contract

`PlaybackXMEnvelopeTimeline` consumes `PlaybackSongFxxTimingPlan`; it does not
compute a second tempo or elapsed-seconds clock. Each channel owns logical
volume/pan positions, key-on, a fadeout accumulator, and held envelope/fadeout
factors independently of source activity. Declared empty routes retain this
state with no C voice; only a valid source generation receives audible targets.
Runtime events and offline render splits import the
same snapshot through a small C state boundary. Generic synthetic frame
envelopes and their reset queue retain their separate established behavior.

The unchanged pinned reference below was observed across 24 independently
generated cases at 48000/125, 48000/250 and 44100/125, including later `FFA`
and `F03`. Measurements establish these rules:

| Field | Semantic rule |
| --- | --- |
| Initial state | Publish envelope position 0 on the trigger tick, key-on true, fadeout 32768 (unity). |
| Advancement | Advance one logical position at each subsequent canonical XM tick; hold the factor between ticks. Existing VTX linear point interpolation is retained. |
| Sustain/release | Hold the sustain point while key-on. The release tick retains a held sustain value; the next tick advances. |
| Loop | Wrap on the end tick to the start point (exclusive end). Looping continues after release, except that a released sustain point at the loop end lets progression escape the loop. |
| `Lxx` | Preserve volume positioning; additionally position the enabled pan envelope under the sounding instrument's raw volume-sustain flag. Use the same canonical tick frame and existing interpolator. See the G07 contract above for loop/end boundaries. |
| Fadeout | On the release tick and each subsequent tick, `accumulator = max(0, accumulator - instrumentFadeout)`; factor is `accumulator / 32768`. Zero fadeout holds unity; an oversized value clamps immediately. |
| No-envelope key-off | Note 97 and `Kxx` zero base/output volume at their scheduled tick. Fadeout still progresses and source cursor/lifetime continue. Later `C40` restores channel volume, exposing the remaining fadeout; zero fadeout factor stays silent. |
| Pan clock | Uses the same tick frames, logical sustain/loop bookkeeping and reset presence flags. G06 consumes its held segment value; G07 positions that same segment under the raw volume-sustain flag. The existing pan-sustain release quirk difference is retained. |

At 48 kHz a voice started at BPM 125 publishes positions 5, 6, 7, 8, 9 at
frames `4800, 5760, 6240, 6720, 7200` when row 1 changes to BPM 250.
The command's own row immediately uses 480-frame ticks. At 44.1 kHz the
corresponding boundary is `4410, 5292, 5733, 6174`. A later `F03` changes row
length to three ticks without changing the BPM-derived tick interval. These
are consumers of the accepted Fxx timeline, whose fractional-frame policy is
unchanged. Bounded tails use that plan's existing final-tempo extrapolation.

The public `envelope-release-fadeout-timing.xm` combines sustain/release, a
no-envelope release followed by `C40`, a looping envelope, `FFA`, and `F03`.
Tests pin target source coordinates, generation, frame, tempo, speed, logical
positions, key state, and exact accumulator. Runtime planned/applied frame
delta is zero. Window imports retain the prior snapshot, including a still
running source whose fadeout is zero, without reviving completed or stale
voices. Source cursor reconstruction and replacement ownership are unchanged.

Fractional slopes remain a separate point-arithmetic difference: reference
Q8 values for `(0,64), (3,32)` are `16384, 13654, 10924, 8192`, while VTX keeps
its existing linear Float calculation. Reference raw pan-sustain counters also
show a distinct release quirk in the observed neutral-pan case; VTX's logical
pan clock is not a claim of raw FT2 point/counter parity. G06 makes the existing
segment audible while preserving these separate arithmetic/clock boundaries.

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
The initial VTX probes injected the reset primitive into a prepared plan,
before the adapter gained instrument-only dispatch.

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
independent multiplier there. G01 now uses that same song ownership in VTX,
without changing any reset duration or interpolation rule. The observed stereo
endpoint law also differs from VTX's non-center comparison-profile pan law.
Reset timing and the stereo endpoint law retain their separate boundaries.

## Why the isolated reset overlay was rejected

Consider envelope points `(0,64), (3,16), (20,16)` with a reset at row 3,
BPM 125. The old envelope is 0.25; the semantic initial value is 1. At 48 kHz,
the reset is frame 17280 and its reference ramp ends at frame 17520.

Before the tick-domain correction, VTX's continuously evaluated envelope had
already decreased to 0.9375 after those 240 frames.
A ramp that reached the initial target and then returned to that per-frame
path had to jump from 1 to approximately 0.9375. Ramping to the advancing target
instead changed the measured FT2 endpoint and interpolation law. This was
evidence that semantic progression and audible target cadence needed separate
ownership.

The independently generated constant-PCM probe makes this measurable without
sample-phase differences. Values below are left-channel PCM with matching
center pan and comparison scale, before downstream headroom:

| 48 kHz probe | Maximum adjacent jump |
| --- | ---: |
| VTX before tick-domain correction, at reset | 0.04143204 |
| FT2 reset ramp | 0.00017264 |
| Rejected isolated ramp, returning to VTX one frame after its endpoint | 0.00346706 |

At 44.1 kHz the corresponding rejected return jump is 0.00346050. This is an
external falsification experiment, not a shipped candidate or listening
acceptance. FT2 holds its initial target until the next tick, then ramps toward
0.75. The old VTX path immediately followed its continuously advancing
envelope. Extending that isolated ramp only moved the return boundary.

That rejection required one carried final-output authority alongside the semantic
clock. The shared implementation above now carries both ordinary and reset
transitions without returning to a second envelope-output mode.

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
time. G01 uses the same volume ownership in VTX:

```text
plannedGain = outputChannelVolume/64 * globalVolume/64
targetL/R = plannedGain * semanticEnvelope * semanticFadeout * existingPanLawL/R
```

Retain current clamps, cached sample-header defaults and profile pan laws.
XM pan-envelope displacement joins the target pan as described under G06.
Downstream headroom is absent from the voice target.

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
or infer note-only behavior from this characterization. The instrument-only
K00 contract is now documented in the volume-ownership note.

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

## Semantic prerequisites and remaining output boundary

The original output-only characterization stopped at three independent
semantic defects. This table preserves the measured pre-correction baseline;
the shared tick contract above replaces those semantic approximations.

| Control | Reference observation | Pre-correction VTX authority |
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

The semantic prerequisites retain the existing frame plan and point arithmetic.
The shared audible implementation above consumes those values unchanged. It
recovers transition intent from typed accepted writes before C gain events erase
command identity. It never multiplies an interpolated scalar ramp by a second
interpolated envelope ramp. Carried state and exact-frame runtime/offline tests
cover that boundary; maintainer listening remains required before merge.

## Cuts and retained boundaries

The reference `EC0` control sets semantic volume to zero immediately but ramps
audible output over the same 240/220-frame quick interval. Thus `EC0` is not
evidence that every semantic cut must be an instantaneous PCM stop. VTX's
existing immediate cut remains a separate compatibility boundary; this finding
does not authorize changing it or applying reset smoothing to transport stops.
The reference's explicit `stopVoice` control produces zero PCM from its exact
application frame, confirming that an immediate-stop path is distinct from
the `EC0` volume command.

Generic 32-frame gain/pan ramps, replacement timing, onset behavior, generic
frame envelopes, headroom policies, and explicit-trigger default-volume behavior
retain their contracts. Managed XM factor updates use the single final-output
state described above for ordinary and reset transitions, including instrument-only
restoration and note-only carry. G06 uses the same output state. Pan-clock/Q8
quirks, G40 and full FT2 mixer parity remain open; bounded G07 positioning is closed.
