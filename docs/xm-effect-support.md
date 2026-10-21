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
Legacy diagnostic reason strings are historical VTX outcomes, not FT2 semantic
authority. E90 now reports applied, no-route or NOTE_OFF-suppressed dispatch.

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

G23 nonzero instrument-only `ED1...EDF` is a different dispatch: valid carried
instrument selection occurs at row entry; tick x resolves the retained note
through that instrument's exact map and starts one new cursor-zero source.
Header/default and instrument resets wait until that tick. Empty routes retire
without a new voice; no retained note creates none. Out-of-row delays keep the
row-entry owner but perform no delayed reset/start. Instrument-only ED0 retains
ordinary immediate cached-default/reset behavior without a source restart.

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
Supported same-cell note+instrument forms additionally reset instrument semantics
on the retained source: cached volume/pan, enabled envelope segments/clocks,
key-on and full fadeout precede explicit writers. The retained sounding header owns defaults
and active sample metadata; the row instrument may independently become carried
and supply target pitch. Song volume consumes the header once, without another
sample multiplier. This covers 3xx/5xy/volume Fx in both modes. G28 Amiga
consumers reuse the existing ownership paths. Note-only/empty continuation does
not acquire this reset.
With no retained source/header owner, supported same-cell tone admission instead
restores cold volume 0/pan 128 and key/fadeout, carries instrument/neutral target/
speed, and starts no source. Explicit writers and shared 5xy slides still execute.
Later ordinary note-only starts the exact mapped source while carrying tracker
state; header-cache refresh is separate. Declared empty headers keep their own
defaults/clocks. `cold-tone-portamento-initialization.xm` pins this distinction.
K00 suppresses a normal note-only trigger; ED0 carries ordinary state, valid
nonzero EDx resets at its delayed tick, and out-of-row EDx does not trigger.
E9x retains repeat resets; Rxy uses its persistent counter and sample restarts
that preserve instrument semantic state (G21). VTX's immediate new-source onset versus
FT2's 5 ms onset ramp remains separate. See
[volume ownership](design/xm-volume-ownership.md#note-only-routing-and-state-carry).

## Effect Column Commands

Support applies to both runtime and offline paths. Closure is bounded by the
notes and matrix IDs, including the cross-cutting obligations below.

| Command | Name | Support | FT2 closure | FT2 memory | VTX pitch mode | Current behavior / remaining boundary |
| --- | --- | --- | --- | --- | --- | --- |
| `0xy` | Arpeggio | Implemented | Partial; G25/G26 in-range contracts closed | None; `000` inert | Both | Ordinary tick zero is base; pure Bx held-output entry follows G32A-0R below. Later ticks select `[base,x,y][(effectiveSpeed - tick) % 3]` using effective same-row Fxx speed. Source/cursor and arithmetic are preserved; G30A supplies quantization/step conversion. G30B inverse projection gives B-7 `037` periods 1540/1540. Amiga phases resolve through the existing quantized note/finetune lookup, with relative-note metadata. G30B owns bounded Amiga extremes; step conversion is G30A. |
| `1xx` | Portamento up | Implemented | Partial; G27 in-range Amiga contract closed | Own; `100` supported | Both | Linear `4 * xx`, Amiga `16 * xx` subtraction per nonzero tick through the shared native-word arithmetic and G30A conversion. Corrected generic memory admission requires an executed nonzero tick; speed 1 neither seeds nor replaces history. Combined G30 closes the native minimum 1 (Amiga VTX 4), including the owned cold-100 signed-negative clamp without memory provenance. |
| `2xx` | Portamento down | Implemented | Partial | Own; `200` supported | Both | Linear `4 * xx`, Amiga `16 * xx` in VTX's 4x representation. Same memory admission rule as `1xx`; speed 1 neither seeds nor replaces it. G30B closes the distinct signed-threshold boundary below. |
| `3xx` | Tone portamento | Implemented | Partial | Shared with volume-column `Fx`; `300` target/speed supported | Both | No retrigger, target-clamped nonzero ticks and Amiga quantized targets are established. Targets, speed and period direction are independent channel state. Explicit 3xx/5xy/Fx target admission latches direction; equality installs none. Ordinary source/pitch changes retain it; 300/500/F0 consumes it. An executed clamp leaves higher-period direction, including a crossed-target clamp at implicit zero speed without memory provenance. G30B closes bounded extremes below; glissando remains separate. |
| `4xy` | Vibrato | Implemented | Partial | Shared with `6xy` and volume-column vibrato; independent speed/depth nibbles | Both | Integer modulation, initially-zero memory, `400`/zero-nibble replay, Amiga wrap/zero-step hold and G10 shared volume-column dispatch are closed. Full audible interactions remain G39. |
| `5xy` | Tone portamento + volume slide | Implemented | Partial; G28 Amiga composition closed | Shared `3xx` target/speed and `Axy`/`5xy`/`6xy` slide byte | Both | Amiga reuses 3xx progression plus the existing shared volume writer, including independent cold 500 execution and whole-byte replay. Same-cell ownership selects retained/empty defaults or cold initialization before explicit writers. Fxx/speed-1, exact routes and source/cursor carry are pinned. Combined G30 closes bounded extremes below; broader parent limitations remain separate. |
| `6xy` | Vibrato + volume slide | Implemented | Partial | Shared `4xy` vibrato and `Axy`/`5xy`/`6xy` slide byte; `600` supported | Both | Vibrato then slide on ticks `1..<speed`; no tick-zero/speed-1 slide. Unseeded `600` restores base to output with zero amount and publishes against the held source target even when local values are unchanged. Timing/memory/local publication are closed; G39 remains. |
| `7xy` | Tremolo | Implemented | Partial | Own; independent initially-zero speed/depth nibbles | Not applicable | `700`, `70y`, `7x0`, integer nonzero-tick output modulation and empty-row phase/output carry are closed. Onset, ramps and trigger/cut interactions remain G39; G01 removes duplicate header scaling. |
| `8xx` | Set panning | Implemented | Known difference | None | Not applicable | Exact tick-zero panning state exists. Final stereo pan law differs (G40); this is separate from E8 and pan envelopes. |
| `9xx` | Sample offset | Implemented | Partial | Own; `900` supported | Not applicable | Same-cell source offset/memory exists; end/loop/offset boundaries remain G41. Safely skipping an out-of-range offset does not prove FT2 parity. |
| `Axy` | Volume slide | Implemented | Closed G14 cold restoration and seeded replay | Shared with `5xy`/`6xy`; cold `A00` executes implicit zero without seeding | Not applicable | Nonzero-tick slides and cold base-to-output restoration use causal local publication. Speed 1 is inert; tremolo/E7 state and real seeded provenance are preserved. Broader output interactions remain separate. |
| `Bxx` | Position jump | Implemented | Needs characterization | None | Not applicable | Focused traversal exists; conflicting B/D/E6 precedence, restart and bounds remain G38. |
| `Cxx` | Set volume | Implemented | Closed | None | Not applicable | Bounded tick-zero channel-volume state/clamp is supported; audible header/gain/ramp obligations remain separate. |
| `Dxx` | Pattern break | Implemented | Needs characterization | None | Not applicable | BCD target/traversal exists; broader B/D/E6 precedence remains G38. |
| `E0x` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch. VTX's no-op needs no audible XM filter; MOD hardware-filter semantics are a separate target. |
| `E1x` | Fine portamento up | Implemented | Closed G17 Linear / G29 in-range Amiga | Own per-channel up amount; seeded `E10` supported | Both | Tick-zero Linear `4 * x` / Amiga `16 * x`; same-cell folding and independent replay. Cold forms restore meaningful held pitch without provenance; ineligible publications are suppressed. G30B supplies native-word clamps below. |
| `E2x` | Fine portamento down | Implemented | Closed G17 Linear / G29 in-range Amiga | Own per-channel down amount; seeded `E20` supported | Both | Same bounded timing/restoration as E1 with independent downward memory and positive deltas. Ordinary source changes preserve tone target/direction/speed. Combined G30 closes bounded native-word extremes below. |
| `E3x` | Glissando control | Deferred | Open | Special; persistent enable/disable control | Not applicable | Genuine FT2 v1 target G36, separate from inert E0/E8/EF. Linear/Amiga tone-output quantization still needs a focused oracle. |
| `E4x` | Vibrato control | Implemented | Closed | Special; persistent control for `4xy`/`6xy` | Not applicable | All 16 controls: sine/ramp/square/square; bit 2 suppresses phase reset; bit 3 ignored. Bounded control contract only. |
| `E5x` | Set finetune | Implemented | Partial; G29 in-range Amiga trigger closed | None; no-note form inert | Both | Ordinary exact mapped note trigger uses `16 * nibble - 128` instead of header finetune, preserving relative note, defaults/reset and latent tone target/direction/speed. No-note E5 does not retune current/later sources. Amiga reports inert; the Linear legacy no-note diagnostic is unchanged. G30B supplies ordinary admission below. |
| `E6x` | Pattern loop | Implemented | Partial | Special; channel loop start/counter | Not applicable | Explicit E60 start exists. Implicit initial loop start missing (G37); B/D/E6 ordering remains G38. |
| `E7x` | Tremolo control | Implemented | Closed | Special; persistent control independent of E4 | Not applicable | All nibble aliases and phase-reset suppression are supported; ramp retains FT2's vibrato-phase sign quirk. Full `7xy` audio remains G39. |
| `E8x` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch; current no-op matches. OpenMPT's audible panning alias is outside FT2 v1; use supported `8xx`. |
| `E9x` | Retrigger note | Implemented | Partial | Special; no ordinary interval replay | Not applicable | G19 `E90` row-entry routing/carry/reset is closed. E91...E9F retain existing nonzero-tick resets and offsets. Onset/ramp parity and `Rxy` are separate. |
| `EAx` | Fine volume slide up | Implemented | Closed G16 directional replay and cold publication | Own per-channel fine-up amount | Not applicable | Tick-zero +x, clamped to 64; seeded EA0 replays up memory. Cold EA0 restores base to output and publishes against the held target without seeding memory. Independent of EB/A/5/6 and volume-column 8x/9x. |
| `EBx` | Fine volume slide down | Implemented | Closed G16 directional replay and cold publication | Own per-channel fine-down amount | Not applicable | Tick-zero -x, clamped to 0; seeded EB0 replays down memory. Cold EB0 restores base to output and publishes against the held target without seeding memory. Independent of EA/A/5/6 and volume-column 8x/9x. |
| `ECx` | Note cut | Implemented | Known difference | None | Not applicable | VTX hard-retires the source. FT2 zeros base/output with a quick ramp and retains the cursor/source for recovery (G04). Internal hard stop is separate. |
| `EDx` | Note delay | Implemented | Partial | None | Not applicable | Ordinary delayed notes remain supported. G23 retained-note instrument-only ED1...EDF dispatch is closed: row-entry owner, delayed exact route/default/reset and one cursor-zero generation. Instrument-only ED0 resets immediately without a restart; out-of-row retains owner only. G24 bounded release/default precedence is closed below. |
| `EEx` | Pattern delay | Deferred | Open | None | Not applicable | Standard FT2/XM v1 traversal/timing target G35. Row-duration/tick replay needs its own contract, separate from unrelated E effects. |
| `EFx` | Inert in FT2 XM | FT2-inert | Closed | None | Not applicable | Dummy dispatch; no destructive MOD invert-loop/funk behavior. OpenMPT XM macro hacks are outside FT2 v1. |
| `F01...F1F` / `F20...FFF` | Speed / BPM | Implemented | Closed | None | Not applicable | Nonzero command-row tick-zero timing is closed. `F20` is valid XM BPM 32. Last speed and last BPM each win in left-to-right channel order. |
| `F00` | Zero speed boundary | Implemented | Known difference | None | Not applicable | VTX ignores it; pinned FT2 writes zero speed/tick state. Resulting traversal needs characterization and explicit closure rationale; nonzero Fxx stays closed. |
| `Gxx` | Global volume | Implemented | Closed channel-turn birth/held-target delivery | None | Not applicable | One clamped `0...64` global; fresh notes observe their channel turn, including same-cell Gxx. Later writers do not backfill earlier targets. Real later publications refresh from held gain even when calculated gain was unchanged; whole/window/runtime share source-generation order. Generic ramps, onset and broader mix parity remain separate. |
| `Hxy` / `H00` | Global volume slide | Implemented | Closed G12 timing / G13 memory; retained cold artifact difference | Independent channel-local whole byte; cold `H00` is a true no-op | Not applicable | Nonzero ticks `1..<effectiveSpeed`, upper nibble wins, clamp `0...64`. F01 neither seeds nor replaces memory. Seeded H00 uses G12 ascending channel turns and held targets against one song-global volume; later writers do not revise earlier targets. FT2's cold zero-memory target-refresh artifact is intentionally not emulated. |
| `Kxx` | Key off | Implemented | Partial | None | Not applicable | G24 bounded precedence closed: raw K00 suppresses ordinary starts and owns note97+K00 once; release → cached restore → column/Cxx/8xx writers. Nonzero Kxx uses low five bits after column writers; K20 has no invocation, out-of-row omits release. Cold key/fadeout carry and once-per-tick finalization preserve source/cache ownership. Both-rate canonical-host delivery and startup attribution pass; the overall product ≤1 s startup target remains outstanding. |
| `Lxx` | Set envelope position | Implemented | Partial | None | Not applicable | Existing volume positioning is preserved. Bounded G07 pan positioning is closed under the sounding instrument's raw volume-sustain flag, including disabled volume envelopes and silent-channel clocks. Volume loop/end positioning, cold before-first initialization, pan arithmetic/sustain and G40 remain open; bounded volume Q8 follows G31. |
| `Pxy` | Panning slide | Deferred | Open | Own byte; pinned `P00` replays it | Not applicable | Real FT2/XM v1 target G33. Legacy handler support is not C-adapter support; remaining timing/writer/pan-envelope interactions need characterization. |
| `Rxy` | Multi retrigger | Implemented | Closed G20 memory / G21 counter and carry / G22 integer volume modes | Independent zero-initialized interval/mode bytes and persistent counter | Not applicable | Memory resolves before invocation gating. Eligible ticks increment the counter; reaching the interval resets it and restarts the exact retained route at cursor zero, carrying semantic state. Interval zero executes every eligible tick. Volume modes use exact pinned FT2 integer arithmetic over 0...64. Only fully uninitialized volume bookkeeping is excluded as C; retirement reconstruction debt remains separate. |
| `Txy` | Tremor | Deferred | Open | Own byte; pinned `T00` replays it | Not applicable | Real FT2/XM v1 target G34. Counter/phase, cold state, trigger carry and volume-writer interactions still need characterization. |
| `X1x` / `X2x` | Extra fine portamento | Implemented | Closed G18 Linear / G29 in-range Amiga | Own independent per-channel up/down amount/origin | Both | Tick-zero Linear `x` / Amiga `4 * x`; seeded X10/X20 replay their direction independently of E1/E2. Cold restoration, deduplication and source eligibility are preserved. Fine:extra-fine granularity is 4:1; combined G30 closes bounded native-word extremes below. |
| `X5x`, `X6x`, `X9x`, `XAx`, `Yxy`, `Zxx` | OpenMPT / ModPlug commands | Extension | Outside v1 | Not applicable | Not applicable | No runtime/offline support. Extension/hack families require a separately accepted compatibility target. |
| `Vxx`, `Wxx` | High-byte diagnostic unknowns | Classification-only | Outside v1 | None in pinned FT2 | Not applicable | Unused/dummy in pinned FT2 dispatch. Diagnostic occurrence does not establish an FT2 effect or identify an extension. |

`Rxy` volume modes use exact pinned FT2 integer arithmetic over `0...64`.
Modes `0` and `8` preserve volume; `1...5` subtract `1, 2, 4, 8, 16` and
`9...D` add the same constants. Mode `6` sums `v/2 + v/8 + v/16`, truncating
each division independently; mode `7` is `v/2`, mode `E` is `(3*v)/2`, and
mode `F` is `2*v`. Clamp the result to `0...64`. Mode 6 therefore gives
32→22→14→8→5→2→1→0, rather than a common-XM two-thirds approximation.
All 1,040 mode/input pairs and repeated scaling sequences are independently
pinned in `RxyVolumeArithmeticTests`. The pure helper changes numeric results
only; G20 memory, G21 execution/source carry and the narrow C exclusion remain
unchanged.

## Zero forms and reference boundaries

Pinned FT2 [fine-pitch handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L620-L648),
[fine-volume handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L685-L713)
and [extra-fine handlers](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1182-L1219)
establish independent up/down memories within each family. E10/E20, EA0/EB0
and X10/X20 continue their respective directional amounts at tick zero.
VTX implements G16 EA0/EB0, G17 Linear E10/E20 and G18 Linear X10/X20
directional replay. Fine-volume memory is separate
from A/5/6 and volume-column 8x/9x; extra-fine memory is separate from fine/regular
pitch. G29 reuses those same memories for the bounded Amiga paths below;
Linear nonzero units and restoration stay unchanged.

E1x/E2x retain separate channel-local amount/origin memories, independent of
1/2/3, X1/X2 and shared vibrato state. Nonzero and seeded zero commands execute
once at tick zero, with G30B native-word arithmetic and same-cell trigger
folding. Cold E10/E20 perform zero arithmetic on meaningful canonical real pitch
and restore held output from it, publishing only when the current source is
eligible and its held step differs. A later fine publication subsumes a preceding
vibrato exit at the same frame; converged cold commands keep the existing exit.
Cold forms create no memory provenance and preserve vibrato speed/depth/phase,
E4 control and later continuation. Completed/empty
routes may restore retained semantic pitch but cannot resurrect a C voice;
uninitialized pitch remains absent. Pinned FT2's source-less cold-E10 0→1 clamp
mutation and redundant refresh flags are intentionally not emulated. This is a
bounded Linear contract; G29 extends its existing stores and scheduler to Amiga.
Amiga fine deltas are ±16 times the nibble in VTX units; target/direction/speed
remain independent channel state. G30B supplies the native-word extreme policy below.

X1x/X2x have separate channel-local directional extra-fine memories. Seeded
X10/X20 replay their own amount; cold forms restore held output from meaningful
canonical realPeriod at tick zero with zero arithmetic and no memory provenance.
Only a differing held step on an eligible generation receives a C write. Empty
and completed routes may restore semantic pitch without fabricating a source;
uninitialized pitch stays absent. FT2's cold-X10 0→1 clamp and redundant refreshes
are intentionally omitted. Vibrato speed/depth/phase, E4 controls and later
column-vibrato continuation survive. Same-cell forms fold into one trigger;
existing nonzero units and period bounds are protected. G29 adds Amiga deltas
of ±4 times the resolved nibble, preserving the 4:1 fine/extra-fine ratio and
latent tone state without another memory family.

EAx and EBx use independent directional per-channel memories. Seeded EA0/EB0
replay their own amount once at tick zero. Cold EA0/EB0 execute implicit zero
fine-volume operations, assign local output from base and declare local
publication intent without creating memory provenance. A differing composed
target refreshes the active generation; equal held targets deduplicate. This is
A seeded memory plus B bounded cold compatibility behavior. Cold H00 remains
intentionally inert; cold A00/500/600 retain their nonzero-tick local writes.
`FineVolumeMemoryTests` and `fine-volume-directional-memory.xm` cover both rates,
clamps, source lifetimes, independent families, speed/Fxx and window carry.
Envelope/fadeout composition and existing ramp policy remain unchanged.

The pinned [E dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L733-L750)
and [nonzero-tick dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L2209-L2227)
leave E0/E8/EF inert. The [note dispatch](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1394-L1460)
handles E90 at tick zero; the nonzero E9 handler does not replay an interval.
G19 treats this as intended FT2/XM behavior (A). Empty-note E90 uses the retained
note; a row note replaces it. The carried or explicit instrument's exact keymap
selects the source, starting at cursor zero without consuming 9xx memory.
Instrumentless E90 carries base/output volume, pan, envelope clocks/segments,
release/fadeout and modulation/effect memory. An explicit instrument resets once
before same-cell volume/pan overrides. NOTE_OFF releases without a source start;
cold and unavailable routes invent neither a note nor a fallback sample.
Completed sources can restart from retained identity. E93 followed by E90
produces one row-entry start, with no tick-3 replay. Existing nonzero E9 offsets
and resets, Rxy behavior and mixer ramps remain protected. The public
`e90-row-entry-retrigger.xm` and both-rate routing/runtime/window tests pin this
bounded contract; complete FT2 PCM parity remains outside it.

G20 implements Rxy memory resolution (A intended behavior), independently of E9/E90.
Each channel owns zero-initialized speed and mode bytes; a nonzero nibble updates
only its byte, and zero preserves/reuses it. Nonzero-origin provenance is
metadata, never an availability gate. Cold R90→R03→R00 resolves 9/0→9/3→9/3;
cold R03→R90→R00 resolves 0/3→9/3→9/3, including without a source. Note,
instrument, completion, release, order and loop transitions retain the bytes.
Same-cell routing or counter-dispatch gates cannot suppress memory mutation.
`RxyNibbleMemoryTests` and runtime controls close G20 memory at both rates:
positive-interval replay matches explicit-equivalent event plans and PCM in
whole/window offline and runtime paths. Baseline comparison proves the existing
runtime/offline retrigger-retirement difference unchanged: runtime ramps the
old source over 32 frames while offline cuts it immediately. That separate
retirement debt does not close with G20; mixer and retirement code are unchanged.

G21 closes the persistent R counter, tick-zero dispatch and semantic carry.
Every eligible invocation increments the channel counter, then executes and
resets it when it reaches the resolved interval. Zero executes every eligible
invocation, including tick zero. R93 at speed 6 fires at ticks 2,5; cross-row
carry can fire at tick 0 or 1. Same-row Fxx governs the invocation count.

Tick zero is eligible with no volume column, set-volume 10, fine-volume 8x/9x
when the resulting base is zero, A0 and C0. Other column values gate it;
nonzero ticks invoke R after their column writer. Set-volume and Cx are
reasserted after R arithmetic. G20 nibble resolution always runs.

Note+instrument and instrument-only trigger boundaries, valid delayed triggers
and dispatched nonzero E9 reset the counter, including without a source. Note-only starts, E90, blanks, release,
completion and order/E6 transitions preserve it. None erase nibble memory.
Ordinary same-cell semantics precede R; simultaneous trigger requests coalesce
into one mixer source. R restarts the retained note through the selected
instrument's exact map at cursor zero, preserving envelope clocks, key/release,
fadeout and effect memory. Completed sources can restart; unavailable routes
never acquire a fallback source. Initialized source-less channels execute
semantic volume changes that survive a later note-only trigger.

The fully uninitialized case, with no selected/carried instrument or note, is
an explicitly excluded C bookkeeping artifact: the first note+instrument resets
it and matches the blank-control PCM. This exclusion does not cover initialized
source-less, empty, completed or released channels. Public
`rxy-counter-timing-carry.xm`, focused tests and both-rate runtime/window controls
cover G21. Replay matches explicit-equivalent commands within each render path;
PCM differences between runtime and offline stay inside the unchanged 32-frame
retirement windows. G22 closes integer volume arithmetic independently of that
unchanged retirement policy.

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
pin existing units, replay, modulation and zero-command contracts; E90 row-entry
tests additionally pin exact source routing, carry, reset and release metadata.
The matrix retains the distinguishing reference controls and remaining gaps.

## Volume Column Commands

The same dimensions apply. Volume-column slide amounts do not acquire
effect-column whole-command memory just because their names resemble it.

| Command family | Support | FT2 closure | FT2 memory | VTX pitch mode | Current behavior / remaining boundary |
| --- | --- | --- | --- | --- | --- |
| Set volume (`10...50`) | Implemented | Closed | None | Not applicable | Bounded channel-volume write exists; cross-cutting gain/output obligations remain. |
| Volume slide down/up (`60...7F`) | Implemented | Closed | None | Not applicable | G08: clamp base/output on ticks `1..<effective row speed`; tick zero and speed 1 preserve volume. Zero amounts restore output from base without parameter replay. Same-tick effect-column writers follow the column write; existing gain/output boundaries remain separate. |
| Fine volume slide down/up (`80...9F`) | Implemented | Partial | None | Not applicable | Tick-zero scheduling is closed; zero amount still restores base to output. Shared gain/output boundaries remain. |
| Vibrato speed (`A0...AF`) | Implemented | Closed | Shared vibrato speed with `4xy`/`6xy` | Both | G10: nonzero Ax writes at tick zero, including speed 1; A0 preserves speed. Ax alone neither executes vibrato nor advances phase. |
| Vibrato depth (`B0...BF`) | Implemented | Closed | Shared vibrato depth with `4xy`/`6xy` | Both | G10: Bx writes nonzero depth and executes on each nonzero tick; B0 preserves depth and executes. Speed 1 has no Bx write or execution. Bx precedes same-tick 4xy/6xy writer/execution. |
| Set panning (`C0...CF`) | Implemented | Closed | None | Not applicable | G11: tick-zero stored pan is `16 * nibble`, C8 = 128 and CF = 240. Header/Cx/8xx precedence, silent carry and G09/G06/G07 remain intact; final stereo conversion/law is separately G40. |
| Panning slide left/right (`D0...EF`) | Implemented | Closed | None; D0/E0 are special zero cases | Not applicable | G09: ticks `1..<effective row speed`, clamped stored pan; D0 forces zero, E0 preserves it. Speed 1 has no slide. Header/Cx/8xx tick-zero order and G06/G07 remain intact; G11/G33/G40 stay separate. |
| Tone portamento (`F0...FF`) | Implemented | Partial; G28 Amiga consumer closed | Shared `3xx` speed; `F0` retains it | Both | Fx stores `nibble << 4` in shared raw speed, including at speed 1; existing mode conversion gives Linear `64 * nibble` / Amiga `256 * nibble` VTX period units per nonzero tick. Retained/empty/cold ownership, F0 replay and no-retrigger continuation are pinned. Combined G30 closes bounded extremes below; broader parent limitations remain separate. |
| Unsupported / unknown bytes | Classification-only | Outside v1 | Not applicable | Not applicable | Diagnostic visibility grants no playback support. |

## Frequency Table Support

- Linear frequency table: primary v1 target and currently supported by the
  runtime/offline C mixer adapter path.
- Amiga frequency table: narrow implemented foundation for note
  period/frequency/sample-step calculation using the FT2-compatible quantized
  period lookup, sample finetune metadata, G26 `0xy`, G27 `1xx`, `2xx`,
  `3xx`, `4xy`, the vibrato half of `6xy`, and G28 `5xy`/volume-column Fx
  in the runtime/offline C mixer adapter path. Amiga 5xy composes existing
  3xx progression with the shared A/5/6 writer; Fx uses that same tone authority.
- G29 Amiga `E1x`/`E2x` and `X1x`/`X2x` share existing directional memory
  and tick-zero scheduling. Same-cell `E5x` uses the ordinary mapped trigger
  and Amiga lookup; no-note E5 stays inert. Pitch writers preserve latent tone
  target/direction/speed. G30B closes the bounded range/extremes below; broader
  interactions remain separate, without universal Amiga parity.
- Private Amiga-table coverage is tracked locally; do not publish private
  filenames, local paths, or corpus details.

### G30A bounded pitch conversion

For already-valid effective notes 1...119, Linear periods are
`7680 - 64*(effectiveNote-1) - 4*floor(finetune/8)`. Arithmetic right shift by
three supplies the signed floor. Same-cell E5 and tone targets use the same
helper; G30B separately decides out-of-domain admission and effect state.

Both pitch modes publish a shared project-authored Q16 sample step divided by
65536 into the existing Double event payload. Linear conversion rounds Q24
source/output and octave-fraction coefficients, truncates their UInt64 product,
and applies the reference UInt32 delta and masked shift domain. Amiga rounds
`1712 * 65536 * sourceHz / outputHz`, then divides by the native period using
integer truncation. VTX's Amiga period is divided by four at this boundary.
The output conversion truncates/masks its native period word without changing
canonical period, target, direction, memory or scheduling. There is no new table,
pass, callback work or C DSP change.

The public bounded-pitch fixture pair, exhaustive UInt16 reference fingerprints,
source rates 4000/8363/16726, and 0.25/1/5-second cursor controls cover both
44.1/48 kHz outputs. Bounded sustained drift is closed. Remaining waveform
residuals are the existing onset and interpolation fraction/PCM rounding;
retirement remains 32 frames. Stored sample-import tuning and PCM are unchanged;
its existing derived playback-rate/error diagnostics now observe quantization.

### G30B extreme pitch state and independent instrument reset

Raw note + instrument resolves the exact keymap before transposition. UInt8
addition of raw note and signed relative note gives three ordinary outcomes:
1...119 starts the selected source with lookup pitch; 0 starts it with retained
current/base pitch; 120...255 refuses the source. This authority covers explicit
and carried instruments, same-cell E5 and actual ED dispatch. Effective zero owns
new defaults/reset without replacing latent tone target/direction/speed. A cold
zero-period source is held through an existing explicit step-zero event after
creation and before rendering; generic initial-step sanitization is unchanged.

Refusal preserves sounding source/header, generation, cursor/fraction, current
pitch, cached volume/pan, cached finetune and latent tone state. Control-instrument
selection is independent. An explicit instrument restores the old sounding
cache, key-on, integer fadeout and enabled volume/pan clocks under the selected
control instrument's curves/rate; existing E4/E7 phase-reset gates still apply.
Later explicit volume/pan writers win. Immediate note-only refusal does not
reset; delayed note-only refusal resets clocks/key/fadeout at dispatch without
restoring cached defaults. Completed/empty owners gain no live source; a valid
cold explicit instrument can establish semantic ownership. G32 autovibrato is
still a missing parent, without a new automatic-modulation implementation here.

Ordinary Amiga native lookup spans 22...29024 (VTX 88...116096). Effects use
native UInt16 storage, with Linear scale 1 and Amiga VTX scale 4. Upward 1xx/E1/X1
wrap the subtraction, then replace Int16 results below 1 with 1. Downward 2xx/E2/X2
wrap addition, then replace Int16 results at/above 32000 with 31999; negative
signed results continue. Regular/fine native deltas remain four times the
parameter/nibble, extra-fine one. Zero-amount source-less artifacts remain excluded.

Cold Amiga E10/X10 still execute the upward signed minimum on owned current
pitch: reachable VTX 136156 becomes 4 at tick zero with amount zero and absent
memory provenance. Completed/empty owners retain that semantic clamp while
fine-pitch source eligibility suppresses PCM publication. Cold Amiga 100 applies
the same minimum at its first nonzero tick only for the owned signed-negative
state; it does not seed memory. Linear and downward zero-form behavior is unchanged.

Tone target admission uses its own UInt16 lookup-index boundary and unsigned
direction latch. Lower-period execution compares wrapped result/target as Int16;
higher-period execution compares UInt16. A crossed target clamps even at zero
speed, leaving the higher-period latch. The reachable Amiga 2FF→301 control
clamps 156556 to 480 on its first nonzero tick. 3xx/5xy/Fx share this authority;
their memories, writer order and timing remain unchanged.

Arpeggio uses a bounded inverse-period projection over the existing lookup,
independent of ordinary admission. G25/G26 phase order stays unchanged: base
phase is unprojected, X/Y phases project even a zero nibble. B-7 `037` gives
Linear 1540 and Amiga 428 for both raised phases. Amiga vibrato retains its
separate UInt16 wrap, including period/step-zero hold and resume.

The public extreme-pitch fixture pair and reference fingerprints pin these
bounded contracts. G30A remains the unchanged downstream step authority.
G30 is closed for:

- valid Linear nongrid finetune quantization;
- reference-compatible period-to-step conversion;
- mode-independent extreme note admission/refusal/retained-pitch semantics;
- exact Amiga ordinary lookup range;
- reference-compatible UInt16/signed extreme arithmetic;
- extreme tone-portamento target/direction/clamp;
- bounded arpeggio extreme projection;
- preservation of the distinct Amiga vibrato wrap policy.

Combined verification covers both rates, whole/window/runtime-core/canonical-host
delivery, matched reference audio and paired Release guardrails. Remaining
G32/G33/G34/G35–G38/G39/G40/G41 and callback real-time safety stay open.

### Retained-source arpeggio row handoff

G32A-0R preserves canonical pitch separately from held effect output. Pure
volume-column Bx output survives the first `0xy` tick zero; ordinary starts and
effect-column 4xy/6xy exits retain base pitch. Later phases keep G25/G26 ordering.
Leaving nonzero arpeggio restores the canonical G30A-converted step, including
blank/000 rows. A later same-frame arpeggio or fine/extra-fine writer subsumes
that outgoing restoration in the shared delivery list; its original period,
step and frame remain diagnostic evidence. Source generation/cursor and
strict-before history/continuation semantics are preserved. This bounded
correction does not authorize the final-pitch migration or instrument autovibrato.

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

Seeded `Axy`/`5xy` scheduling and memory are unchanged. Cold `A00` is a
compatibility-supported zero-slide execution on ticks `1..<effectiveSpeed`:
base stays unchanged, output is restored from current base, and a causal local
publication refreshes a differing held target. It creates no seeded provenance,
preserves tremolo/E7 state, and works on silent channel semantics without a
fabricated voice. The manuals do not specify the cold boundary; this is a bounded
B compatibility convention, distinct from the excluded cold-H00 refresh artifact.
`cold-a00-output-restoration.xm` and `ColdA00Tests` pin both rates and window carry.
G15 cold Linear `500` executes an implicit zero slide on ticks `1..<speed`
independently of tone target/speed availability: restore output from base and
compare the composed target with the active generation's held target. It restores
63→32 after 748 and refreshes stale held 1→.25 with unchanged base/output 64.
Speed 1 is inert; no memory is created and repeated equal targets deduplicate.
Tone target/speed, no-retrigger routing, tremolo/E7 and envelope clocks are
unchanged. `Cold500Tests` and `cold-500-local-publication.xm` cover both rates.
This is A independent composition plus B cold restoration; redundant reference
period-refresh flags (C) are not required. G28 Amiga 500 reuses this exact
shared writer, including independent execution and absent cold provenance.
Cold `600` retains its existing zero-slide restoration;
that slide half is a real local writer on every nonzero tick. Publication
compares the composed target with the active generation's held target, so
base/output 64 with global 16 refreshes stale held gain 1 to .25 at tick 1.
Equal targets deduplicate and absent shared memory stays absent. `Cold600Tests`
and `cold-600-local-publication.xm` pin this completion independently of G14.

`6xy`/`600` follow FT2's
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
the existing Linear range guard. G30A converts that output period through
shared reference-compatible Q16 step calculation, described above. Modulation
never changes the base. Consecutive `4xy`/`6xy` rows hold output through tick 0; leaving the
family restores the base. The public `vibrato-semantics.xm` fixture and
`VibratoFoundationTests` pin this contract against the
[pinned FT2 replayer](https://github.com/8bitbubsy/ft2-clone/blob/87be42543dac82cf802b5bddad917bda62ace131/src/ft2_replayer.c#L1836-L1866).

Note-only triggers restore the mapped note's pitch at tick zero without
resetting modulation phase. Linear range-edge behavior remains a parity boundary.

Exact empty/unavailable sample routes still dispatch `4xy`/`400` and the
vibrato half of `6xy`/`600`: nonzero nibbles write channel memory and nonzero
ticks advance phase without creating a source or pitch event. Established
speed/depth/control survive routing; explicit instrument selections retain the
normal prior-E4 phase-reset policy, while note-only carries phase. The
`vibrato-empty-route-state.xm` regression pins later playable `400`/`600`
targets in both frequency modes at 44.1/48 kHz. This fixes skipped empty-route
effect execution; Ax/Bx use this same semantic state and source boundary.

G10 volume-column Ax/Bx reuse the existing vibrato handler, waveform, phase,
and frequency-mode conversion. Nonzero Ax writes shared speed at tick zero;
A0 preserves it, and Ax alone holds phase. Bx writes nonzero depth immediately
before each nonzero-tick execution; B0 preserves depth and still executes.
Mixed Bx plus 4xy/6xy retains two ordered executions and two existing pitch
updates at the same frame. A later 400/600 consumes the shared state. Leaving
pure Bx holds its output; the established restoration on leaving effect-column
4xy/6xy remains unchanged. The public `volume-column-vibrato.xm` fixture and
[VolumeColumnVibratoTests](../tests/vtx_render_bounded_xm/VolumeColumnVibratoTests.swift)
pin both modes, rates, silent routes, reset policy and whole/window/runtime carry.

Amiga `4xy` and the vibrato half of `6xy` apply the same signed delta using
`resultFT2 = (baseFT2 + signedDelta) mod 65536`, then
`resultVTX = 4 * resultFT2`. C-4 at finetune 0 is FT2 1712 / VTX 6848.
This operation does not use the separate note/portamento clamp or alter the
unmodulated base. G30A converts the resulting native period through the shared
reference-compatible Q16 calculation; period zero produces an explicit step-zero
update. The existing C mixer holds the active source cursor while rendered-frame time and playback follow advance;
a later nonzero update resumes that same voice. Underflow and upper overflow
wrap, including 118 - 119 = 65535 and 65417 + 119 = 0.

`amiga-vibrato.xm`, `AmigaVibratoTests`, and `RuntimeCMixerTests` pin periods,
memory/controls, zero hold/resume, and exact runtime/offline event frames.
G30B separately closes ordinary lookup and supported slide/tone extremes;
G30A owns fixed-point step conversion. Neither policy replaces vibrato wrap or
closes broader G39 interactions; the shared slide schedule is specified above.

## Portamento Units

Linear periods use 64 units per semitone: a decrease of `d` units multiplies
ideal frequency by `2^(d/768)`; G30A quantizes the published step. Regular/tone
and fine commands use `4 * parameter` units; extra-fine remains `parameter`, preserving the 4:1 ratio
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
  release and integer fadeout foundations exist. Bounded G31 volume arithmetic
  is closed: direct and carried segments share signed Q8 slope truncation and
  exact point reassignment through the existing final stereo targets. Both-rate
  whole/window/core/actual-host, reference-audio and Release gates pass. Volume-Lxx
  loop/end positioning and cold before-first initialization remain open, as do pan
  Float/Q8 and pan-clock quirks. See the
  [owned volume policy](design/xm-reset-output-ramp.md#g31-bounded-volume-envelope-q8-arithmetic).
  Instrument autovibrato (G32) is
  preserved but runtime-inert and remains Phase 2 playback work; later editable
  Instrument Editor controls are a separate roadmap milestone.
- **Volume writers and memory:** H00 replay (G13) is closed; its cold FT2
  zero-memory target-refresh artifact is an intentional known difference.
  Cold A00 restoration (G14) is closed under the bounded B convention above.
  Cold 600 held-target refresh, G15 cold Linear 500 and G16 fine-volume memory
  and G17/G18 Linear fine/extra-fine memory/restoration are closed.
  G28 Amiga 5xy composes the same writer and existing tone authority; Amiga
  fine/extra-fine shares the existing directional stores under G29.
  Rxy nibble memory, persistent counter, interval-zero/tick-zero dispatch and
  semantic carry and exact integer volume arithmetic are closed under G20–G22.
  G23 delayed instrument-only retained-note dispatch is closed separately;
  G24 note97/Kxx/default/writer precedence and both-rate host delivery are closed without broadening continuation effects. The overall product startup target remains separate.
- **Traversal:** EEx is a dedicated timing contract (G35). Bxx/Dxx/E6x
  precedence and E6's implicit loop start remain G37–G38; safe finite export
  guards do not establish reference in-song traversal parity.
- **Pitch and mode:** Linear in-range arpeggio ordering is closed under G25;
  Amiga quantized arpeggio reuses it under G26; G27 upward slides and G28
  5xy/Fx consumers close their bounded mode paths. G29 closes in-range Amiga
  E1/E2/X1/X2 and same-cell E5 through existing memory/trigger authorities;
  G30B closes bounded range/state behavior; G30A conversion is closed above.
  Supported Amiga vibrato's unsigned wrap/zero hold remains a separate policy.
  Combined bounded G30 verification is closed. Full 4xy/6xy/7xy audible
  interactions remain G39 without reopening their closed integer engines or 6xy timing.
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
