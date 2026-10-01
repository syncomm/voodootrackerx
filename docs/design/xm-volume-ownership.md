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
| Volume envelope | Point values `0...64` normalized to `0...1`; channel-local progression, projected to a live source when present | `PlaybackXMEnvelopeTimeline` publishes logical position/value at canonical Fxx tick frames, including release and `Lxx`. C holds the imported target until the next publication. |
| Fadeout | Channel-local integer `0...32768`, initially 32768; factor `accumulator / 32768` | The shared timeline subtracts instrument fadeout on the release tick and every subsequent XM tick, clamping at zero. C holds the factor without advancing a second clock. |
| Planned voice gain | Float `0...1`; trigger value with scheduled active-voice updates | `adaptedGain` combines output, sample, and global factors. Managed XM envelope/release voices combine it with semantic factors in one final-output target; generic voices retain existing gain/pan ramps. |
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
XM amplitude target = planned gain * semantic envelope * semantic fadeout
XM stereo PCM = PCM * interpolated final L/R target
generic voice amplitude = PCM * ramped gain * envelope * fadeout
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
contracts. Ordinary key-off without an enabled volume envelope zeros base/output
while retaining the active source association; later volume writes can expose its
remaining fadeout. Instrument-only uses the cached-default contract below;
note-only uses the separate state-carry contract below. Explicit initialization does not alter
envelope/reset operations, gain ramps, replacement ramps, or downstream headroom
policy.

## Instrument-only cached defaults and reset

An ordinary valid instrument number with no note updates carried instrument
memory, then restores base/output volume and static pan from the last selected
declared header's cached defaults. A different instrument number does not select
its sample or change the sounding generation. Canonical note routing
resolves the exact 96-note keymap; editor sample selection is never an
input. The independent sample/header factor is unchanged: cached default 24
restores tracker volume 24, retaining sample factor `24/64` and gain `0.140625`.

For an existing voice generation, the adapter publishes the existing
volume-envelope/pan-clock/key-on/fadeout reset at the row's canonical tick-zero
frame. The shared semantic timeline and current-output 5 ms authority own all
reset math, completion, hold and ordinary-target continuation. No sample trigger, cursor
rewind, fractional-position change, loop-direction change or new voice occurs.
Cold defaults are volume 0 and pan 128; an explicitly selected canonical
empty header caches zero volume and zero pan. Completed/cut voices cannot resurrect;
cached defaults survive source completion/cut, and a later explicit mapped
trigger refreshes them and remains audible.

Same-cell volume-column/Cxx/fine-volume and static-pan writers follow default
restoration. Existing volume-column pan quantization remains unchanged. Prior
vibrato/tremolo controls govern phase reset before a same-cell E4x/E7x write;
speeds, depths, slide/portamento/offset memories persist.

Instrument-only K00 restores defaults and same-cell volume overrides but
releases without resetting envelopes, modulation phases or fadeout. Its volume
restoration wins the no-envelope release's usual zero-volume write; the shared
quick-volume publication uses 5 ms. Volume-column portamento retains its K00
precedence and ordinary reset. K01 resets at tick zero, then releases at tick
one. Delayed instrument-only ED1...EDF remains deferred.

`instrument-only-volume-semantics.xm` and direct/runtime tests cover this
contract. Audible pan envelopes, ECx quick-volume parity,
sample/header ownership parity and full FT2 mixer parity remain separate.

## Declared empty slots and silent channel state

A declared zero-payload XM header retains source-only volume, pan, finetune and
relative note in `XMSourceSampleSlotProvenance`. The canonical resolver still
returns no represented sample for that exact map entry. Ordinary explicit
selection updates the cached defaults, tracker volume/static pan and period
controls, then same-cell writers apply. It retires the prior source at the exact
frame; it creates no PCM, sample, cursor or C voice. Undeclared/unavailable
slots do not acquire invented header defaults. Editable playback projects the
unchanged sparse writer's all-zero empty-route contract without storing source
metadata in the editable document.

`PlaybackXMEnvelopeTimeline` owns channel clocks, key/release and integer fadeout
through these silent intervals, on the same Fxx tick frames. Instrument-only
restoration reuses its existing cache/phase/memory behavior; its silent reset
updates this timeline without an audible target. Release and volume-envelope
position writes can likewise address the silent channel. Completed sources stay
completed, and a stale event cannot update a replacement. The runtime stores
channel publications independently of C slots; offline windows query the same
plan. Only a matching live source receives C semantic/audible publications.

Empty-header tuning enters the existing supported period/effect calculations;
portamento targets and channel effect memories can persist without a source.
A later explicit playable note refreshes its own mapped defaults and restarts
its semantic envelope as before. A later note-only route instead carries the
progressed silent state and current tracker volume/pan. Audible
panning-envelope offsets, sample/header multiplication, ECx, onset, Rxy timing,
and delayed instrument-only behavior keep their separate boundaries.

## Note-only routing and state carry

An ordinary note with an empty instrument field resolves the carried instrument,
then the new note's exact 96-entry keymap route. Sounding sample identity and
editor selection do not supply an owner or fallback. No carried instrument or
absent map creates no source. Represented samples restart through the normal
event path, including same-sample, replacement and completed-source cases;
the cursor starts at zero unless an existing offset command applies.

Selection refreshes cached header volume/pan and mapped pitch/tuning, while
current tracker base/output volume and static pan carry. Modulation phases,
held output and effect memories also carry. Envelope carry includes the pending
segment value/slope/point, not just its clock: selecting another instrument's
curve must not resample it prematurely. Key/release state, fadeout accumulator
and the initialized fadeout decrement carry until an existing reset changes
them. A cold instrument-only selection followed by note-only can create a real
but zero-volume source; it does not invent initialized envelope state.

An empty note-only route consumes the retained zero-payload header and stops
the prior source at the same canonical frame. It creates no `PlaybackSample`
or C voice. The channel retains the same clocks, release, modulation and period
authority while silent. The volume-40 regression selects empty metadata at
tracker volume 16, restores cached 40 on a silent instrument-only row, then
starts a playable note-only at volume 40 and envelope tick 6. Tests contrast
header volume 0 and cover retained finetune/relative-note controls.

Tone-portamento `3xx`, `5xy` and volume-column `Fx` remain target-only paths.
K00 suppresses note-only selection; ED0 carries ordinary state, a valid delayed
note resets at its nonzero tick, and an out-of-row delay does not trigger.
E9 repeats reset channel semantics even for an empty route. Rxy retains its
existing scheduler; its FT2 repeat timing/state parity is not promoted.
The new public fixture and runtime tests share the adapter's exact frames and
window state. New-source onset still initializes immediately in VTX versus
FT2's 5 ms ramp; source replacement DSP and downstream sample scaling are
unchanged.

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
creates no voice. Instrument-only dispatch reuses this operation; ordinary
note-only carries its prior result into the new route.

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
and replacement lifetime keep their existing ownership. Final audible mono/L/R
start/target, duration/progress and retirement state are independently carried
using the same C transition operations as rendering.

Direct C, Swift, window, and runtime tests cover partial resets, cursor identity,
completion, stale generations, and exact application frames. Product WAV
auto-headroom and fixed runtime `-12 dB` headroom are independent of this state
operation; runtime auto-headroom remains disabled.

The [reset output contract](xm-reset-output-ramp.md) distinguishes the immediate
semantic operation from its implemented audible transition. A changed reset
target rebases from current audible mono/L/R through the existing shared C state
over `floor(sampleRate * 0.005)` frames, then holds until the next ordinary
target. Same-frame factor writes, window continuation and exact-frame runtime
application use that same authority, including instrument-only dispatch.

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
Explicit-instrument `ED0` resets immediately; note-only ED0 carries phase.
Successful nonzero delays reset at the scheduled
trigger, and out-of-row delays leave phase unchanged. `E9x` resets phase
without replacing held output, while `Rxy` volume writes replace output. See [FT2 trigger and row ordering](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1350-L1455).

Empty rows retain the last output. For base 32 and `748`, tick-0 through tick-5
outputs are `32, 32, 44, 54, 61, 63`; a following empty row retains 63. `C20`
replaces it with 32 even though base was already 32. Supported positive volume
writers operate on base and replace output at their existing command times.
Ordinary explicit note+instrument triggers load the mapped sample default before
same-cell volume commands, including after tremolo activation. Instrument-only
restores its cached triggered-sample default; specialized portamento/retrigger
paths retain their existing contracts. Sample scaling continues downstream.
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
- The fixture's note-only cells preserve tremolo state while restarting the
  carried instrument's exact mapped sample through the normal trigger path.
- Generic C-mixer gain-update ramps remain 32 frames. Managed XM envelope/release
  voices use the shared final-output cadence; FT2 ordinarily ramps across a tick. [FT2 ramp selection](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_audio.c#L270-L283)
  explains another rendering difference without changing the modulation target.
- Instrument-associated note 97 and note-plus-instrument `K00` retain their
  separate default-volume dispatch boundary. Ordinary no-envelope release zeros
  output; instrument-only K00 follows the cached-default/release ordering above.
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
