# XM Volume Ownership

This note owns the shared adapter's volume-state boundary. The base/output
separation preserves current supported playback output. Effect statuses remain
owned by [XM effect support](../xm-effect-support.md).

## State and gain domains

| Component | Domain and lifetime | Writers and consumers |
| --- | --- | --- |
| `baseChannelVolume` | Integer `0...64`; persistent, channel-local; initially 64 | Existing instrument/default-volume paths, `Cxx`, volume-column volume/slides, `Axy`, `EAx`/`EBx`, `5xy`/`6xy` volume components, and `Rxy` volume modes write the base. Each retains its existing timing, memory, and clamp policy. |
| `outputChannelVolume` | Integer `0...64`; channel-local output retained between writes | Follows each base write for all currently supported behavior. Trigger and active-voice gain construction consume output. A future effect can write output independently of base; empty rows do not reset it. |
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
The foundation invariant is `outputChannelVolume == baseChannelVolume` for every
currently supported effect path. Separating these values changes no trigger,
retrigger, command order, envelope timing, or sample-selection rule.

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

## FT2 boundary for later tremolo work

FT2 can retain the last tremolo output on a following empty row. Its
[tremolo handler](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1987-L2038)
writes output separately from base; its
[row handling](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1350-L1455)
does not automatically restore tremolo output. Future modulation must preserve
that possibility. This foundation implements no tremolo command or control.

The existing sample-volume compatibility gap remains: VTX multiplies the
sample factor downstream, while FT2 initializes base volume from the sample
default. For example, sample-header 16 plus `C20` remains gain 0.125 in VTX;
FT2's assigned base 32 gives 0.5 before global/envelope factors. State separation
makes the domains explicit but does not correct quiet-sample tremolo depth or
clamping. That behavioral decision still needs focused reference-backed work.
Later tick planning must also avoid exposing an earlier channel's end-of-row
output to a later channel's row-start global-volume command.

## Maintainer smoke

Use the canonical Debug build/run commands in [testing](../testing.md). Load
`basic-instrument-sample.xm` and `instrument-sustained-defaults.xm`, confirm
ordinary playback and envelope changes. Play `fxx-timing.xm` and both
`portamento-scaling` fixtures; the Linear fixture's rows 24...31 include the
`501` volume-slide component and explicit `C00` mute. Compare the same cases
with the baseline using matching render settings. Keep generated WAVs/traces
outside the repository; listening remains an explicit maintainer check.
