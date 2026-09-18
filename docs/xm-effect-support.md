# XM Effect Support

This page tracks public XM effect support for VoodooTracker X. It is a
maintainer reference, not a promise of FastTracker 2 bit-perfect playback.

The command names follow FT2/MilkyTracker-style XM terminology. OpenMPT and
ModPlug compatibility commands are called out separately when they are outside
the original XM target.

Reference framing: [MilkyTracker's effect command reference](https://milkytracker.org/docs/manual/MilkyTracker.html)
and [OpenMPT's effect reference](https://wiki.openmpt.org/Manual:_Effect_Reference).
VoodooTracker X status is based on this repo's implementation and tests, not on
external tracker feature completeness.

## Status Legend

- Implemented: supported in the default CoreAudio C mixer runtime path and
  offline bounded C mixer render path, with automated tests and corpus
  diagnostics where applicable.
- Implemented, parity-watch: implemented in the runtime/offline C mixer path,
  but known tracker-compatibility nuance, effect-memory nuance, or corpus
  residuals remain tracked.
- Deferred: known XM/FT2 command intentionally not implemented yet.
- Classification-only: recognized for diagnostics or coverage reporting, but
  not a playback target yet.
- Not targeted for v1: OpenMPT / ModPlug extensions or non-FT2 compatibility
  commands outside the current XM v1 target.

Implemented means supported by VTX's current runtime/offline C mixer path. It
does not claim bit-perfect parity with every FT2 clone, tracker quirk, or
hardware configuration.

## Fixture-Backed FT2/XM Effect Closure

After the separate Fxx timing and Linear/Amiga portamento-scaling corrections,
the next playback milestone is fixture-backed FT2/XM effect closure and
C-engine correctness. It is a sequence of narrow effect-family PRs, not one PR.
Its exit criterion is:

> Every FT2/XM command in the chosen VTX v1 compatibility scope is implemented
> and tested, or explicitly deferred with an evidence-backed technical or
> product reason.

The target is the chosen FT2/XM v1 scope, not OpenMPT/ModPlug extensions or
every historical tracker quirk. Known candidates for later focused slices
include:

- `Pxy` panning slide, `Txy` tremor, and `EEx` pattern delay;
- remaining relevant E-command gaps;
- volume-column vibrato and effect-memory gaps; and
- broader Amiga-table pitch parity where it remains in v1 scope.

Keeping a candidate visible does not promise that it must ship. The command
tables below remain authoritative, and this planning definition changes none of
their support statuses.

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

## Effect Column Commands

| Command | Name | Status | Effect memory | Runtime support | Offline support | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `0xy` | Arpeggio | Implemented, parity-watch | Deferred for broad memory | Yes | Yes | Deterministic tick-cycle sample-step updates; `000` is a no-op. |
| `1xx` | Portamento up | Implemented, parity-watch | `100` memory supported | Yes | Yes | Linear slides subtract `4 * xx` period units per tick after tick 0; Amiga-table `1xx` remains deferred. |
| `2xx` | Portamento down | Implemented, parity-watch | `200` memory supported | Yes | Yes | Linear slides add `4 * xx` period units per tick after tick 0; the existing narrow Amiga-table period/sample-step path is preserved. |
| `3xx` | Tone portamento | Implemented, parity-watch | `300` reuses existing target/speed when available; no broad quirk claim | Yes | Yes | No-retrigger target setting, `300` target/speed memory, and target-clamped updates after tick 0 (Linear `4 * xx` period units); Amiga targets use the FT2-compatible quantized period lookup. No-active/no-target/no-speed/missing-memory residuals remain parity-watch. |
| `4xy` | Vibrato | Implemented, parity-watch | Initially zero speed/depth; `400` / zero-nibble memory supported | Yes | Yes | FT2 integer phase/waveform modulation in Linear mode; Amiga execution remains deferred. See the shared contract below. |
| `5xy` | Tone portamento + volume slide | Implemented, parity-watch | Uses existing `3xx` tone target/speed; `500` reuses shared Axy-style volume-slide memory when available | Yes | Yes | Reuses Linear `3xx` speed in `4 * xx` period units and the independent `Axy` tick-level volume-slide policy; missing `500` volume-slide memory remains no-op/deferred. |
| `6xy` | Vibrato + volume slide | Implemented, parity-watch | Shared `4xy` vibrato memory; `600` volume-slide memory deferred | Yes | Yes | Corrected Linear vibrato plus the existing row-level volume-slide path. Amiga vibrato and tick-level slide correction remain separate work. |
| `7xy` | Tremolo | Implemented, parity-watch | Independent speed/depth nibble memory, initially zero; `700`, `70y`, and `7x0` supported | Yes | Yes | Exact integer output-volume modulation after tick 0; phase and output persist across empty rows. Existing sample scaling, gain ramps, and trigger/other-effect boundaries remain; see [volume ownership](design/xm-volume-ownership.md#tremolo-output-memory-and-controls). |
| `8xx` | Set panning | Implemented | Not applicable | Yes | Yes | Row-level panning state update. |
| `9xx` | Sample offset | Implemented | `900` memory supported | Yes | Yes | Same-cell note/sample starts; out-of-range offsets are skipped safely. |
| `Axy` | Volume slide | Implemented, parity-watch | `A00` reuses prior same-channel Axy-style volume-slide memory | Yes | Yes | Tick-level gain updates after tick 0; missing memory remains no-op/deferred. |
| `Bxx` | Position jump | Implemented, parity-watch | Not applicable | Yes | Yes | Focused traversal planning; broader tracker quirks remain deferred. |
| `Cxx` | Set volume | Implemented | Not applicable | Yes | Yes | Row-level channel-volume state update. |
| `Dxx` | Pattern break | Implemented, parity-watch | Not applicable | Yes | Yes | XM-style BCD row target with safe diagnostics; broader traversal quirks remain tracked. |
| `E0x` | Filter toggle | Deferred | Deferred | No | No | Limited usefulness for v1 compatibility. |
| `E1x` | Fine portamento up | Implemented, parity-watch | `E10` deferred/no-op | Yes | Yes | One tick-0 Linear adjustment of `4 * x` period units (including same-cell note triggers). |
| `E2x` | Fine portamento down | Implemented, parity-watch | `E20` deferred/no-op | Yes | Yes | One tick-0 Linear adjustment of `4 * x` period units (including same-cell note triggers). |
| `E3x` | Glissando control | Deferred | Deferred | No | No | No current C mixer adapter behavior. |
| `E4x` | Vibrato control | Implemented | Channel-local control stored for later vibrato | Yes | Yes | All 16 values: low two bits select sine/ramp/square/square; bit 2 suppresses phase reset; bit 3 is ignored. |
| `E5x` | Set finetune | Implemented, parity-watch | No-note memory deferred | Yes | Yes | Same-cell note triggers only; non-linear table behavior deferred. |
| `E6x` | Pattern loop | Implemented, parity-watch | Loop state supported for focused traversal | Yes | Yes | Missing loop starts are diagnosed without inventing playback; broader traversal quirks remain tracked. |
| `E7x` | Tremolo control | Implemented, parity-watch | Channel-local control stored for later tremolo | Yes | Yes | All nibble values follow FT2: low two bits select sine/ramp/square/square, bit 2 suppresses phase reset, bit 3 is ignored. Ramp reproduces the vibrato-phase sign quirk without changing vibrato playback. |
| `E8x` | Set panning | Deferred | Deferred | No | No | `8xx` is the currently supported panning command. |
| `E9x` | Retrigger note | Implemented, parity-watch | `E90` deferred | Yes | Yes | Retrigger volume-change variants remain deferred. |
| `EAx` | Fine volume slide up | Implemented, parity-watch | `EA0` deferred/no-op | Yes | Yes | Row-level channel-volume adjustment. |
| `EBx` | Fine volume slide down | Implemented, parity-watch | `EB0` deferred/no-op | Yes | Yes | Row-level channel-volume adjustment. |
| `ECx` | Note cut | Implemented | Not applicable | Yes | Yes | Hard cut at requested row tick. |
| `EDx` | Note delay | Implemented | Not applicable | Yes | Yes | Delays same-cell normal note triggers; no-note residuals are diagnostic. |
| `EEx` | Pattern delay | Deferred | Deferred | No | No | Recognized as a traversal/timing hazard. |
| `EFx` | Invert loop / funk repeat | Deferred | Deferred | No | No | Not a current playback target. |
| `Fxx` | Speed / BPM | Implemented | Not applicable | Yes | Yes | `F01...F1F` sets the command row's tick count; `F20...FFF` sets its tick duration starting at tick 0. Channels are processed left to right; the last speed and last BPM commands each win. `F00` remains an ignored no-op. |
| `Gxx` | Global volume | Implemented | Not applicable | Yes | Yes | Clamped `0...64` global-volume state. |
| `Hxy` | Global volume slide | Implemented, parity-watch | `H00` no-op | Yes | Yes | Both-nibble parameters use diagnosed up-nibble precedence. |
| `Kxx` | Key off | Implemented | Not applicable | Yes | Yes | Schedules the existing key-off/release path; `K00` releases at row start. |
| `Lxx` | Set envelope position | Implemented, parity-watch | Not applicable | Yes | Yes | Effect-column `Lxx` sets the active mapped volume-envelope position; no-active and no-envelope cases are diagnosed no-ops. Panning-envelope behavior remains deferred. |
| `Pxy` | Panning slide | Deferred | Deferred | No | No | Legacy handler support exists, but the default C mixer adapter path has no implementation yet. |
| `Rxy` | Multi retrigger | Implemented, parity-watch | `R00` deferred/no-op | Yes | Yes | Reuses the retrigger scheduler for active voices and applies a common-XM volume-change table with channel volume clamped to `0...64`. |
| `Txy` | Tremor | Deferred | Deferred | No | No | No current C mixer adapter behavior. |
| `X1x` / `X2x` | Extra fine portamento | Implemented, parity-watch | `X10`/`X20` deferred/no-op | Yes | Yes | Linear-frequency row-level adjustment only; other `X` subcommands remain deferred. |
| `X5x`, `X6x`, `X9x`, `XAx`, `Yxy`, `Zxx` | OpenMPT / ModPlug compatibility commands | Not targeted for v1 | Not targeted | No | No | Extension and hack families stay out of v1 unless a later compatibility target justifies them. |
| `Vxx`, `Wxx` | High-byte unknowns in current diagnostics | Classification-only | Not applicable | No | No | Kept visible as unsupported diagnostics; no playback behavior is inferred. |

`Rxy` volume mode handling currently follows common XM behavior: modes `1...5`
subtract `1, 2, 4, 8, 16`, modes `6...7` scale by `2/3` and `1/2`, mode `8`
is no change, modes `9...D` add `1, 2, 4, 8, 16`, and modes `E...F` scale by
`3/2` and `2`. The result is clamped to the XM channel-volume range `0...64`.

## Volume Column Commands

| Command family | Status | Runtime support | Offline support | Notes |
| --- | --- | --- | --- | --- |
| Set volume (`10...50`) | Implemented | Yes | Yes | Sets channel volume for triggers and active voices. |
| Volume slide down/up (`60...7F`) | Implemented, parity-watch | Yes | Yes | Row-level approximation in the adapter path. |
| Fine volume slide down/up (`80...9F`) | Implemented, parity-watch | Yes | Yes | Row-level approximation in the adapter path. |
| Vibrato speed (`A0...AF`) | Deferred | No | No | Decoded for diagnostics only. |
| Vibrato depth (`B0...BF`) | Deferred | No | No | Decoded for diagnostics only. |
| Set panning (`C0...CF`) | Implemented | Yes | Yes | Maps XM panning to the C mixer pan range. |
| Panning slide left/right (`D0...EF`) | Implemented, parity-watch | Yes | Yes | Row-level approximation in the adapter path. |
| Tone portamento (`F0...FF`) | Implemented, parity-watch | Yes | Yes | Linear `Fx` uses `3x0`-equivalent speed (`64 * x` period units per tick after tick 0); `F0` retains existing speed memory and no-retrigger target handling. Amiga-table volume-column tone portamento remains deferred. |
| Unsupported / unknown volume-column bytes | Classification-only | No | No | Kept visible in diagnostics when encountered. |

## Frequency Table Support

- Linear frequency table: primary v1 target and currently supported by the
  runtime/offline C mixer adapter path.
- Amiga frequency table: narrow foundation implemented, parity-watch, for note
  period/frequency/sample-step calculation using the FT2-compatible quantized
  period lookup, sample finetune metadata, `2xx` portamento down, and
  effect-column `3xx` tone portamento in the runtime/offline C mixer adapter
  path.
- Broader Amiga-table pitch effects remain separate parity work; `1xx`,
  `E1x`/`E2x`, `X1x`/`X2x`, same-cell `E5x`, `5xy`, and volume-column
  tone portamento are not broadened by the Amiga foundation.
- Private Amiga-table coverage is tracked locally; do not publish private
  filenames, local paths, or corpus details.

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

Existing note-only sample retrigger limitations, Linear range-edge behavior,
and `6xy` row-level volume-slide timing remain parity boundaries. `600`
volume-slide memory is still deferred. Amiga `4xy`/`6xy` pitch execution is
still guarded: its later implementation must map the reference delta to
VTX's 4x period representation and explicitly handle FT2 unsigned wrapping
and period zero, rather than blindly reuse the existing Amiga clamp.

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

## Explicitly Deferred / Not V1

- `E0x` filter toggle.
- Broader Amiga frequency-table pitch parity beyond the narrow note,
  `2xx` down, and effect-column `3xx` foundation.
- `E3x`, `E8x`, `EEx`, `EFx`, `Pxy`, and `Txy` in the default
  C mixer adapter path.
- `X` subcommands other than `X1x` and `X2x`.
- OpenMPT / ModPlug hacks and non-v1 extensions unless explicitly promoted by
  a future compatibility decision.

## Maintenance Note

Update this page whenever an XM effect PR lands. Corpus coverage reports are
private/local evidence; public docs and PR summaries should use anonymized
labels only and should never include private module filenames or local paths.

The synthetic XM reference-fixture plan supplies the incremental public-fixture
contract for effect-family parity work; reference renders and generated metrics
remain local unless a separately reviewed change explicitly approves them.
