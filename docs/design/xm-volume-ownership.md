# XM Volume Ownership

This note owns the shared adapter's volume-state boundary. The base/output
separation owns tracker volume; G01 removes the duplicate song header multiplier.
Effect statuses remain owned by [XM effect support](../xm-effect-support.md).

## State and gain domains

| Component | Domain and lifetime | Writers and consumers |
| --- | --- | --- |
| `baseChannelVolume` | Integer `0...64`; persistent, channel-local; initially 64 | Instrument/default-volume paths, `Cxx`, volume-column volume/slides, `Axy`, `EAx`/`EBx`, `5xy`/`6xy` volume components, and `Rxy` volume modes write the base. No-envelope key-off zeros it. Each retains its timing, memory, and clamp policy. |
| `outputChannelVolume` | Integer `0...64`; channel-local output retained between writes | Follows each base write. `7xy` writes output independently; empty rows retain it. Trigger and active-voice gain construction consume output. |
| `PlaybackSample.volume` / `activeSampleVolume` | Header `0...64` normalized to Float `0...1`; immutable sample metadata plus channel-local active selection | The header initializes/restores cached channel defaults. Active metadata also retains represented-source availability; it is never a second song-gain multiplier. |
| Global volume | Integer `0...64`; persistent, song-local; initially 64 | `Gxx` sets at tick zero; resolved nonzero `Hxy`/`H00` mutates on ticks `1..<effectiveSpeed` in channel order. Gain publications capture the global value visible at that channel's turn. Future triggers use the final canonical value. |
| Hxy memory | Optional whole nonzero byte and provenance; independent per tracker channel; initially absent | Executed nonzero Hxy establishes it; H00 recalls it without writing zero. F01 does not seed or replace it. Independent of shared Axy/5xy/6xy memory and song-global volume. |
| Axy/5xy/6xy memory | Optional whole nonzero byte and provenance; channel-local; initially absent | Cold A00 executes implicit zero on nonzero ticks without creating history. A real nonzero A/5/6 seed enables the existing shared replay path. |
| Volume envelope | Point values `0...64` normalized to `0...1`; channel-local progression, projected to a live source when present | `PlaybackXMEnvelopeTimeline` publishes logical position/value at canonical Fxx tick frames, including release and `Lxx`. C holds the imported target until the next publication. |
| Fadeout | Channel-local integer `0...32768`, initially 32768; factor `accumulator / 32768` | The shared timeline subtracts instrument fadeout on the release tick and every subsequent XM tick, clamping at zero. C holds the factor without advancing a second clock. |
| Planned voice gain | Float `0...1`; trigger value with scheduled active-voice updates | `songGain` consumes output volume once with global volume. Managed XM envelope/release voices combine it with semantic factors in one final-output target; generic voices retain existing gain/pan ramps. |
| Held scalar gain target | Last publication by source event identity, initialized from trigger gain | Distinct from canonical global/base state and hypothetical calculated gain. A real publication compares its requested target to this held value; replacement starts a new identity. |
| Mix/output gain | Render/host/export policy; independent of channel state | Existing mix profile, runtime headroom, and export gain policies apply downstream. Summed Float32 PCM may exceed unity; encoded PCM16 clamps at the export boundary. |

The owning implementation is
[PlaybackSongSyntheticAdapter](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter.swift),
its volume/effect helpers, and
[gain construction](../../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+RuntimeEvents.swift).
Base writes synchronize output without an unconditional row-start or row-end copy.
Existing base-volume writers synchronize output; `7xy` can leave output distinct
from base until another volume writer replaces it. Header metadata, envelope
clocks, and existing trigger-selection policies remain separate.

## Song gain and clamps

```text
base write -> output follows
planned song gain = clamp01(clamp64(outputChannelVolume)/64
                         * clamp64(globalVolume)/64)
XM amplitude target = planned gain * semantic envelope * semantic fadeout
XM stereo PCM = PCM * interpolated final L/R target
generic voice amplitude = PCM * ramped gain * envelope * fadeout
```

Existing volume writers clamp integer state; gain construction also normalizes
and clamps its inputs/output. Header normalization stays in the default-state path.
Envelope and fadeout stay outside the planned gain. Panning and downstream mix
policies remain outside tracker-volume state.

At full global volume, these cases are independently representable:

| Sample header | Base | Output | Planned gain |
| --- | --- | --- | --- |
| 64 | 16 | 16 | 0.25 |
| 16 | 64 | 64 | 1 |
| 16 | 16 | 16 | 0.25 |
| 0 | 0 | 0 | 0 |
| 0 | 32 | 32 | 0.5 |

Sample-header volume initializes/restores the channel default. Song audible gain
consumes channel/output volume once; the header is not multiplied again as an
independent song-gain factor. Header metadata and tracker state remain distinct.

Exact mapped represented PCM remains a valid song source at header volume 0.
The canonical resolver's song eligibility requires PCM, independently of header
loudness; identity, note/map validation and fallback policies are unchanged.
The source starts at its canonical frame, progresses through its loop while
silent, and later Cxx reveals the same continuing source without a trigger or
cursor reset. Instrument-only restoration can silence it by restoring cached
zero without invalidating its route. Canonical empty/unrepresented routes still
create no source.

Direct editor preview consumes the represented sample header once, then applies
its existing runtime headroom and preview safety cap. It does not use song
channel state or `songGain`; Sample Editor and Instrument Editor routing and
preview levels retain their existing contract, including the positive-header
availability predicate for both mapped and direct preview.

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
Explicit volume-column and `Cxx` writes still override the default.
Default/header 16 initializes base/output 16
and produces song gain `0.25` at full global volume without envelope/fadeout.
A later or same-cell `C20` replaces output with 32 and yields `0.5`, independent
of the original header.

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
input. Cached default 24
restores tracker output 24 and song gain `24/64 = 0.375` before global/envelope/
fadeout factors.

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
restoration. Column Cx supplies the G11 byte rule below. Prior
vibrato/tremolo controls govern phase reset before a same-cell E4x/E7x write;
speeds, depths, slide/portamento/offset memories persist.

Instrument-only K00 restores defaults and same-cell volume overrides but
releases without resetting envelopes, modulation phases or fadeout. Its volume
restoration wins the no-envelope release's usual zero-volume write; the shared
quick-volume publication uses 5 ms. Volume-column portamento retains its K00
precedence and ordinary reset. K01 resets at tick zero, then releases at tick
one. Delayed instrument-only ED1...EDF remains deferred.

`instrument-only-volume-semantics.xm` and direct/runtime tests cover this
contract. G06 pan-envelope targets reuse that reset; ECx quick-volume parity and
full FT2 mixer parity remain separate.

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
progressed silent state and current tracker volume/pan. G06 consumes the carried
pan segment only when a real source exists. ECx, onset, Rxy timing,
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
FT2's 5 ms ramp; source replacement DSP and downstream mix policies are
unchanged.

## G08 ordinary volume-column slides

`6x/7x` change base volume by the current low nibble on ticks `1..<speed`,
clamping to `0...64`; output follows each write. Tick zero and speed 1 leave
both domains unchanged. From 32, `61` ends at 32/30/27 for speeds 1/3/6;
`71` ends at 32/34/37. `60/70` have no amount memory: on each nonzero tick
zero displacement still restores held tremolo output from base.

Header defaults, column set-volume and Cxx retain their tick-zero order.
Each later column slide precedes a coincident A/5/6 or tremolo writer, with
independent effect-column memory. Existing delayed triggers/reset run after
that tick's column write; later ticks slide from the reset state. Fine `8x/9x`
still write only at tick zero. Silent and completed sources retain channel
state; a later note-only route observes it without an invented voice.

The public `volume-column-slide-timing.xm` and direct/runtime controls pin
these values, effective Fxx speeds and 44.1/48 kHz frames. They reuse song gain,
envelope/fadeout clocks and the existing audible output targets. Cold channel
initialization, G31 arithmetic, G40 pan law,
onset and generic ramps retain their separate boundaries.

Canonical full Xcode verification passes. The maintainer reported a passing
listen for `xm-corpus-198` at zero-based order 1, pattern 0, row 0, channel 9,
and regression sentinel `xm-corpus-011`, with slides progressing across ticks
and no unrelated regression heard. This records maintainer acceptance.

## G09 ordinary volume-column panning slides

`Dx/Ex` change stored pan by the current low nibble on ticks `1..<effective
row speed`, clamping to `0...255`. Tick zero and speed 1 preserve it. From
128, `D1` ends at 128/126/123 for speeds 1/3/6; `E1` ends at 128/130/133.
On each nonzero tick `D0` sets pan to zero, including from interior/right
positions; `E0` leaves it unchanged. Neither uses amount memory or Pxy memory.
An unchanged value retains its existing static conversion.

Explicit sample defaults, column Cx and effect 8xx retain their tick-zero
order. Note-only carries current pan; silent declared routes and completed
sources retain it without fabricating a voice. Existing cold initialization
remains 127.5 versus FT2's 128; explicit 8xx source-less controls pin the slide
contract independently. Cx's byte mapping is owned by the G11 contract below.

The planner captures each slide's stored pan alongside the existing typed
update. Semantic publications consume that value for G06 reach/displacement,
including final-value tail carry. G06/G07 clocks and arithmetic, final-L/R
composition and ramp policies remain unchanged. The public fixture, constant
controls and canonical host prove both-rate frames/output; G08 PCM and static
header/Cx/8xx before/after controls were identical for the G09 change. G33/G40
stay open; G11 corrects only the Cx input below.

## G11 volume-column static-pan mapping

`C0...CF` supplies `16 * nibble` to existing channel pan state at tick zero.
All sixteen values match the pinned reference: C8 is 128, CF is 240, and CF
does not select the 255 endpoint. Sample/header defaults precede Cx; effect
8xx follows it and retains its exact byte. Silent/source-less Cx carries into
later note-only routing without creating a voice. G09 slides start from this
corrected base; D0/E0 timing and amount-memory absence remain unchanged.

Public constant-loop controls pin every byte, precedence, carry, G06/G07 and
both-rate whole/window/runtime targets. This changes one decoder input rule,
not G06 displacement, G07 positioning/clocks, final-L/R authority or G40
conversion/profile law. The PlaybackEngine decision trace reports the same
Cx bytes without a schema change. Direct sample/editor preview consumes header
pan and is unchanged. G33/Pxy, G40 and the cold 127.5 baseline remain separate.

At 44.1/48 kHz, 750 observed stored-pan ticks and 642 targets under the current
law agree per rate. Canonical CoreAudio delivery applies all 261 control events
per rate with zero frame delta; capture/offline PCM error is below `1.91e-5`.
Header/8xx and G08/G09 baseline controls remain byte-identical. Full Xcode passes.

## Runtime, offline, and diagnostics

`RuntimeCMixerAdapterEventPlan` and bounded/windowed offline rendering consume
the same adapter triggers and `voiceStateUpdates`. Both schedule the existing
C-mixer gain input at planned frames; neither recomputes a second tracker-volume
authority. Runtime host delivery and offline comparison retain their roles in
[audio comparison](../audio-comparison.md).

Adapter `effectiveVolumeValue` and update `effectiveVolumeBefore/After` describe
tracker output in `0...64`; sample volume remains header metadata. `gainBefore/After`
are output/global products before the C-mixer envelope/fadeout and mix
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

XM panning metadata supplies the existing segment/clock with its point positions,
sustain and loop boundaries. G06 publishes the held pan value and composes its
byte-domain displacement into the same final-L/R target. Neutral values preserve
the exact static baseline. Generic synthetic mixer panning envelopes and editor
preview retain their established behavior. `Lxx` positions this same pan clock
under the sounding instrument's raw volume-sustain flag, preserving the existing
volume-position path. The bounded G07 positioning contract is closed with
automated controls and external maintainer Xcode/listening acceptance.
Static conversions/profile laws (G40) and pan-clock/Q8 quirks remain
separate; see the [G06 factor](xm-reset-output-ramp.md#g06-panning-envelope-factor)
and [G07 positioning](xm-reset-output-ramp.md#g07-lxx-panning-envelope-positioning)
contracts.

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
paths retain their existing contracts. Their song gains consume output once.
Nonzero tremolo ticks are planned after all row-start channel/global writers,
so a later channel's `Gxx` cannot see an earlier channel's future tremolo output.

## Reference coverage and retained boundaries

The public [tremolo fixture](../../tests/reference-xm/README.md#generated-fixtures)
provides ordinary, memory, waveform, phase, and empty-row cases. Direct tests
pin tracker-domain values; runtime/offline tests pin plans and applied frames.
The unchanged pinned FT2 replayer agrees with every fixture tick's output and
all tremolo update states. This is not a waveform-identical rendering claim:

- G01 consumes tremolo output once: header 16 plus explicit channel volume 32
  yields song gain 0.5 before other factors, matching the pinned reference.
  Quiet-header tests retain exact integer depth, output clamping and frames.
- The fixture's note-only cells preserve tremolo state while restarting the
  carried instrument's exact mapped sample through the normal trigger path.
- Generic C-mixer gain-update ramps remain 32 frames. Managed XM envelope/release
  voices use the shared final-output cadence; FT2 ordinarily ramps across a tick. [FT2 ramp selection](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_audio.c#L270-L283)
  explains another rendering difference without changing the modulation target.
- Instrument-associated note 97 and note-plus-instrument `K00` retain their
  separate default-volume dispatch boundary. Ordinary no-envelope release zeros
  output; instrument-only K00 follows the cached-default/release ordering above.
- Cold `A00` restoration is closed under G14 below. `EA0`/`EB0`, `R00`, and
  other deferred cases retain their documented status. G09 closes column panning-slide timing;
  G12 closes nonzero Hxy timing and channel-turn publication; G13 closes H00
  memory with the cold artifact excluded below.

## Gxx channel-turn birth and held-target publication

Gxx changes one canonical song-global value at its channel turn. A note before
G10 starts at factor 1; a note after or in the same cell starts at 0.25. Notes
before/between/after G20 then G10 start at `[1, 0.5, 0.25]`. Later same-tick
writers do not retroactively backfill earlier birth/held targets. This is the
adopted B compatibility convention where written XM ordering is ambiguous.

The shared planner projects canonical transitions into `gxxChannelTarget`
snapshots in ascending channel order, reusing the Hxy held-target mechanism.
Plain targets persist across blank rows and pan-only commands. Cxx,
volume-column volume and later Gxx request publication against the active
generation's held target, even when canonical calculated gain did not change:
repeated C40/volume-column 50/G10 repairs held 1 to 0.25; C20 after G00 repairs
held 1 to zero. Enabled volume envelopes refresh on their next tick through the
existing final-output path, without changing envelope arithmetic or plain-voice
management.

Birth-equivalent snapshots need no separate gain event. Changed later targets
follow their generation's birth; offline preallocation grants no extra semantic
rights. Whole/window/runtime consume these same causal events and existing
ramps. Source-less writers create no voice, later notes inherit canonical state,
and stale publications cannot target replacements. No callback interprets Gxx.

## Hxy channel-turn gain publication (G12)

Hxy mutates one canonical song-global value in ascending channel order on
nonzero ticks. H01 at channel 0 followed by H10 at channel 2, starting at 32,
produces canonical transitions `32 -> 31 -> 32` and channel target factors
`[31, 31, 32]`. A later writer never recomputes an earlier turn's target.
These are held gain snapshots by trigger identity, not per-channel global state
or an additional multiplier. Source-less writers still change the canonical
state; later triggers inherit it without a fabricated voice.

The adapter records canonical H mutations separately from explicit
`hxyChannelTarget` publications, interleaved by tick/channel. Each target consumes
channel output volume and its visible global value once. Unchanged targets
produce no redundant mixer gain event. The existing final-L/R path applies
envelope/fadeout downstream and preserves its clocks and ramps; plain voices
retain the existing generic ramp policy (G05 remains open).

After Hxy ends, a plain target can retain an intermediate factor across blank
rows and pan-only commands. A later note starts with the final canonical state;
Cxx, volume-column volume, and Gxx publish at their channel turns. Volume
envelopes and released voices refresh each tick, so an earlier channel sees the
previous tick's final state on its next turn. Window history retains these
publications and their existing ramp progress. No callback interprets Hxy.
Seeded H00 follows this same G12 publication contract.

## H00 effect-memory replay (G13)

H00 effect-memory replay is **CLOSED**. Each tracker channel owns an optional
nonzero Hxy byte and its source provenance, independently of Axy/5xy/6xy.
H01/H10/H12/H21 retain exactly `01`/`10`/`12`/`21`; replay resolves the whole
byte before applying upper-nibble precedence. H00 never overwrites it with zero.
Memory is established only when the row executes nonzero ticks: F01 neither
seeds a cold channel nor replaces prior memory. F01/F03/F06 replay executes
0/2/5 times. Notes, instruments, key-off, blank rows, pattern/order changes,
empty routes and completed sources preserve memory; a fresh song plan initializes
it absent. Window reconstruction retains the already-planned transitions.

A seeded H00, including H01 at global zero or H10 at 64, uses G12's existing
ascending channel turns, clamp and target publications. There is still exactly
one song-global volume, no per-channel global value and no additional gain stage.
Starting at 32, H01 then H00 ends at 27 then 22; H10/H12 ends at 37 then 42;
H21 ends at 42 then 52.

The explicit compatibility decision classifies whole-byte channel-local replay
as **A: intended semantics**, and FT2's cold zero-memory target refresh as
**C: implementation artifact**. The latter is **INTENTIONALLY NOT EMULATED**,
a known reference difference. Cold H00 is a true no-op with no audio publication.
In the public counterexample, channel 1 H01 takes canonical 32 to 27 while an
earlier plain channel holds 28/64. A later cold H00 on channel 0 or 2 leaves
canonical 27 and held 28/64, with PCM identical to a blank command. Pinned FT2
instead refreshes that held target to 27/64 through its unconditional zero-amount
volume flag. No bit-perfect cold-H00 parity is claimed.

The [pinned H handler](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2068-L2097)
is behavioral evidence only. Project-authored tests/fixtures cover whole-byte
resolution, independence, mixed cold/seeded turns, Fxx, lifetime, Gxx, clamp
replay and whole/window/runtime parity at 44.1/48 kHz. G12 remains authoritative;
this contract changes no envelope arithmetic, DSP, host or callback behavior.

## Cold A00 base-to-output restoration (G14)

Cold A00 is a bounded **B compatibility convention**: on ticks
`1..<effectiveSpeed`, leave base volume unchanged, restore output from current
base, and request an explicit causal local volume publication. No tick-zero or
speed-1 restoration occurs. Absent memory stays absent; later real Axy/5xy/6xy
seeds retain their original whole byte and provenance.

After base 32 and speed-6 748, output 63 becomes 32 at A00 tick 1; phase 80,
speed 4, depth 8 and E7 control remain intact. Later 700 resumes that state.
Current Cxx, volume-column and reset-established bases are authoritative.
Envelope/fadeout clocks and final composition are unchanged. A publication
compares against the source generation's held target even when base arithmetic
or calculated gain is unchanged, and identical targets deduplicate.

Silent routes restore persistent output for later explicit note-only inheritance
without PCM fabrication or source resurrection. `ColdA00Tests` and the public
fixture cover rates, speed/Fxx, resets, envelopes, shared seeds and generations.
Cold H00 remains a true no-op under G13. Cold 500 and the separate cold-600
numeric-no-op target-refresh difference are outside G14.

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
