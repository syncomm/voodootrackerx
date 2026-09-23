# XM Volume Ownership

This note owns the shared adapter's volume-state boundary. The base/output
separation preserves current supported playback output. Effect statuses remain
owned by [XM effect support](../xm-effect-support.md).

## State and gain domains

| Component | Domain and lifetime | Writers and consumers |
| --- | --- | --- |
| `baseChannelVolume` | Integer `0...64`; persistent, channel-local; initially 64 | Instrument/default-volume paths, `Cxx`, volume-column volume/slides, `Axy`, `EAx`/`EBx`, `5xy`/`6xy` volume components, and `Rxy` volume modes write the base. No-envelope key-off zeros it. Each retains its timing, memory, and clamp policy. |
| `outputChannelVolume` | Integer `0...64`; channel-local output retained between writes | Follows each base write. `7xy` writes output independently; empty rows retain it. Trigger and active-voice gain construction consume output. |
| `PlaybackSample.volume` / `activeSampleVolume` | Header `0...64` normalized to Float `0...1`; immutable sample metadata plus channel-local active selection | The builder normalizes the header. Existing trigger/instrument-selection paths select the active sample factor; channel-volume commands do not rewrite it. |
| Global volume | Integer `0...64`; persistent, song-local; initially 64 | `Gxx` and the existing row-level `Hxy` approximation update the global state and active gains. Future triggers use the current global multiplier. |
| Volume envelope | Point values `0...64` normalized to `0...1`; voice-local progression | `PlaybackXMEnvelopeTimeline` publishes logical position/value at canonical Fxx tick frames, including release and `Lxx`. C holds the imported target until the next publication. |
| Fadeout | Voice-local integer `0...32768`, initially 32768; factor `accumulator / 32768` | The shared timeline subtracts instrument fadeout on the release tick and every subsequent XM tick, clamping at zero. C holds the factor without advancing a second clock. |
| Planned voice gain | Float `0...1`; trigger value with scheduled active-voice updates | `adaptedGain` combines output, sample, and global factors. The C mixer applies its existing gain-update ramps, envelope, fadeout, and panning. |
| Mix/output gain | Render/host/export policy; independent of channel state | Existing mix profile, runtime headroom, and export gain policies apply downstream. Summed Float32 PCM may exceed unity; encoded PCM16 clamps at the export boundary. |

The owning implementation is
[PlaybackSongSyntheticAdapter](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter.swift),
its volume/effect helpers, and
[gain construction](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+RuntimeEvents.swift).
Base writes synchronize output without an unconditional row-start or row-end copy.
Existing base-volume writers synchronize output; `7xy` can leave output distinct
from base until another volume writer replaces it. The sample factor, envelope
clock, and existing trigger-selection policies remain separate.

## Preserved multiplication and clamps

```text
base write -> output follows
planned gain = clamp01(sampleVolume * clamp64(outputChannelVolume)/64
                                   * clamp64(globalVolume)/64)
voice amplitude = PCM * ramped gain * envelope * fadeout
```

Existing volume writers clamp integer state; gain construction also normalizes
and clamps its inputs/output, mapping a nonfinite sample factor or gain to zero.
Envelope and fadeout stay outside the planned gain. Panning and downstream mix
policies remain outside tracker-volume state.

At full global volume, these cases are independently representable:

| Sample header | Base | Output | Planned gain |
| --- | --- | --- | --- |
| 64 | 16 | 16 | 0.25 |
| 16 | 64 | 64 | 0.25 |
| 16 | 16 | 16 | 0.0625 |

Equal final gains therefore do not imply equal tracker or sample state.

## Ordinary explicit note and instrument initialization

An ordinary immediate `note + instrument` resolves its sample once through the
existing canonical keymap resolver. Before same-cell volume commands, it writes
that newly selected sample's default (`PlaybackSample.volume * 64`, rounded and
clamped to `0...64`) to base volume; output follows immediately. A stale zero,
reduced base, or held tremolo output cannot silence or scale the new trigger.
The trigger refreshes its active instrument/sample association through the
existing event-creation path. Editor sample selection is not a routing input.

The [pinned FT2 trigger](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L537-L590)
selects the new note's mapped sample and caches its default in `oldVol`;
`getNewNote` then calls `resetVolumes` before tick-zero volume/effect handling.
Explicit volume-column and `Cxx` writes still override the default. VTX retains
its independent sample factor: default/header 16 initializes base/output 16
and produces gain `0.0625` at full global volume without envelope/fadeout.
FT2's different sample-multiplier ownership remains a separate compatibility gap.

Specialized delayed, retrigger and portamento paths retain their existing volume
contracts. Key-off without an enabled volume envelope zeros base/output while
retaining the active source association; later volume writes can expose its
remaining fadeout. Instrument-only reset dispatch and note-only
routing remain deferred. This initialization does not alter envelope/reset
operations, gain ramps, replacement ramps, or downstream headroom policy.

## Runtime, offline, and diagnostics

`RuntimeCMixerAdapterEventPlan` and bounded/windowed offline rendering consume
the same adapter triggers and `voiceStateUpdates`. Both schedule the existing
C-mixer gain input at planned frames; neither recomputes a second tracker-volume
authority. Runtime host delivery and offline comparison retain their roles in
[audio comparison](../audio-comparison.md).

Adapter `effectiveVolumeValue` and update `effectiveVolumeBefore/After` describe
tracker output in `0...64`; sample volume remains separate. `gainBefore/After`
are sample/output/global products before the C-mixer envelope/fadeout and mix
policies. Tests can inspect the internal base/output state without changing the
trace schema.

The separate `PlaybackEngine` decision trace uses `computedVolume` for its
normalized control scale, including its channel/global/envelope/fadeout state;
`finalAppliedVolume` additionally multiplies sample volume and clamps. These
fields are diagnostic estimates, not measurements of C-mixer PCM or substitutes
for adapter gain/application evidence. See [playback trace](../playback-trace.md).

## Non-retriggering envelope and release reset

`PlaybackVoiceStateEvent` targets an existing trigger event index and channel.
Its reset has four independent presence flags: restart the enabled volume
envelope, restart the enabled panning clock, restore key-on, and restore unity
fadeout. The operation changes neither tracker/sample volume nor pan, pitch,
sample identity, fractional cursor, loop state, or ping-pong direction. It
creates no voice. Instrument-only default-volume/reset dispatch and note-only
routing remain separate, deferred work.

The [pinned FT2 instrument reset](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L348-L407)
sets enabled clocks to 65535 and their point cursors to zero; envelope handling
then advances to tick zero, selects the first point, and establishes the first
interpolation segment. Key-off clears and fadeout returns to 32768 (unity).
The shared XM timeline represents the corresponding published target with
logical position zero. Disabled clocks retain their state. It consumes the
canonical Fxx frame plan and preserves VTX's linear point interpolation. See
[the semantic tick contract](xm-reset-output-ramp.md#shared-xm-semantic-tick-contract)
for measured sustain/loop, release, fadeout and BPM-change behavior.

XM panning metadata now supplies a clock with its point positions, sustain, and
loop boundaries, but every mixer offset is zero. Exact non-neutral values stay
in the instrument model. This permits clock advancement/reset without audible
modulation; it does not implement panning envelopes or `Lxx` panning behavior.
Generic synthetic mixer panning envelopes retain their established behavior.

Generic synthetic frame envelopes retain the fixed-capacity C reset/key-off
queue and per-frame rate. XM plans fold explicit resets and release into their
semantic snapshots instead; reset dimensions remain independent presence flags.
Same-frame explicit transitions retain input order, then XM release and `Lxx`
are included before publication. A reset between ticks publishes immediately
without consuming a tick or fadeout step. XM fadeout uses the instrument's tick
rate; a legacy synthetic key-off's per-frame rate is not a second XM authority.

Both planners reject stale event/channel associations and events after cuts or
replacement. Runtime checks current association and C activity again. C ignores
resets on completed voices and replacement tails; stopping/reusing a slot drops
its queued transitions. No inactive voice is revived by reset or state import.
Channel-only instrument/effect memory remains the adapter's responsibility.

Window reconstruction folds transitions strictly before the boundary; events
on the boundary remain scheduled at local frame zero. XM imports its last
logical clocks, key-on, integer fadeout and target directly, including zero
fadeout on a still-running source. It never reconstructs them from startup BPM
or reschedules a historical release at zero. Generic frame-envelope histories
retain their Float32 subtraction reconstruction. Source-position reconstruction
and replacement ramps keep their existing ownership. Final audible L/R
ramp/hold state remains a separate, unimplemented output contract.

Direct C, Swift, window, and runtime tests cover partial resets, cursor identity,
completion, stale generations, and exact application frames. Product WAV
auto-headroom and fixed runtime `-12 dB` headroom are independent of this state
operation; runtime auto-headroom remains disabled.

The [reset output characterization](xm-reset-output-ramp.md) distinguishes this
semantic operation from FT2's audible final-L/R ramp and records the unresolved
handoff to ongoing envelope/fadeout output. Reset smoothing is not implemented.
That note also pins ordinary tick-length output ramps and the implemented
shared semantic targets that supply their inputs. Final-output continuation
and transition intent remain separate work.

## Tremolo output, memory, and controls

`7xy` updates ticks `1...speed-1`. Each nonzero parameter nibble replaces its
own remembered speed/depth; zero nibbles retain initially-zero memory. Tick 0
changes neither memory nor phase. The current unsigned byte phase selects a
waveform magnitude; integer `(magnitude * depth) >> 6` is added below phase 128
and subtracted otherwise. Output clamps to `0...64`, then phase advances by
`4 * x` modulo 256. Base volume and the downstream factors remain unchanged.
The [pinned FT2 handler](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1987-L2038)
is the semantic reference.

`E7x` stores all four control bits independently from `E4x`:

| Control bits | Behavior |
| --- | --- |
| `x & 3 = 0` | Sine lookup table |
| `x & 3 = 1` | Ramp; FT2's magnitude complement reads vibrato phase sign |
| `x & 3 = 2` or `3` | Square |
| `x & 4` | Suppress instrument-trigger phase reset |
| `x & 8` | Ignored; `8...F` alias `0...7` |

A narrow raw phase observer follows `4xy`/`6xy` for the ramp quirk without
changing the existing pitch planner. Deferred volume-column vibrato remains
deferred; the observer does not imply support for it. Ordinary explicit instrument triggers reset phase
using the previous control before a same-cell `E7x` write. A note alone does
not reset tremolo phase. Note-off and `K00` preserve phase; the existing
volume-column tone-portamento priority still takes precedence over `K00`.
`ED0` resets immediately; successful nonzero delays reset at the scheduled
trigger, and out-of-row delays leave phase unchanged. `E9x` resets phase
without replacing held output, while `Rxy` volume writes replace output. See [FT2 trigger and row ordering](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1350-L1455).

Empty rows retain the last output. For base 32 and `748`, tick-0 through tick-5
outputs are `32, 32, 44, 54, 61, 63`; a following empty row retains 63. `C20`
replaces it with 32 even though base was already 32. Supported positive volume
writers operate on base and replace output at their existing command times.
Ordinary explicit note+instrument triggers load the mapped sample default before
same-cell volume commands, including after tremolo activation. Other existing
instrument/reset paths retain their neutral tracker-multiplier behavior; sample
scaling continues downstream. This does not add instrument-memory or trigger routing.
Nonzero tremolo ticks are planned after all row-start channel/global writers,
so a later channel's `Gxx` cannot see an earlier channel's future tremolo output.

## Reference coverage and retained boundaries

The public [tremolo fixture](../../tests/reference-xm/README.md#generated-fixtures)
provides ordinary, memory, waveform, phase, and empty-row cases. Direct tests
pin tracker-domain values; runtime/offline tests pin plans and applied frames.
The unchanged pinned FT2 replayer agrees with every fixture tick's output and
all tremolo update states. This is not a waveform-identical rendering claim:

- VTX retains independent sample scaling, while FT2 initializes base from the
  sample default. Sample-header 16 plus explicit tracker volume 32 therefore
  gives VTX gain 0.125 versus FT2 0.5 before other factors. Quiet-sample tests
  pin tremolo depth/clamping before this retained downstream multiplier.
- The fixture's note-only cells preserve tremolo state, but existing VTX
  missing-instrument routing skips their sample retrigger. FT2 reuses the
  remembered instrument and resolves the new note through its keymap. This
  separate boundary creates phase differences in WAVs.
- Existing C-mixer gain-update ramps remain 32 frames; FT2 ordinarily ramps
  across a tick. [FT2 ramp selection](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_audio.c#L270-L283)
  explains another rendering difference without changing the modulation target.
- Instrument-associated note 97 / `K00` retain their separate default-volume
  dispatch boundary. The shared no-envelope release rule still zeros output;
  this does not implement the deferred instrument-only/default-volume policy.
- Initial missing-memory `A00`, `EA0`/`EB0`, `R00`, and other deferred cases
  retain their documented status. Existing volume-column and `Hxy`
  timing approximations remain. Tremolo does not broaden those families.

## Maintainer smoke

Use the canonical Debug build/run commands in [testing](../testing.md). Load
`basic-instrument-sample.xm` and `instrument-sustained-defaults.xm`, confirm
ordinary playback and envelope changes. Play `fxx-timing.xm` and both
`portamento-scaling` fixtures; the Linear fixture's rows 24...31 include the
`501` volume-slide component and explicit `C00` mute. Compare the same cases
with the baseline using matching render settings. For tremolo, load
`tremolo-effects.xm`, listen to ordinary modulation, held empty rows, and each
control block against the matching FT2 profile; account for the boundaries
above. Keep generated WAVs/traces
outside the repository; listening remains an explicit maintainer check.
