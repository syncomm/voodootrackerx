# XM Effect Support

This page tracks public XM effect support for VoodooTracker X. It is a
maintainer reference, not a promise of FastTracker 2 bit-perfect playback.

This page owns concise command-family support. The
[closure matrix](ft2-xm-closure-matrix.md) owns unresolved gaps, evidence and
dependencies; [the roadmap](roadmap.md) owns milestone sequencing. The target
is original FT2/XM, including loaded Linear and the specified Amiga paths.
Editable-copy admission remains a separate [ADR 014](decisions/014-loaded-xm-editable-copy-planning.md)
contract; support labels neither change it nor make loaded sources editable.

Reference hierarchy:

1. Current VTX source/tests establish current runtime/offline behavior.
2. Pinned [ft2-clone replayer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c)
   and matched reference renders establish the chosen FT2 behavior.
3. [MilkyTracker terminology](https://milkytracker.org/docs/manual/MilkyTracker.html)
   and [OpenMPT's reference](https://wiki.openmpt.org/Manual:_Effect_Reference#XM_Effect_Commands)
   triangulate it. Their extension behavior and generic descriptions do not
   redefine the FT2 target; disagreements are stated below.

The GPL reference is consulted for behavior/control flow only. Its source,
comments, tables, constants, fixtures and implementation structure are not
incorporated into MIT VTX.

## Independent status dimensions

| Dimension | Labels and meaning |
| --- | --- |
| Support | **Implemented**: the family exists in the default CoreAudio C-mixer runtime and bounded offline path. **Deferred**: an FT2 family has no implementation there yet. **FT2-inert**: the chosen FT2 dispatch intentionally does nothing. **Extension**: outside original FT2/XM v1. **Classification-only**: diagnostic unknown/unused byte, with no inferred playback behavior. |
| FT2 closure | **Closed**: evidence closes the stated bounded behavior only. **Partial**: a foundation exists, with unresolved interactions, memory or mode coverage. **Known difference**: a verified or explicitly retained mismatch. **Needs characterization**: the remaining reference behavior is not fully pinned. **Open**: a confirmed required behavior is absent. **Outside v1**: an extension/unknown is outside the chosen target. |
| FT2 memory | **None**: no parameter replay. **Own**: family-local memory, including independent directional or nibble state as specified. **Shared**: named families consume common state. **Special**: persistent control/loop state or special zero-form dispatch, rather than ordinary whole-command replay. **Not applicable**: outside the FT2 command target. This describes the reference obligation; notes say what VTX implements or lacks. |
| VTX pitch mode | **Linear**, **Amiga**, or **Both** identify implemented frequency-dependent paths. **Not applicable** means frequency-independent/inert behavior or no implemented pitch path; notes identify any missing Linear/Amiga target. It never grants support by itself. |

**Implemented + Partial** is valid. **Closed** does not assert complete audible
parity or close a neighboring family. FT2-inert no-op behavior is compatible
with this target, even where legacy diagnostics call the byte deferred.
Diagnostic strings such as `ignored_e90_no_effect_memory` describe VTX's current
outcome, not FT2 semantics; this cleanup changes no diagnostic schema.

## Fixture-Backed FT2/XM Effect Closure

After the separate Fxx timing and Linear/Amiga portamento-scaling corrections,
the next playback milestone is fixture-backed FT2/XM effect closure and
C-engine correctness. It is a sequence of narrow effect-family PRs, not one PR.
Its exit criterion is:

> Every FT2/XM command in the chosen VTX v1 compatibility scope is implemented
> and tested, or explicitly deferred with an evidence-backed technical or
> product reason.

Remaining FT2/XM v1 targets include:

- `Pxy` panning slide, `Txy` tremor, and `EEx` pattern delay;
- remaining relevant E-command gaps;
- volume-column vibrato and effect-memory gaps; and
- broader Amiga-table pitch parity where it remains in v1 scope.

Deferred implementation is an open closure obligation until implemented or
given an accepted, evidence-backed scope rationale. It is not an automatic v1
exclusion. OpenMPT/ModPlug extensions remain outside that target.

The [FT2/XM closure matrix](ft2-xm-closure-matrix.md) separates bounded closed
contracts from remaining timing, memory, output and frequency-mode differences.

Each effect-family slice uses the smallest sufficient project-generated public
XM fixture and a deterministic automated regression. An ft2-clone WAV rendered
from that same fixture is the primary FT2-style comparison; a secondary
renderer may triangulate, and focused diagnostics may confirm the root cause.
Optional anonymized maintainer-local corpus evidence may discover or prioritize
a suspected gap, but the gap must be reproduced independently with public or
synthetic evidence before it becomes committed regression coverage. The private
corpus is never a CI or release dependency.

Match sample rate, channels, bounds, and renderer settings before comparing.
Keep generated WAVs, JSON, Markdown, and traces under `/tmp` or another ignored
local path, and treat reference renders as evidence rather than automatic proof
of semantic correctness. Historical retired-backend behavior may inform an
investigation, but the current CoreAudio/C-mixer architecture remains
authoritative. See `docs/design/synthetic-xm-reference-fixture-pack.md` and
`docs/audio-comparison.md` for the fixture and comparison contracts.

## Instrument-only cells

Ordinary valid instrument-only cells restore cached defaults from the last
selected declared header and reuse the shared semantic and 5 ms audible reset.
They update carried instrument memory without selecting or retriggering a sample.
Declared empty routes retain header defaults/tuning and channel envelope/release
state without creating a voice. Instrument-only resets also work during this
silent interval. Cold channels stay silent and completed voices stay stopped.
Same-cell volume/pan
overrides and K00 release ordering are covered by the public fixture; see
[volume ownership](design/xm-volume-ownership.md#instrument-only-cached-defaults-and-reset).
Song gain consumes restored channel output once (G01); preview remains a
separate header/headroom policy. G06 pan-envelope targets reuse the existing
reset; ECx quick-volume parity remains deferred.

## Note-only routing

Ordinary notes with no instrument field use the carried instrument and resolve
the new note through its exact 96-entry keymap. A represented route restarts a
source at the canonical frame; a declared empty route consumes source-only
header defaults/tuning and retires the old source without creating a voice.
Tracker volume/static pan, envelope segment/release/fadeout and modulation
state carry. A silent instrument-only reset can restore an empty header's
cached volume 40; the next playable note-only retains 40 and the progressed
envelope. No owner or absent keymap yields no fallback trigger.

`3xx`, `5xy` and volume-column `Fx` retain their no-retrigger target paths.
K00 suppresses a normal note-only trigger; ED0 carries ordinary state, valid
nonzero EDx resets at its delayed tick, and out-of-row EDx does not trigger.
E9x retains repeat resets; Rxy keeps its existing repeat scheduler, with FT2
repeat timing/state parity deferred. VTX's immediate new-source onset versus
FT2's 5 ms onset ramp remains separate. See
[volume ownership](design/xm-volume-ownership.md#note-only-routing-and-state-carry).

## Effect Column Commands

Support applies to both runtime and offline paths. Closure is bounded by the
notes and matrix IDs, including the cross-cutting obligations below.

| Command | Name | Support | FT2 closure | FT2 memory | VTX pitch mode | Current behavior / remaining boundary |
| --- | --- | --- | --- | --- | --- | --- |
| `0xy` | Arpeggio | Implemented | Known difference | None; `000` inert | Linear | VTX's base/x/y cycle differs from FT2's speed-dependent remaining-tick order (G25). Amiga path missing (G26). |
| `1xx` | Portamento up | Implemented | Partial | Own; `100` supported | Linear | Correct nonzero-tick `4 * xx` units; Amiga upward path missing (G27). |
| `2xx` | Portamento down | Implemented | Partial | Own; `200` supported | Both | Linear `4 * xx`, Amiga `16 * xx` in VTX's 4x representation. Units are closed; shared conversion/extreme boundaries remain G30. |
| `3xx` | Tone portamento | Implemented | Partial | Shared with volume-column `Fx`; `300` target/speed supported | Both | No retrigger, target-clamped nonzero ticks and Amiga quantized targets are established. Missing-target/speed states and glissando remain distinct; Amiga `5xy`/`Fx` are not promoted. |
| `4xy` | Vibrato | Implemented | Partial | Shared with `6xy` and volume-column vibrato; independent speed/depth nibbles | Both | Integer modulation, initially-zero memory, `400`/zero-nibble replay and Amiga wrap/zero-step hold are closed. Full audible interactions remain G39; volume-column dispatch is missing (G10). |
| `5xy` | Tone portamento + volume slide | Implemented | Partial | Shared `3xx` target/speed and `Axy`/`5xy`/`6xy` slide byte | Linear | Seeded `500` replay and nonzero-tick slides exist. Cold `500` output/target interactions need characterization (G15); Amiga combined path missing (G28). |
| `6xy` | Vibrato + volume slide | Implemented | Partial | Shared `4xy` vibrato and `Axy`/`5xy`/`6xy` slide byte; `600` supported | Both | Vibrato then slide on ticks `1..<speed`; no tick-zero/speed-1 slide. Unseeded `600` restores base to output with zero amount. That timing/memory contract is closed; G39 remains. |
| `7xy` | Tremolo | Implemented | Partial | Own; independent initially-zero speed/depth nibbles | Not applicable | `700`, `70y`, `7x0`, integer nonzero-tick output modulation and empty-row phase/output carry are closed. Onset, ramps and trigger/cut interactions remain G39; G01 removes duplicate header scaling. |
| `8xx` | Set panning | Implemented | Known difference | None | Not applicable | Exact tick-zero panning state exists. Final stereo pan law differs (G40); this is separate from E8 and pan envelopes. |
| `9xx` | Sample offset | Implemented | Partial | Own; `900` supported | Not applicable | Same-cell source offset/memory exists; end/loop/offset boundaries remain G41. Safely skipping an out-of-range offset does not prove FT2 parity. |
| `Axy` | Volume slide | Implemented | Partial | Shared with `5xy`/`6xy`; seeded `A00` supported | Not applicable | Nonzero-tick slides exist. Cold `A00` fails to restore output from base volume with valid initial-zero slide memory (G14). |
| `Bxx` | Position jump | Implemented | Needs characterization | None | Not applicable | Focused traversal exists; conflicting B/D/E6 precedence, restart and bounds remain G38. |
| `Cxx` | Set volume | Implemented | Closed | None | Not applicable | Bounded tick-zero channel-volume state/clamp is supported; audible header/gain/ramp obligations remain separate. |
| `Dxx` | Pattern break | Implemented | Needs characterization | None | Not applicable | BCD target/traversal exists; broader B/D/E6 precedence remains G38. |
| `E0x` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch. VTX's no-op needs no audible XM filter; MOD hardware-filter semantics are a separate target. |
| `E1x` | Fine portamento up | Implemented | Partial | Own directional fine-up state; `E10` replay missing | Linear | Nonzero tick-zero `4 * x` adjustment, including same-cell notes, exists. Zero memory gap G17; Amiga path missing G29. |
| `E2x` | Fine portamento down | Implemented | Partial | Own directional fine-down state; `E20` replay missing | Linear | Same bounded timing/units as E1. Separate downward memory gap G17; Amiga path missing G29. |
| `E3x` | Glissando control | Deferred | Open | Special; persistent enable/disable control | Not applicable | Genuine FT2 v1 target G36, separate from inert E0/E8/EF. Linear/Amiga tone-output quantization still needs a focused oracle. |
| `E4x` | Vibrato control | Implemented | Closed | Special; persistent control for `4xy`/`6xy` | Not applicable | All 16 controls: sine/ramp/square/square; bit 2 suppresses phase reset; bit 3 ignored. Bounded control contract only. |
| `E5x` | Set finetune | Implemented | Partial | None; no-note form inert in pinned control | Linear | Same-cell note-trigger adjustment exists; Amiga path missing (G29). Diagnostic no-note deferral is not missing FT2 memory. |
| `E6x` | Pattern loop | Implemented | Partial | Special; channel loop start/counter | Not applicable | Explicit E60 start exists. Implicit initial loop start missing (G37); B/D/E6 ordering remains G38. |
| `E7x` | Tremolo control | Implemented | Closed | Special; persistent control independent of E4 | Not applicable | All nibble aliases and phase-reset suppression are supported; ramp retains FT2's vibrato-phase sign quirk. Full `7xy` audio remains G39. |
| `E8x` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch; current no-op matches. OpenMPT's audible panning alias is outside FT2 v1; use supported `8xx`. |
| `E9x` | Retrigger note | Implemented | Partial | Special; no ordinary interval replay | Not applicable | Nonzero intervals exist. `E90` is a missing special tick-zero retrigger (G19), not reuse of the preceding interval. `Rxy` is separate. |
| `EAx` | Fine volume slide up | Implemented | Partial | Own directional fine-up amount; `EA0` replay missing | Not applicable | Nonzero tick-zero parent exists; current zero no-op is G16, independent of EB/A/5/6 memory. |
| `EBx` | Fine volume slide down | Implemented | Partial | Own directional fine-down amount; `EB0` replay missing | Not applicable | Nonzero tick-zero parent exists; current zero no-op is G16, independent of EA/A/5/6 memory. |
| `ECx` | Note cut | Implemented | Known difference | None | Not applicable | VTX hard-retires the source. FT2 zeros base/output with a quick ramp and retains the cursor/source for recovery (G04). Internal hard stop is separate. |
| `EDx` | Note delay | Implemented | Partial | None | Not applicable | Valid same-cell ED0/nonzero delayed notes exist. Delayed instrument-only/default/reset interactions remain G23; out-of-row no-op is not full precedence closure. |
| `EEx` | Pattern delay | Deferred | Open | None | Not applicable | Standard FT2/XM v1 traversal/timing target G35. Row-duration/tick replay needs its own contract, separate from unrelated E effects. |
| `EFx` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch; no destructive MOD invert-loop/funk behavior. OpenMPT XM macro hacks are outside FT2 v1. |
| `F01...F1F` / `F20...FFF` | Speed / BPM | Implemented | Closed | None | Not applicable | Nonzero command-row tick-zero timing is closed. `F20` is valid XM BPM 32. Last speed and last BPM each win in left-to-right channel order. |
| `F00` | Zero speed boundary | Implemented | Known difference | None | Not applicable | VTX ignores it; pinned FT2 writes zero speed/tick state. Resulting traversal needs characterization and explicit closure rationale; nonzero Fxx stays closed. |
| `Gxx` | Global volume | Implemented | Partial | None | Not applicable | Clamped `0...64` state and active/future gains exist; cross-channel writer/output interactions remain bounded by the shared-output contract. |
| `Hxy` | Global volume slide | Implemented | Partial | Own channel-local byte; `H00` replay missing | Not applicable | VTX applies once at row start. FT2 nonzero-tick scheduling (G12) and H00 memory (G13) remain open. |
| `Kxx` | Key off | Implemented | Partial | None | Not applicable | Canonical-tick release, retained source and integer fadeout exist. No-envelope release zeros base/output except instrument-only K00 volume restoration. Note-97/K00/instrument/volume precedence remains G24. |
| `Lxx` | Set envelope position | Implemented | Partial | None | Not applicable | Existing volume positioning is preserved. Bounded G07 pan positioning is closed under the sounding instrument's raw volume-sustain flag, including disabled volume envelopes and silent-channel clocks. G31, G40 and pan-sustain/release differences remain open. |
| `Pxy` | Panning slide | Deferred | Open | Own byte; pinned `P00` replays it | Not applicable | Real FT2/XM v1 target G33. Legacy handler support is not C-adapter support; remaining timing/writer/pan-envelope interactions need characterization. |
| `Rxy` | Multi retrigger | Implemented | Partial | Own independent interval/mode nibbles; replay missing | Not applicable | First-pass active-voice scheduler and common-XM volume modes exist. R00/zero-nibble memory G20, persistent counter/tick-zero/carry G21 and exact FT2 arithmetic G22 remain open. |
| `Txy` | Tremor | Deferred | Open | Own byte; pinned `T00` replays it | Not applicable | Real FT2/XM v1 target G34. Counter/phase, cold state, trigger carry and volume-writer interactions still need characterization. |
| `X1x` / `X2x` | Extra fine portamento | Implemented | Partial | Own directional extra-fine states; `X10`/`X20` replay missing | Linear | Nonzero tick-zero `x` units exist. Missing memory G18 and Amiga paths G29 are separate from X extensions. |
| `X5x`, `X6x`, `X9x`, `XAx`, `Yxy`, `Zxx` | OpenMPT / ModPlug commands | Extension | Outside v1 | Not applicable | Not applicable | No runtime/offline support. Extension/hack families require a separately accepted compatibility target. |
| `Vxx`, `Wxx` | High-byte diagnostic unknowns | Classification-only | Outside v1 | None in pinned FT2 | Not applicable | Unused/dummy in pinned FT2 dispatch. Diagnostic occurrence does not establish an FT2 effect or identify an extension. |

`Rxy` volume mode handling currently follows common XM behavior: modes `1...5`
subtract `1, 2, 4, 8, 16`, modes `6...7` scale by `2/3` and `1/2`, mode `8`
is no change, modes `9...D` add `1, 2, 4, 8, 16`, and modes `E...F` scale by
`3/2` and `2`. The result is clamped to `0...64`. This is current VTX policy,
not exact FT2 arithmetic: G22's mode-6 control gives FT2 22 versus VTX 21 from 32.

## Zero forms and reference boundaries

Pinned FT2 [fine-pitch handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L620-L648),
[fine-volume handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L685-L713)
and [extra-fine handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1182-L1219)
establish independent up/down memories within each family. E10/E20, EA0/EB0
and X10/X20 continue their respective directional amounts at tick zero.
VTX currently returns zero-form no-ops; those are missing-memory obligations,
not inert FT2 bytes. Fine-volume memory is separate from A/5/6, and extra-fine
memory is separate from fine/regular pitch. Current Linear nonzero units stay
closed; missing Amiga execution cannot borrow that closure.

The pinned [E dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L733-L750)
and [nonzero-tick dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2209-L2227)
leave E0/E8/EF inert. The [note dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1394-L1460)
handles E90 at tick zero; the nonzero E9 handler does not replay an interval.
P00 and T00 use their own whole-byte memories in the
[pinned handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2106-L2161).
These are source-confirmed obligations, not claims of complete render-tested
P/T counters, cold initialization or writer precedence.

External descriptions disagree at some boundaries.
[OpenMPT's XM reference](https://wiki.openmpt.org/Manual:_Effect_Reference#XM_Effect_Commands)
lists an audible E8 panning alias and EF macro behavior, while pinned FT2 leaves
both inert. [MilkyTracker](https://milkytracker.org/docs/manual/MilkyTracker.html)
says E8 does not work in FT2 and describes F00 as stopping; OpenMPT describes
65535 ticks. Pinned FT2's
[Fxx handler](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L801-L814)
writes zero speed/tick state. VTX's ignored F00 therefore remains a known
difference needing explicit scope rationale and delivery characterization.
Neither description changes the closed XM F20/BPM-32 boundary.

Current implementation evidence is in the
[adapter pitch handlers](../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+PitchEffects.swift),
[volume handlers](../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+VolumeEffects.swift)
and [retrigger dispatch](../app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+SampleEffects.swift).
[PortamentoScalingTests](../tests/vtx_render_bounded_xm/PortamentoScalingTests.swift),
[VolumeSlideMemoryTests](../tests/vtx_render_bounded_xm/VolumeSlideMemoryTests.swift),
[TremoloTests](../tests/vtx_render_bounded_xm/TremoloTests.swift) and the
[adapter tests](../app/VoodooTrackerX/VoodooTrackerXTests/PlaybackSongAdapterTests.swift)
pin existing units, replay, modulation and current zero/E90 no-ops.
The matrix retains the distinguishing reference controls and remaining gaps.

## Volume Column Commands

The same dimensions apply. Volume-column slide amounts do not acquire
effect-column whole-command memory just because their names resemble it.

| Command family | Support | FT2 closure | FT2 memory | VTX pitch mode | Current behavior / remaining boundary |
| --- | --- | --- | --- | --- | --- |
| Set volume (`10...50`) | Implemented | Closed | None | Not applicable | Bounded channel-volume write exists; cross-cutting gain/output obligations remain. |
| Volume slide down/up (`60...7F`) | Implemented | Known difference | None | Not applicable | Once at tick 0 in VTX; FT2 uses nonzero ticks (G08). |
| Fine volume slide down/up (`80...9F`) | Implemented | Partial | None | Not applicable | Tick-zero scheduling is closed; zero amount still restores base to output. Shared gain/output boundaries remain. |
| Vibrato speed (`A0...AF`) | Deferred | Open | Shared vibrato speed with `4xy`/`6xy` | Not applicable | Diagnostic decoding only (G10); Linear/Amiga volume-column dispatch is missing. |
| Vibrato depth (`B0...BF`) | Deferred | Open | Shared vibrato depth with `4xy`/`6xy` | Not applicable | Diagnostic decoding only (G10); neither missing column borrows effect-column closure. |
| Set panning (`C0...CF`) | Implemented | Known difference | None | Not applicable | VTX `17 * nibble` versus FT2 `16 * nibble` (G11), separate from stereo pan law G40. |
| Panning slide left/right (`D0...EF`) | Implemented | Known difference | None; D0/E0 are special zero cases | Not applicable | VTX tick-zero approximation; FT2 nonzero ticks, D0 left-edge quirk and E0 no displacement (G09). |
| Tone portamento (`F0...FF`) | Implemented | Partial | Shared `3xx` speed; `F0` retains it | Linear | `64 * nibble` nonzero-tick units/no-retrigger targets are closed; Amiga column path missing (G28). |
| Unsupported / unknown bytes | Classification-only | Outside v1 | Not applicable | Not applicable | Diagnostic visibility grants no playback support. |

## Frequency Table Support

- Linear frequency table: primary v1 target and currently supported by the
  runtime/offline C mixer adapter path.
- Amiga frequency table: narrow implemented foundation for note
  period/frequency/sample-step calculation using the FT2-compatible quantized
  period lookup, sample finetune metadata, `2xx` portamento down, and
  effect-column `3xx` tone portamento, `4xy`, and the vibrato half of `6xy`
  in the runtime/offline C mixer adapter path.
- Broader Amiga-table pitch effects remain separate parity work; `0xy`, `1xx`,
  `E1x`/`E2x`, `X1x`/`X2x`, same-cell `E5x`, `5xy`, and volume-column
  tone portamento are not broadened by the Amiga foundation.
- Private Amiga-table coverage is tracked locally; do not publish private
  filenames, local paths, or corpus details.

## Shared Volume-Slide Memory Contract

The pinned FT2 [combined handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1971-L1985)
and [volume-slide handler](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2041-L2067)
use one channel-local `volSlideSpeed` byte for `Axy`, `5xy`, and `6xy`.
Nonzero parameters replace the whole byte; zero parameters replay it. Thus
`Axy`/`5xy`/`6xy` can seed `600`, and `6xy` can seed `A00`/`500`.
Mixed nibbles remain stored intact; a nonzero upper nibble wins during application.
Intervening rows/effects and note/instrument triggers preserve the memory.
Channel initialization starts it at zero, so unseeded `600` supplies no slide
amount; FT2 still copies base volume to output. Vibrato state is independent.

`Axy`/`5xy` scheduling and memory are unchanged. `6xy`/`600` now follow FT2's
[nonzero-tick dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2234-L2287): vibrato then the shared slide on ticks `1..<speed`.
[Tick-zero dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L985-L1031) does not slide; speed 1 has no slide, output restoration, or memory write/replay.
Each slide clamps base volume to `0...64` then copies it to output; unseeded
`600` restores base to output with zero slide amount. Trigger, gain/scaling,
and vibrato phase/value/frame contracts remain unchanged. Runtime and offline
apply their independent gain and pitch updates before rendering the shared frame.
`effect-memory.xm` pins speeds 1/3/6; this closes only the `6xy` row-level timing gap.

## Shared Vibrato Contract

On ticks `1...(speed - 1)`, `4xy` samples the current unsigned-byte phase,
computes the integer FT2 waveform magnitude, applies
`signedDelta = sign * ((magnitude * depth) >> 5)`, then advances phase by
`4 * speedNibble` modulo 256. Sine uses the 32-entry FT2 table; ramp uses
`8 * ((phase >> 2) & 31)`, complemented in the negative half; both square
aliases use magnitude 255. Phase bit 7 selects the negative half.

Nonzero speed/depth nibbles replace independent, initially zero memories on
nonzero ticks. `400` retains both, `40y` changes depth, `4x0` changes speed;
`6xy` consumes the same state. A speed-1 row does not write those memories.
Explicit instrument triggers, including instrument-only rows, reset phase
unless the previously stored control suppresses it. Note-only continuation
does not reset phase; a same-cell `E4x` write occurs after the trigger reset.

FT2 and VTX Linear periods have the same coordinates: C-4 is 4608 and an
octave is 768 units. Output period is base period plus signed delta, with
the existing Linear range guard; sample step is
`baseHz * 2^((4608 - outputPeriod) / 768) / outputHz`. Modulation never changes
the base. Consecutive `4xy`/`6xy` rows hold output through tick 0; leaving the
family restores the base. The public `vibrato-semantics.xm` fixture and
`VibratoFoundationTests` pin this contract against the
[pinned FT2 replayer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1836-L1866).

Note-only triggers restore the mapped note's pitch at tick zero without
resetting modulation phase. Linear range-edge behavior remains a parity boundary.

Amiga `4xy` and the vibrato half of `6xy` apply the same signed delta using
`resultFT2 = (baseFT2 + signedDelta) mod 65536`, then
`resultVTX = 4 * resultFT2`. C-4 at finetune 0 is FT2 1712 / VTX 6848.
This operation does not use the separate note/portamento clamp or alter the
unmodulated base. Nonzero step is `baseHz * 1712 / resultFT2 / outputHz`;
period zero produces an explicit step-zero update. The existing C mixer holds
the active source cursor while rendered-frame time and playback follow advance;
a later nonzero update resumes that same voice. Underflow and upper overflow
wrap, including 118 - 119 = 65535 and 65417 + 119 = 0.

`amiga-vibrato.xm`, `AmigaVibratoTests`, and `RuntimeCMixerTests` pin periods,
memory/controls, zero hold/resume, and exact runtime/offline event frames.
The existing extreme Amiga note-base clamp remains a separate parity boundary,
as does FT2 fixed-point versus VTX analytic frequency conversion. This does not
promote other Amiga pitch families; the shared slide schedule is specified above.

## Portamento Units

Linear periods use 64 units per semitone: a decrease of `d` units multiplies
frequency/sample step by `2^(d/768)`. Regular/tone and fine commands use
`4 * parameter` units; extra-fine remains `parameter`, preserving the 4:1 ratio
with fine slides. Fine and extra-fine apply once at tick 0; regular/tone slides
apply on ticks `1...(speed - 1)`. Volume-column `Fx` stores `x << 4` in the same
raw-parameter speed memory as `3xx`, then uses that shared period conversion.

Amiga state uses **four times FT2's table period**, including quantized targets
and the frequency numerator: C-4 is 6848 in VTX versus 1712 in FT2. Its existing
`16 * xx` delta for supported `2xx`/`3xx` equals FT2's `4 * xx`; reducing it to
4 would introduce a regression. The historical VTX-CS-002 audit omitted that
additional representation scale. For `210`, FT2's 1712 → 1776 and VTX's
6848 → 7104 both give `8363 * 1712 / 1776` Hz before mixer quantization.

These units follow the pinned ft2-clone
[regular/tone handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1891-L1949),
[fine handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L620-L648),
[extra-fine handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1182-L1219),
and [volume-column decoding](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1397-L1415).
The public `portamento-scaling-linear.xm` and `portamento-scaling-amiga.xm`
fixtures pin these supported paths; no deferred effect family is promoted.

## Cross-cutting FT2 closure obligations

The matrix owns IDs, reference controls, prevalence and dependencies. Command
support alone does not close these domains:

- **Volume and transitions:** G01 song gain consumes channel/output volume
  once while the header initializes/restores defaults. Exact mapped represented
  PCM remains a valid source at header volume 0; later Cxx reveals the continuing
  source, while canonical empty/unrepresented routes remain source-less.
  Preview availability and safety gain are unchanged. New-note onset, same-channel
  replacement/retirement, ECx retained-source/cursor and quick-output behavior,
  and generic ramps (G02–G05) remain open. Existing
  cached defaults and shared final-L/R reset targets are established foundations.
- **Panning:** exact header/8xx state, final stereo pan law (G40), semantic pan
  clocks, audible pan-envelope factor (G06), and Lxx pan positioning (G07) are
  distinct. G06 now composes the carried pan value into the existing final-L/R
  target, preserving neutral/static baselines and silent routes. Existing
  fractional/point-64 arithmetic and pan-sustain release differences remain open.
  Lxx now positions the existing pan clock under the sounding instrument's raw
  volume-sustain flag, independent of volume enable/loop flags. Command-frame
  position/value controls match the pinned reference at both rates. The bounded
  G07 positioning contract is closed with automated controls and external
  maintainer Xcode/listening acceptance. Volume Lxx is unchanged; this does not
  close overall panning-envelope parity.
- **Envelopes and instrument modulation:** volume/pan clocks, sustain/loop,
  release and integer fadeout foundations exist. Fractional envelope arithmetic
  (G31) and pan-clock quirks still need closure. Instrument autovibrato (G32) is
  preserved but runtime-inert and remains Phase 2 playback work; later editable
  Instrument Editor controls are a separate roadmap milestone.
- **Volume writers and memory:** volume-column timing/quirks (G08–G11), Hxy
  scheduling/H00 (G12–G13), cold A00/500 (G14–G15), and directional fine-slide
  memory remain open. Rxy counter lifetime, nibble memory, tick-zero dispatch,
  semantic carry and exact volume arithmetic (G20–G22) cannot be closed by its
  common-XM table. ED delayed note/instrument/default interactions and
  note-97/K00/instrument/volume precedence remain G23–G24.
- **Traversal:** EEx is a dedicated timing contract (G35). Bxx/Dxx/E6x
  precedence and E6's implicit loop start remain G37–G38; safe finite export
  guards do not establish reference in-song traversal parity.
- **Pitch and mode:** arpeggio tick order, Amiga 0xy/1xx/5xy/volume-column Fx,
  Amiga E1/E2/X1/X2 and same-cell E5, plus conversion/range boundaries remain
  G25–G30. Supported Amiga vibrato's unsigned wrap/zero hold is closed; other
  period wrap/clamp behavior is not. Full 4xy/6xy/7xy audible interactions
  remain G39 without reopening their closed integer engines or 6xy timing.
- **Sources and loops:** 9xx/900 offset/end/loop boundaries and ping-pong
  turnaround precision remain under G41 where unclosed. Sample/instrument
  changes must preserve exact routing, defaults, silent clocks and note-only
  carry; their unusual delay/retrigger/release precedence stays open.

See [volume ownership](design/xm-volume-ownership.md) and
[reset/output targets](design/xm-reset-output-ramp.md) for retained policies and
bounded foundation tests. Current differences require a focused policy change
or explicit accepted rationale; aggregate audio correlation is not closure.

## Pending FT2 targets and exclusions

- Deferred FT2 parents: E3x, EEx, Pxy, Txy, volume-column vibrato and instrument
  autovibrato. Fine-slide zero memory and missing Amiga paths remain in v1 scope.
- E0x/E8x/EFx are FT2-inert. Adding an audible filter, E8 panning alias, MOD
  destructive funk or XM macro behavior would change the target.
- X5/X6/X9/XA, Y/Z and other OpenMPT/ModPlug hacks are extensions outside v1.
  V/W remain classification-only unknowns, not inferred extensions.
- F00 is a known difference awaiting explicit closure rationale, separate from
  the completed nonzero Fxx contract. No new exclusion is adopted here.

## Maintenance Note

Update this page whenever an XM effect PR lands. Corpus coverage reports are
private/local evidence; public docs and PR summaries should use anonymized
labels only and should never include private module filenames or local paths.

The synthetic XM reference-fixture plan supplies the incremental public-fixture
contract for effect-family parity work; reference renders and generated metrics
remain local unless a separately reviewed change explicitly approves them.
