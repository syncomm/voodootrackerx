# XM Volume Ownership

This note owns the shared adapter's volume-state boundary. The base/output
separation preserves current supported playback output. Effect statuses remain
owned by [XM effect support](../xm-effect-support.md).

## State and gain domains

| Component | Domain and lifetime | Writers and consumers |
| --- | --- | --- |
| `baseChannelVolume` | Integer `0...64`; persistent, channel-local; initially 64 | Existing instrument/default-volume paths, `Cxx`, volume-column volume/slides, `Axy`, `EAx`/`EBx`, `5xy`/`6xy` volume components, and `Rxy` volume modes write the base. Each retains its existing timing, memory, and clamp policy. |
| `outputChannelVolume` | Integer `0...64`; channel-local output retained between writes | Follows each base write. `7xy` writes output independently; empty rows retain it. Trigger and active-voice gain construction consume output. |
| `PlaybackSample.volume` / `activeSampleVolume` | Header `0...64` normalized to Float `0...1`; immutable sample metadata plus channel-local active selection | The builder normalizes the header. Existing trigger/instrument-selection paths select the active sample factor; channel-volume commands do not rewrite it. |
| Global volume | Integer `0...64`; persistent, song-local; initially 64 | `Gxx` and the existing row-level `Hxy` approximation update the global state and active gains. Future triggers use the current global multiplier. |
| Volume envelope | Point values `0...64` normalized to `0...1`; voice-local progression | The adapter maps instrument points/sustain/loop state at trigger. The C mixer advances the envelope; existing key-off and `Lxx` paths control release/position. |
| Fadeout | Voice-local multiplier `0...1`, initially 1 | Existing key-off planning supplies the per-frame decrement derived from instrument fadeout. The C mixer decreases/clamps it after release; the current default-tick approximation is preserved. |
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
After tremolo activation, supported explicit instrument resets restore the
neutral tracker multiplier before same-cell volume commands; sample scaling
continues downstream. This does not add instrument-memory or trigger routing.
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
  missing-instrument routing skips their sample retrigger. FT2 retriggers the
  remembered sample. This separate boundary creates phase differences in WAVs.
- Existing C-mixer gain-update ramps remain 32 frames; FT2 ordinarily ramps
  across a tick. [FT2 ramp selection](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_audio.c#L270-L283)
  explains another rendering difference without changing the modulation target.
- Note 97 or `K00` with an instrument retains VTX's existing key-off and
  volume policy. FT2 resets its volume from the active sample default in these
  cases; tremolo phase preservation does not correct that separate difference.
- Initial missing-memory `A00`, `EA0`/`EB0`, `R00`, and other deferred cases
  retain their documented status. Existing `6xy`, volume-column, and `Hxy`
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
