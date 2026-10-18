# Synthetic XM Reference Fixture Pack

This directory is VoodooTracker X's public, deterministic XM reference pack.
It includes approved generated binary XM fixtures; XI and reference audio
remain intentionally deferred.

## Purpose

`amiga-fine-extra-fine-finetune.xm` uses fourteen rows and twenty channels.
Channels 0–3 seed/replay fine and extra-fine memories and cover note97, ordinary
folding and active-source updates. Channels 4–8 use the actual E1F/E2F/X18/X28/
E5F target crossings and later 300. Channels 9–12 cover E50/E57/E58/E5F, exact
sample/different-instrument routing and writer precedence; channels 13–18 cover
release, cold, completed, empty, high-pitch and inert no-note E5 controls.
Rows 6–9 place F01/F02/F03/F06 after affected channels; rows 10–13 place them
before. PCM is original mathematical data. Swift tests pin the wider nibble,
header-tuning/relative-note, memory and retained G30 boundary matrix. FT2 WAVs
and local diagnostic artifacts remain external; G30 conversion/range and
onset/retirement remain separate.

`tone-portamento-direction-latch.xm` uses five rows and twenty channels. Rows
0–2 establish sources/targets and apply supported ordinary, regular-slide,
header-finetune and exact-keymap crossings; F02 gives one regular-slide tick.
Rows 3–4 restore F03 and exercise 300/500/F0, explicit target replacement,
equal-target inactivity, post-arrival direction, cold zero-speed clamp and
instrument/release preservation. Tests also pin Linear fine/extra-fine/E5,
move-away, cold/completed/empty and independent historical directions in both
modes/rates. PCM is original mathematical data; reference WAVs remain external.
G29 arithmetic, G30 conversion/extremes and onset/retirement remain separate.

`ordinary-trigger-tone-target-lifetime.xm` uses four rows and eight channels:
row 0 starts sources, row 1 seeds E-4/304, row 2 applies the boundary, and row 3
continues with 300. Channels 0–3 cover same instrument, different instrument,
different exact keymap sample and neutral E58; 4–6 replace the target through
3xx/5xy/volume Fx; 7 is the existing note-only control. Tests run the same data
in both modes and at both rates, with parameterized ordinary effects, release,
empty/completed/cold routes and speed changes. Mathematical PCM is original;
reference WAVs remain external. G29 execution, direction-latch quirks, G30
conversion and onset/retirement remain separate.

`rxy-counter-timing-carry.xm` covers G21's persistent R counter, interval-zero
execution, F01/F02/F03/F06, volume-column gates/slides, G20 nibble replay,
order/E6 carry, same-cell coalescing, exact empty routes and initialized
source-less volume changes. Looped and short mathematical PCM with envelopes
pin completed/released source restarts and fadeout carry. Only fully
uninitialized volume bookkeeping is excluded as C. Parameterized tests add
speeds 1/2/3/6 and the full counter-reset and column-gate matrices. Both-rate
whole/window/runtime checks retain the existing 32-frame retirement seam.
First-order rows 25...44 use F01 to distinguish modes 1/6/7/9/E/F, scaling
replay and clamps, including mode 6's 32→22→14. Exhaustive 0...64 integer
vectors and repeated sequences live in `RxyVolumeArithmeticTests`; G20 memory
and G21 counter/carry semantics are unchanged. Reference WAVs stay outside git.

`noteoff-kxx-precedence.xm` covers G24 in 34 rows and two channels with distinct
24/40 volume, 192/64 pan, enabled/disabled envelopes and a declared empty route.
Rows 0–2 expose cold K00 versus scheduled K01 through C40/note-only consumers;
6 and 11 cover note97/default/writer ordering and raw K00 trigger suppression;
16 covers column71 before K01 and changed-owner K21; 21 distinguishes K20
from out-of-row K06; 26 covers empty/default carry and C20; 30–31 cover Fxx
before/after K21 in channel order. Tests compare whole/window/runtime plans and
PCM at 44.1/48 kHz, with frame splits around releases. Mathematical PCM and
recipes are original project assets; reference audio stays external. G31/G40,
onset/replacement/retirement policy and note97 continuation effects remain separate.

`e90-row-entry-retrigger.xm` covers G19's special tick-zero source trigger:
carried and explicit note/instrument shapes, distinct mapped samples, cold and
completed one-shot channels, NOTE_OFF suppression, released envelope/fadeout
carry, explicit instrument reset, volume/pan ordering, concurrent channels,
E93 then E90, and 9xx/900 and Rxy separation. E90 has no interval memory;
instrumentless starts preserve channel state. Its original mathematical PCM
and recipes are redistributable. FT2 renders and local diagnostics stay outside
the repository; this fixture does not close mixer-ramp or Rxy gaps.

The pack provides small redistributable XM modules for parser, editor,
instrument/sample, preview-availability, and later audio-comparison tests.
Existing `tests/fixtures/minimal.xm` remains a tiny parser smoke fixture, but it
does not contain meaningful instrument/sample payload for positive editor
preview or audition planning tests. The original 64-frame sine fixture is also
too short for sustained audition, loop inspection, or useful waveform display.

## Provenance And License Rules

- Fixtures must be generated by this repository's tooling or hand-authored by
  the maintainer for VoodooTracker X.
- Fixture source, manifests, mathematical PCM, patterns, instruments, and
  approved binary fixtures are original VoodooTracker X project assets and
  inherit the repository's MIT license.
- Do not use private XM modules, copied tracker modules, commercial sample
  material, copyrighted songs, private corpus maps, private filenames, or
  private corpus-derived patterns, samples, instruments, names, or effects.
- Automated tests must use committed public fixtures or synthetic data created
  inside the test. They must not require private modules or local paths.

## Expected Layout

The intended fixture-pack layout is:

```text
tests/reference-xm/
  README.md
  source/
  generated/
```

`source/` stores reviewed source manifests and `generated/` stores only
manifest-approved binary XM fixtures. XI, WAV, AIFF, M4A, AAC, MP3, FLAC,
screenshots, traces, reports, benchmarks, and private/third-party modules do
not belong here.

## Generator Workflow

Use the deterministic generator from the repo root:

```bash
python3 scripts/generate-synthetic-xm-fixtures.py
python3 scripts/generate-synthetic-xm-fixtures.py --validate
python3 scripts/generate-synthetic-xm-fixtures.py --print-paths
python3 scripts/generate-synthetic-xm-fixtures.py --write-manifest
python3 scripts/generate-synthetic-xm-fixtures.py --write-xm
python3 scripts/generate-synthetic-xm-fixtures.py --verify
```

The default command prints the manifest to stdout and writes no files.
`--write-manifest` writes only
`tests/reference-xm/source/basic-instrument-sample.manifest.json`.
`--write-xm` writes only approved generated XM files under
`tests/reference-xm/generated/`. `--verify` regenerates in memory and fails if
any committed XM differs without rewriting it. Use
`--fixture NAME.xm` for scoped generation or
verification and `--output-dir` for test-temporary output. Generation reports
the filename, byte count, instrument/sample counts, and SHA-256. No command
emits reference audio.

Generated WAV, JSON, Markdown, trace, log, screenshot, and exploratory render
artifacts stay under `/tmp` or another ignored local path unless a future PR
explicitly approves committing that exact artifact.

## Generated Fixtures

`generated/amiga-portamento-up.xm` is an 18-row Amiga control with original
looped sine PCM. Rows 0–4 pin cold 100, speed-1 seed/replacement refusal and
101 replay; 5–6 pair 104/204 at speed 6 with finetune +127 and relative +12.
Rows 7–11 cover release, retained slides and note-only sources; 12–15 put
F01/F02/F03 before the effect channel. Both-rate tests cover all nine requested
parameters, speeds 1/2/3/6, finetunes -128/0/+1/+127 and relative ±12/0.
Rows 16–17 isolate B-7 1FF/100: the existing VTX minimum 107 and one update per
clamped row differ from FT2 native period 1 and later refreshes (G30). Compare
ordinary listening through row 15 separately from this deliberate edge control.
Whole/window/runtime/host checks preserve source generations and cursors;
reference WAVs stay external and automated checks do not establish listening.

`generated/regular-portamento-memory-admission.xm` is a four-channel, 12-row
Linear control with looped mathematical PCM: rows 0–1 distinguish speed-1
104/204 attempts from cold replay; 2–4 distinguish valid 101/201 seeds from
speed-1 replacement; 5–6 cover F02 admission and F03 replay. Channel 2 pins
directional independence; 7–11 cover release, note and instrument carry.
Tests also project the same public value into Amiga mode for regular 1xx/2xx.
Both-rate tests cover memory/periods, Fxx before/after,
whole/window/runtime delivery and cursor continuity. Reference audio stays external.

`generated/extra-fine-pitch-directional-memory.xm` is the G18 two-channel,
two-order Linear control with a looped mathematical sample. Rows 0–4 pin cold
same-cell folding, B8 restoration and B0 continuation; later rows pin independent
direction/channel memory, E13 independence, F01/F03/F06, order carry, same-cell
replay, amount-F, effect-vibrato exit, key-off and note-only controls.
`ExtraFinePitchMemoryTests` adds canonical-empty/completed/uninitialized
qualification, converged deduplication, E1/E2/regular/tone/modulation independence,
parent range and the unchanged Amiga guard. Whole/window/core/engine checks use
44.1/48 kHz. Cold commands restore meaningful canonical pitch without provenance;
FT2's source-less cold-X10 0→1 artifact is omitted. Amiga remains G29; reference
WAVs stay external.

`generated/fine-pitch-directional-memory.xm` is the G17 two-channel, two-order
Linear control using a looped mathematical sample. Rows 0–4 pin cold same-cell
folding, B8 restoration and later B0 continuation. Rows 5–11 and the second order
pin independent directional/channel memories, order carry, X13 independence,
F01/F03/F06, same-cell replay, amount-F, key-off and note-only controls.
`FinePitchMemoryTests` additionally covers source-less, completed/empty routes,
parent clamp boundaries, converged deduplication, regular/tone/modulation memory
independence and the unchanged Amiga guard. Whole/window/core/engine checks use
44.1/48 kHz. Uninitialized cold E10 intentionally omits FT2's 0→1 artifact;
Amiga fine-pitch stays G29; G18 is covered separately above. Reference WAVs remain external.

`generated/fine-volume-directional-memory.xm` is the G16 two-channel, two-order
control with a looped mathematical sample at header volume 32. Rows 0–7 pin cold
current/stale-global and tremolo restoration; 8–11 pin independent EA3/EB4/EA0/EB0
with a cold second channel. The second order pins boundary replay, volume-column
8x/9x and A/5/6 independence, F01/F03/F06, same-cell and note-only controls, clamps
and key-off. `FineVolumeMemoryTests` adds parameterized lifetimes, empty/completed
routes, envelope/fadeout and whole/window parity. Runtime tests compare every
event frame and source order at 44.1/48 kHz. Reference WAVs stay outside git.

`generated/cold-a00-output-restoration.xm` is the small G14 compatibility
control: two channels, seven rows, one looped mathematical sample and one exact
empty slot. 748 leaves output 63; cold A00 restores current base 32 at tick 1
without seeding shared slide memory. E76 state, later 700, repeated A00 and
empty-route note-only inheritance are pinned by `ColdA00Tests`. Parameterized
tests also cover speed/Fxx, other base writers, envelopes, resets, real A/5/6
seeds and unchanged cold H00 at 44.1/48 kHz. Reference WAVs remain external.

`generated/cold-600-local-publication.xm` is a two-channel, four-row control
with one looped mathematical sample. A source born before later-channel G10
holds gain 1 with base/output 64 and canonical global 16. Cold 600 at row 2 tick 1
publishes .25; repeated 600 at row 3 emits no duplicate. Slide memory stays
absent. `Cold600Tests` also pin numeric 63→32 restoration, speed/Fxx, seeded
A/5/6 replay, Linear/Amiga vibrato, silent/completed routes, envelope/fadeout,
and whole/window parity at both rates. Cold A00/H00 and cold 500 stay independent.

`generated/cold-500-local-publication.xm` is a project-authored, two-channel,
four-row Linear control with one looped mathematical sample. Later-channel G10
leaves held gain 1; note-only 301 establishes tone state; cold 500 publishes .25
at row 2 tick 1, then deduplicates row 3 without retrigger or seeded memory.
`Cold500Tests` cover all four tone states, 63→32 tremolo restoration, native/Fxx
speeds, real shared seeds, reached targets, note forms, silent/completed routes,
envelopes and the unclosed partial Amiga boundary. Whole/window/runtime checks
use both rates. It inherits the repository license; reference artifacts remain
external.

`generated/basic-instrument-sample.xm` is generated by
`scripts/generate-synthetic-xm-fixtures.py` from the deterministic manifest in
`source/basic-instrument-sample.manifest.json`. It inherits the repository
license.

Contents:

- XM 1.04, one song position, one pattern, one channel, and 16 rows.
- One instrument named `BASIC SAMPLE`.
- One one-shot 64-frame signed 8-bit delta-encoded sine sample named `SINE64`.
- A C-4 note using instrument 1 on row 0 and a key-off event on row 8.

XM sample payloads do not store a WAV-style sample rate. VTX exposes this
neutral generated XM sample with the expected parsed/generated base sample rate
of 8,363 Hz, matching the current XM linear-period sample-rate decision. Tests
that use this generated fixture should assert that real parsed/generated value
separately from synthetic unit-test helpers that choose small explicit rates
such as 100 Hz for deterministic offline math.

Tests may use this fixture for parser metadata/event positive paths, app-level
instrument/sample payload loading, selected instrument/sample availability, and
inert preview-availability checks. This fixture is not a reference render asset,
and no WAV files are generated or committed for it.

`generated/multi-pattern-loop-boundary.xm` is generated by the same script and
is recorded in the deterministic source manifest with SHA-256
`8438e6074df6d4a6e1ec540121b7adeaf96e199166619a0ae00085c7fafd1ca3`.

Contents:

- XM 1.04, three song positions, three patterns, one channel, and four rows
  per pattern.
- Order table `[0, 1, 2]`, so normal traversal crosses two order boundaries.
- One instrument named `BOUNDARY SAMPLE`.
- One one-shot 64-frame signed 8-bit delta-encoded sine sample named
  `BOUNDARY64`.
- Row-0 note triggers in each pattern: C-4 in pattern 0, E-4 in pattern 1, and
  G-4 in pattern 2.

Tests may use this fixture for public-safe order traversal, pattern/order
mapping, adapter-plan event ordering, and future adapter-safe pattern-loop
design coverage. It does not implement pattern-loop playback and contains no
pattern-loop effect commands.

`generated/instrument-sustained-defaults.xm` is the first fixture in a
three-PR instrument-pack series. It is 33,486 bytes with XM SHA-256
`babedfc9bd79f7e1ac79dbec6493e2182182700a8855c42cd15405f4eb6f0fde`.

Contents:

- XM 1.04, one order, one 64-row pattern, and one channel.
- One instrument named `SUSTAINED DEFAULTS` with an enabled volume envelope at
  `(0,64)`, `(24,56)`, and `(48,64)`.
- One sample named `SINE SUSTAIN 16`: 16,384 frames of project-generated
  signed 16-bit sine PCM at amplitude 12,000, PCM SHA-256
  `46c42a0de8820c8b24419c1676b183398d1e7ced677860df1fe0ea45a48779b0`.
- Volume 64, panning 128, finetune 0, relative note 0, and a smooth forward
  loop starting at frame 4,096 with length 8,192.
- C-4 at row 0, key-off at row 16, G-4 at row 24, and key-off at row 48.

This is the default public fixture for sustained Instrument Editor audition,
Sample Editor waveform/loop inspection, Make Editable Copy, focused metadata
edits, and Export XM/reopen. Sample-header panning remains editable and
round-trippable and initializes each newly triggered preview/playback voice.

`generated/instrument-metadata-matrix.xm` is the second fixture in the series.
It is 5,635 bytes with XM SHA-256
`590e4aaafc71c41130cb1a9a4e768220c38c6e8dcdd3529d9be6e35ec400aef3`.
Its five one-sample instruments provide compact pairwise coverage:

| Instrument | Pan | Vol | Finetune | Relative | PCM | Loop | Waveform |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| I01 | 0 | 0 | -96 | -12 | 8-bit | none | sine |
| I02 | 64 | 16 | -32 | +5 | 16-bit | forward | triangle |
| I03 | 128 | 32 | 0 | -5 | 8-bit | ping-pong | saw |
| I04 | 192 | 48 | +48 | +12 | 16-bit | none | pulse |
| I05 | 255 | 64 | +96 | 0 | 8-bit | forward | triangle |

Rows 0/8/16/24/32 select instruments 1...5, with key-off events at rows
6/14/22/30/40. Tests pin every sample's PCM hash and verify exact loader/model,
editable-copy, metadata mutation/undo/redo, planned panning, and Export
XM/reopen preservation.

`generated/instrument-envelopes-keymap.xm` is the third fixture and completes
the series. It is 6,870 bytes with XM SHA-256
`02c195c97ea64b0be56f75c86e4b2a5e565690cff39500f09dadc3441eeeee09`.
Its one instrument maps notes 1...48 to an 8-bit forward-looped pulse sample
and 49...96 to a 16-bit forward-looped triangle sample. It preserves exact
volume and panning envelope points, sustain/loop indices, fadeout 2,048, and
autovibrato type/sweep/depth/rate `2/8/6/24`; pattern notes on rows 0 and 12
cross the sample-map split. Tests pin both PCM hashes and verify loader/model,
editable-copy, and Export XM/reopen preservation.

Named empty sample slots and named sample-less instruments remain intentionally
absent because the current loader/writer model cannot round-trip their names
honestly. Later focused fixtures cover isolated loops, preview, traversal,
pitch/volume effects, retrigger/cut/delay/key-off, effect memory, and
volume-column effects only after their expected semantics are documented.

`generated/fxx-timing.xm` isolates current-row Fxx speed/BPM application and
runtime/offline planned-frame parity. It is 1,252 bytes with XM SHA-256
`b91cf6454787f8494b7b7579e00cd59cac8dc7fea2a4b831af043a8190273c1b`.
The Linear XM starts at speed 6/BPM 125, with one 16-row pattern, two channels,
and one neutral, envelope-free instrument containing a forward-looped 256-frame
16-bit sine. Channel 0 retriggers alternating C-4/E-4 on every row so timing
boundaries are audible; channel 1 contains only timing commands.

| Row | Channel 0 | Channel 1 |
| ---: | --- | --- |
| 0, 2, 4, 13, 15 | Ordinary note | Empty |
| 1 | F03 | Empty |
| 3 | F96 | Empty |
| 5, 6, 7, 8, 9 | F06, F7D, F1F, F20, FFF respectively | Empty |
| 10 | F03 | F06 |
| 11 | F20 | F7D |
| 12 | F03 | F96 |
| 14 | F06 | Empty |

The paired commands cover later-channel speed/BPM precedence and independent
speed/BPM updates on one row. F00 and other effect families are absent.
Reference renders of this fixture remain local under the existing comparison
workflow in `docs/audio-comparison.md`.

Binary XM fixture commits must remain explicit, small, deterministic, and
reviewed as test asset changes.

`generated/portamento-scaling-linear.xm` (1,270 bytes) and
`generated/portamento-scaling-amiga.xm` (1,191 bytes) isolate supported pitch
trajectories for ModuleCore, runtime/offline adapter, and rendered-audio tests.
Both use one channel, speed 6/BPM 125, and the same neutral, envelope-free,
forward-looped 256-frame 16-bit sine as the timing fixture. Each eight-row case
starts C-4/I01 with explicit volume-column `50` at its first row, applies commands
at offsets +2/+4, mutes with C00 at +6, and holds on remaining rows. The explicit
volume restores 64 after each mute so cases are independently audible.
Row numbers below are decimal.

| Fixture | Case start | First command (+2) | Second command (+4) |
| --- | ---: | --- | --- |
| Linear | 0 | 110 | 100 |
| Linear | 8 | 210 | 200 |
| Linear | 16 | G-4 310 | 300 |
| Linear | 24 | G-4 310 | 501 |
| Linear | 32 | G-4, volume F1 | Volume F0 |
| Linear | 40 | E1F | E2F |
| Linear | 48 | X1F | X2F |
| Amiga | 0 | 210 | 200 |
| Amiga | 8 | G-4 310 | 300 |

Linear contains 56 rows (6.72 seconds); Amiga contains 16 (1.92 seconds).
The manifest pins XM and PCM hashes. Blank rows deliberately hold pitch between
motion rows; target notes carry no instrument. Amiga coverage is restricted to
existing `2xx` and effect-column `3xx`; its other pitch families remain deferred.
Compare each fixture with an ft2-clone render in its own frequency mode using
the local comparison workflow in `docs/audio-comparison.md`.

`generated/tremolo-effects.xm` (1,350 bytes) isolates `7xy`/`E7x` with one
channel, speed 6/BPM 125, Linear frequencies, and 56 rows (6.72 seconds). Its
single envelope-free instrument uses the same forward-looped 256-frame 16-bit
sine as the timing fixture, with header volume 64. Explicit volume-column `30`
sets tracker base volume 32, leaving room for both modulation signs. The
manifest pins XM SHA-256
`9786b13560ec9d6360fa519d7abcdf0263a6c2f36491d6dd67ce2b0c67d814ca`.

| Rows (decimal) | Case |
| --- | --- |
| 0, 1, 2, 3 | C-4/I01/volume `30`; no-note `748`; `700` continuation; empty row retaining output |
| 4, 5, 6, 7 | C-4/I01/volume `30` + `704`; `730`; `700`; empty row retaining output |
| `8 + 6*x`, for `x = 0...7` | `E7x` + volume `30` establishes each waveform/reset control |
| Each control row +1 | C-4/I01/volume `30` + `748`, with instrument-driven phase reset or retention |
| Each control row +2 | C-4 without instrument + `700`, retaining phase |
| Each control row +3, +4, +5 | C-4/I01/volume `30` + `700`; no-note `700`; empty row retaining output |

`E70/E74` select sine, `E71/E75` ramp, and `E72/E73/E76/E77` square;
bit 2 suppresses instrument-driven phase reset. `E78...E7F` aliases are pinned
by numeric tests. Empty rows deliberately retain the last output; explicit
volume writes establish the next base/output baseline. No unrelated effect
commands occur.

Quiet-sample characterization derives the same fixture in memory with its sole
sample header changed from 64 to 16. Generator tests prove only byte 810 changes;
PCM, commands, and tracker-volume trajectories stay comparable. Any local quiet
XM or WAV derivative stays outside the repository. The known downstream sample
scaling compatibility gap is separate from tracker-domain tremolo correctness;
see [volume ownership](../../docs/design/xm-volume-ownership.md).

`generated/vibrato-semantics.xm` (1,327 bytes) isolates the shared FT2
`4xy`/`E4x` foundation and vibrato component of `6xy`. It uses Linear
frequencies, one channel, speed 6/BPM 125, and 46 rows (5.52 seconds). Its
single neutral, envelope-free instrument contains the same forward-looped
256-frame 16-bit sine as the timing fixture. The manifest pins XM SHA-256
`ed8c96a7b13c668650ed816f19cc9fe444e288aa783002f40d299bc4c9c5ec18`.

| Rows (decimal) | Case |
| --- | --- |
| 0...7 | C-4/I01; no-note `448`; `400`; `403`; `480`; `400`; instrument-only I01 + `400`; empty |
| `8 + 2*x`, for `x = 0...15` | `E4x` establishes each waveform/reset control |
| Each control row +1 | C-4/I01 + `488` exercises the selected waveform and instrument-driven phase reset or suppression |
| 40...45 | `E40`; C-4/I01/volume `30` + `448`; `601`; `610`; `612`; empty |

FT2 samples the current phase before advancing by four times the speed nibble.
The integer waveform magnitude times depth is shifted right by five; phase bit
7 selects the period-delta sign. `E4x` low two bits select sine, ramp, square,
square; bit 2 suppresses instrument-trigger phase reset and bit 3 is ignored.
The `488` rows advance far enough to exercise both waveform halves. Explicit
instrument triggers test reset behavior, including the instrument-only row 6.
`400`, `403`, and `480` exercise complete and independent nibble
memory. Numeric tests own exact tick trajectories and phase wrapping.

The final `6xy` rows have explicitly seeded vibrato state. `effect-memory.xm`
owns the shared slide memory and tick-scheduling acceptance contract. This fixture establishes the
shared foundation in Linear mode; Amiga execution uses its own fixture below.

For maintainer listening, load this fixture and compare rows 1...6, the control
pairs at 8...39, then the seeded combination at 41...44 against an ft2-clone
reference. Export the reference at 48,000 Hz, 32-bit float WAV, Linear (FT2)
interpolation, Linear frequency slides, Amplification 10x, Master volume 256,
Volume ramping ON, and Precise BPM OFF. Follow
[audio comparison](../../docs/audio-comparison.md), retaining all WAVs and
diagnostic artifacts outside the repository. Audio comparison corroborates the
exact tick-domain tests; listening requires maintainer confirmation.

`generated/amiga-vibrato.xm` (1,253 bytes) uses Amiga frequencies, one channel,
speed 6/BPM 125, and 30 rows (3.6 seconds). Its one sustained 16-bit sine is
the same original project PCM with sample finetune +8. The manifest pins
SHA-256 `aa74e2992daebef012792f76ce34fa81c9e22e75a833ab5d2df3895de4d30012`.

| Rows (decimal) | Case / listening window |
| --- | --- |
| 0...5 (0.00–0.72 s) | C-4/I01 `448`, three `400` rows, `403`, `480`: positive/negative sine halves, phase wrap, nibble memory |
| 6...19 (0.72–2.40 s) | `E41` ramp, `E42` square, `E44` reset suppression, then `E40`; explicit instrument, instrument-only, and note-only cases |
| 20...23 (2.40–2.88 s) | C-4/I01/volume `30` + `448`; `602`, `600`, `612`: seeded vibrato, retained slide policy |
| 24...29 (2.88–3.60 s) | `E40`; A#7/I01 `44F`; three `400` rows; empty restore |

The final case starts at FT2 period 119. Row 27 tick 3 (3.30 s, frame 158400)
subtracts 119, producing an explicit zero step for 960 frames, then resumes the
same source cursor. Tests also cover unsigned underflow/upper wrap directly.
No other Amiga pitch family is present. Render the local reference with the
profile above, changing Frequency Slides to **Amiga** after loading the XM.
Compare the first three windows for ordinary vibrato, controls/triggers, and
seeded `6xy`; the final extreme-pitch window corroborates numeric zero delivery.
All WAVs/diagnostics stay outside git. Maintainer listening remains a separate
gate; optional real-corpus listening follows only after the public gate passes.
The note-only cells at rows 15 and 19 restart the exact mapped source and
restore the note base at tick 0 while preserving vibrato phase. Subsequent
vibrato ticks retain the same shared modulation contract.

`generated/vibrato-empty-route-state.xm` (1,228 bytes) isolates parent vibrato
execution across canonical empty routing. S01 is a project-generated looped
sine; C#4 maps exactly to zero-payload S02, and C-4 maps to S01. Rows 0...7
select E44, seed `435`, select empty S02 with `400`, return to S01 with `400`,
select empty S02 note-only with `464`, issue instrument-only `400`, return to
S01 with `600`, then leave the effect family. Only rows 1/3/6 create sources.
The later row-3 `400` begins at phase 120 with speed 3/depth 5. Its Linear
tick periods are 4615/4605/4593/4583/4575; Amiga reference periods are
1719/1709/1697/1687/1679 before VTX's 4x mapping. Tests execute both modes at
44.1/48 kHz and split windows before/after empty rows. The stored fixture uses
Linear; reference Amiga verification changes Frequency Slides after loading.
The separate Ax/Bx fixture below covers volume-column dispatch; onset and pan-law
parity remain separate.

`generated/volume-column-vibrato.xm` (1,277 bytes) extends the same project sine
and exact empty S02 route across 25 rows. It covers Ax/A0, Bx/B0, speeds 1/3/6
via same-row Fxx, shared 400/600 memory, ordered Bx+4xy/Bx+6xy executions,
note-only/instrument-only resets, E4 sine/ramp/square controls and later audible
consumption after empty routing. The first nine row-end phases are
0/0/24/84/84/144/80/24/44. Only rows 0/11/16/23 create sources;
empty-route rows 14/15 retain memory, and row 15 executes Bx without PCM or
pitch events.
Focused tests use both frequency modes at 44.1/48 kHz and split windows across
shared writers and empty routes. The stored fixture is Linear; reference Amiga
verification selects the existing frequency mode after loading. Whole/window
and runtime checks retain both same-frame mixed-writer updates. Broader pitch,
onset, autovibrato and pan-law contracts remain independent; reference WAVs and
diagnostic captures stay outside git.

`generated/envelope-release-fadeout-timing.xm` (2,869 bytes) isolates shared XM
semantic targets. Four Linear channels and 16 rows start at speed 6/BPM 125.
Three instruments use the original project-generated 256-frame, 16-bit sine
at amplitude 8192, with a forward loop. SHA-256:
`a83c9bc00d869b1415c886877ddc57094ec049db2d67b7973af4523b5712a60e`.

| Channel / rows | Case |
| --- | --- |
| 0, trigger at 0 / key-off at 3 | Rising/falling volume envelope, sustain at tick 8, fadeout 1024; a neutral pan-envelope loop shares the clock. |
| 1, trigger at 0 / key-off at 3 / `C40` at 4 | No volume envelope; immediate semantic mute, continued fadeout/source, then volume restoration. |
| 2, trigger at 0 / key-off at 5 | Exclusive-end envelope loop with fadeout zero, continuing after release. |
| 3, `FFA` at 2 / `F03` at 4 | BPM then speed changes while the three voices remain active. |

The fixture is 0.72 seconds at the specified tempo sequence. Exact semantic
state/frame assertions are primary; reference output ramps are a separate
contract. Any longer listening variants and reference WAVs stay outside git.

`generated/effect-memory.xm` (1,261 bytes) isolates shared `Axy`/`5xy`/`6xy`
volume-slide memory and `6xy`/`600` tick timing. Two Linear channels, one neutral
sustained project sine, 18 rows, speed 6/BPM 125, with speed-1 controls at rows
13–14 and speed 3 at rows 16–17. SHA-256:
`0e20804e0bbf9aba449c58b76ab97ba93ec02429c5fa056ed26d8a118c43f168`.

| Rows (decimal) | Channel 0 | Channel 1 |
| --- | --- | --- |
| 0–2 | C-4/I01/volume30 `600`, `602`, `600` | C-4/I01/volume30 `448`, `600`, `600` with no slide memory |
| 3–5 | `448`, `600`, empty retention | `C20`, `A01`, `600` |
| 6–7 | `C20`, C-4/I01/volume30 `600` | `501`, `600` |
| 8–11 | instrument-only/volume50 `600`, note-only `600`, `600`, empty | C-4/I01/volume30 `631`, `600`, `A00`, `500` |
| 12–15 | `C20`, `620`, `600`, `600` | `C20`, `F01`, empty, `F06` |
| 16–17 | C-4/I01/volume30 `602`, no-note `600` | `F03`, empty |

At 48 kHz each tick is 960 frames; the one-pass plan ends at frame 88320 (1.84 s). `VolumeSlideMemoryTests`
pins memory origins and bounded/windowed output; `RuntimeCMixerTests` checks
exact runtime gain frames. Row 8 explicitly sets volume 64 to isolate slide
timing from instrument-only default restoration. The fixture introduces no other
memory family.
For FT2 reference use pinned commit `87be42543dac82cf802b5bddad917bda62ace131`,
48000 Hz stereo Float32, Linear interpolation/frequencies, amplification 10,
master 256, ramping on, Precise BPM off. Compare exact tick volumes and frames:
channel 0 row 1 is `32, 30, 28, 26, 24, 22`, row 2 is `22, 20, 18, 16, 14, 12`;
rows 13–14 hold 32 with no slide; rows 16–17 are `32, 30, 28` and `28, 26, 24`.
The first value is tick 0. Whole-WAV equality is not an acceptance criterion.
For a listening sanity check, play rows 0–2: the seeded channel continues
sliding on `600`, while the unseeded control retains volume. Then check rows
4–11 for shared-family replay and 16–17 for speed-3 cadence. Compare the within-row
stair steps with ft2-clone. Listening requires an explicit maintainer report.

`generated/instrument-only-volume-semantics.xm` (2,603 bytes) covers instrument-only
cached defaults and non-retriggering resets. It has two Linear channels, 24 rows
at speed 6/BPM 125 (2.88 seconds), and three independently generated
16-bit sine samples (256-frame loops and a 257-frame one-shot ending at zero).
SHA-256:
`780564b2b56046ea092f3d2a109e5de57cde98f2ea0cabc6d6bd1810b1d8c6a2`.

Instrument 1 maps notes 1–48 to default 64/pan 64 and notes 49–96 to default
24/pan 192. Both loop. Its volume envelope falls from 64 to 16 in three ticks;
fadeout is 1024, and a neutral pan-envelope loop exercises clock reset.
Instrument 2 is a default-48 one-shot used for the cold/completed control.

| Rows | Case |
| --- | --- |
| 0–4 | Establish full sample, reduce volume, same/different instrument-only resets; cold channel later explicitly triggers, then receives a completed-voice reset. |
| 5–6 | Key-off followed by same-generation reset. |
| 7–9 | Trigger mapped quiet sample, reduce, restore cached quiet default with a different instrument number. |
| 10–12 | Same-cell volume/pan override, K00 exception, then ordinary reset. |
| 13 | Note-only retriggers the carried instrument's mapped sample and continues semantic state. |
| 14–23 | Final key-off, natural fadeout and silence. |

At 48 kHz channel 0 resets at frames 11520, 23040, 34560, 51840, 57600 and
69120, with 240-frame ramps. At 44.1 kHz the corresponding ramps last 220
frames. Source generation/cursor and exact semantic state are primary evidence;
quiet-sample/header ownership remains a known reference difference.
Reference audio and diagnostic artifacts remain outside git.

### Empty-slot playback state

`generated/empty-slot-playback-state.xm` (2,310 bytes) contains one generated
represented loop, six declared zero-payload ordinary headers, and a generated
one-shot control. Its 96-note map preserves each empty identity. No reference
PCM, private modules or imported assets are included. The generator permits
zero-frame recipes only with unflagged 8-bit encoding and no loop.

| Rows | Control |
| --- | --- |
| 0–4 | Represented source to volume-40 empty slot, silent release/reset; second channel starts empty and later completes a one-shot. |
| 5–7 | FFA tick-duration change, silent K01, then instrument-only volume/pan overrides. |
| 8 | Explicit represented note refreshes its own volume/pan defaults. |
| 9–13 | Canonical zero, pan 224, finetune +64, relative note +12, and combined headers. |
| 14–17 | Silent tone portamento, silent reset, explicit represented trigger, release. |

`EmptySlotPlaybackStateTests`, runtime application tests, and editable-copy tests
pin metadata ownership, no voice for empty routes, canonical clocks and windows,
source retirement, stale/completed safety, and ADR 014's conservative refusal.
Audible pan envelopes remain deferred. Note-only continuation is covered below.

### Note-only routing

`generated/note-only-routing.xm` (4,062 bytes) uses 48 rows, two Linear channels,
speed 6/BPM 125 and project-generated PCM. Three instruments provide exact
split keymaps, neutral panning clocks, envelope/release carry and a one-shot.
The second instrument also declares an empty S03 with volume 40, pan 128,
finetune +64 and relative note +12; only G-4 maps to that identity.

| Rows | Control |
| --- | --- |
| 0–3 | Explicit I01, then same-sample and different-sample note-only restarts. |
| 5–8 | I02-only carries a new owner while I01 sounds; subsequent notes resolve I02/S01 and S02. |
| 10/12/14 | 3xx, 5xy and volume-column Fx retain the existing source. |
| 16–18 | Release followed by a note-only source restart that stays released. |
| Channel 2: 0/2/4/8/10 | No owner, cold selection, zero-volume note-only, explicit one-shot, completed-source restart. |
| 24–29 | Start I02/S01, set volume 16, select empty S03, restore 40 while silent, then play S01 at carried volume 40 and envelope tick 6. |
| 34–47 | Natural release/fadeout ending for an unambiguous repeated listening comparison. |

Tests pin source identity, cursor restart, cached defaults, exact empty-route
retirement, silent channel clocks, tuning, and shared runtime/offline/window
frames at 44.1/48 kHz. Listening must contain both represented routing and the
later playable consequence of the empty-slot chain. VTX retains immediate
new-source onset versus FT2's 5 ms ramp. Audible pan envelopes, independent
sample/header scaling, and FT2 Rxy repeat timing/state parity remain separate.

### Volume-column slide timing

`generated/volume-column-slide-timing.xm` uses two channels, a project-generated
loop and an integral-slope volume envelope. Rows 0...2 pair `61/71` with
`F01/F03/F06`; row 3 pins Cxx/clamps, row 4 zero amounts, rows 5...6 fine slides,
and row 7 independent A/6 writers. `VolumeColumnSlideTimingTests` and runtime
controls pin exact values/frames and whole/window/runtime parity at both rates.
Reference WAVs and observer artifacts remain outside git. G11/G31/G40
and new-source/generic-ramp differences retain their separate boundaries.

### Volume-column panning-slide timing

`generated/volume-column-pan-slide-timing.xm` pairs `D1/E1` with same-row
`F01/F03/F06` on rows 0...2. Row 3 tests `D0` after `8E0` and `E0`
continuation; row 4 clamps `DF/EF` from `802/8FE`; row 5 contrasts `E0` at
zero with `D0` at 255. A generated loop and flat volume envelope isolate
stored pan and the existing final-L/R targets. `VolumeColumnPanSlideTimingTests`
adds constant-PCM controls for static-writer precedence, source-less/completed
carry, G06/G07 and G08 regression at both rates. G11 conversion, G33/Pxy,
G40 stereo law and generic/onset ramp differences remain separate.

### Global-volume slide timing

`generated/global-volume-slide-timing.xm` is 3,254 bytes, SHA-256
`4297ac913447883d0f140cbcaeb928e6b7d1080d80216619a35d1c5b6486be61`.
Its five channels use distinguishable project-generated sine/triangle/pulse
samples with header volumes 64/32/16 and one volume-envelope/fadeout instrument.

- Rows 0...3 set G20 and exercise source-less Hxy at F01/F03/F06. Row 4 notes
  inherit final canonical volume 29 without fabricated earlier voices.
- Rows 5...9 exercise opposed, same-direction and three writers. Opposed
  H01/H10 ends at 32 with turn factors `[31,31,32,32,32]`; row 7 holds them.
- Row 10 publishes Cxx/column volume before later-channel G20. Rows 11...16
  add the envelope source, clamp down/up and exercise H12 upper-nibble priority.
- Row 17 now replays H12 through G13, taking canonical 37 to 42. Rows 18...21
  release the envelope, run a final-channel H01, refresh the envelope on the
  blank row, then trigger a fresh note using canonical volume 37. The fixture
  bytes are unchanged; G12 timing/publication remains authoritative.

`GlobalVolumeSlideTimingTests` also constructs independent public controls for
H01/H10/H12 speeds 1/3/6 and early/middle/final writers, including held targets
through pan-only commands. Whole/window/runtime-core and canonical-host checks
use the shared gain targets at 44.1/48 kHz. Generic ramps, onset, envelope
arithmetic and static pan law retain their separate closure boundaries.

### Global-volume slide memory

`generated/global-volume-slide-memory.xm` is 2,522 bytes, SHA-256
`4ad3e67e1658d070ca731e58ddb0c978572717cc27d9614a597e5b80045580ee`.
Its three channels use project-generated triangle/pulse/sine samples at header
volumes 64/32/16, including a completed nonlooping source and an exact empty S02.

- Rows 0...2 seed/replay without sources; later notes inherit canonical state.
- Rows 3...6 leave an earlier 28/64 held target with canonical 27. Cold H00 on
  channel 2 emits no publication and retains the target, matching a blank command.
- Rows 7...11 store H12/H21, replay independent memories and exercise F01's
  no-replacement gate followed by F03/F06 scheduling.
- The second order replays memories from the first. Empty-route selection,
  key-off, instrument-only state and later mapped notes retain memory.
- Later rows seed/replay H01 at zero and H10 at 64, preserving G12's resolved
  command publications even when the canonical clamp does not move.

G13 closes seeded H00 replay. FT2's cold zero-memory target-refresh artifact is
intentionally not emulated; this fixture makes no bit-perfect cold-H00 claim.
Whole/window/runtime-core and canonical-host controls use both sample rates.

## Global-volume channel-turn publication fixture

`generated/global-volume-publication.xm` is 5,999 bytes, SHA-256
`27861cb28fd0349cfb00b7157f3c3c4b4f5fe9fd5a299e0bddecff0a285939c9`.
It has six channels, 42 rows at speed 6/BPM 125 and seven distinct mathematical
PCM identities, including a flat volume envelope, a short completed source and
an exact empty S02 route. The shared manifest is its sole generation input.

- Rows 0...14 cover note-before-G10 birth/blank hold, repeated C40,
  replacement-before-G00/C20 repair, volume-column 50, repeated G10,
  Gxx-before-note and same-cell note+Gxx.
- Rows 15...21 put notes before/between/after G20 then G10, preserving
  `[1, 0.5, 0.25]` until real publications; H01/H00 retain G12/G13 behavior.
- Rows 22...31 cover next-tick envelope refresh, completed/empty sources and
  later-note inheritance without fabricated sources.
- Rows 32...41 cover publications before/after replacement, inert cold H00,
  notes around a channel-2 G10, blank hold and repeated C40.

Both-rate tests distinguish canonical global, birth gain and generation-owned
held targets, including real publication intent when calculated gain was already
equal. Whole/window/runtime-core and host delivery use the same causal stream.
Generic ramps, source onset, G31 arithmetic and full FT2 mix parity stay separate;
reference WAVs and diagnostic artifacts remain external.

## Delayed instrument-only EDx fixture

`generated/delayed-instrument-only-edx.xm` has six channels and 18 rows at
speed 6/BPM 125. I02 routes retained C-4 to S02 (volume 40/pan 224), and C-5
to S01 (24/64); I01's header is 64/192. Project-generated waveforms distinguish
sources. I03 is a completed one-shot, I04 has a declared empty S02 retaining
40/224, and I05 has no sample header or playable route.

- Rows 2–3: same-instrument ED1, changed-instrument ED2, completed ED3,
  preexisting release and later note-only through I02.
- Rows 4–7: ordinary instrument-only ED0, out-of-row EDF, unavailable/empty
  routes and later note-only recovery through the exact map.
- Rows 7–9: delayed column set-volume/set-pan and ordinary slide ordering.
- Rows 10–12: 9xx/900 memory followed by cursor-zero delayed restart.
- Rows 14–15: cold/no-retained-note delay and later silent note-only source.

Focused model controls add speeds 1/2/3/6, both Fxx channel orders, delays
1/2/3/5/F, fine-command skips, phase suppression and exact frame window splits.
Whole/window/runtime-core and canonical-host checks use 44.1/48 kHz. Reference
WAVs and local evidence stay outside git; listening is a maintainer handoff.

## Linear arpeggio ordering fixture

`generated/linear-arpeggio-ordering.xm` is 1,237 bytes, SHA-256
`6be4929f28dd05f518eb4e2536de9adb35e0556aa2ea5e972b2c147406cf0e99`.
Its two channels use one project-generated forward-looped sine source at
speed 6/BPM 125 initially; same-row Fxx changes give 81 ticks / 1.62 seconds.

- Rows 0–2: F02 after same-cell `037`, active continuation, then inert `000`.
- Rows 3–5: note-only `073` at F03, `010`, then `000`.
- Rows 6–9: low in-range `037`/`073` at F06, release, then retained-source `001`.
- Rows 10–13: F07 before same-cell/active `037`, then F02 before `073` and `000`.
- Rows 14–15: B-7 `037` pins phase ordering separately from unchanged G30 range
  targets: VTX +7/+3 periods 1152/1408 versus FT2 1540/1540.
- Rows 16–18: in-range `01F`/`0F1` at F04 with sustained continuation, then `000`.

G25 closes in-range ordering: tick zero is base; later ticks select
`[base,x,y][(effectiveSpeed - tick) % 3]`. `LinearArpeggioOrderingTests` adds
speeds 1–8, all seven nonzero parameter controls, Fxx channel order, tuning,
source ownership and windows before/at/after updates. Runtime tests pin retained
cursor/generation and exact application frames at 44.1/48 kHz. G30 conversion,
G26 Amiga and existing onset/retirement policies remain separate. Listen to
rows 0–13 and 16–18 for ordering; rows 14–15 are a G30 boundary example.
Automated checks do not establish listening evidence; FT2 WAVs remain external.

## Amiga arpeggio ordering fixture

`generated/amiga-arpeggio-ordering.xm` is 1,237 bytes, SHA-256
`671d98f9d6e608fe144c8282b1fa15132882c9b4404c3f1a3ae8200345e4b800`.
It uses project-authored looped sine PCM, Amiga frequency mode, sample finetune
+64 and relative note +12. Every closure assertion uses in-range notes.

| Rows | Control |
| --- | --- |
| 0–2 | F02 after fresh 037; active continuation then 000 |
| 3–5 | F03 after note-only 073; single-nibble 010 then 000 |
| 6–9 | F06, 037/073, release then retained-source 001 |
| 10–13 | F07 before fresh/active 037, F02 before 073, then 000 |
| 14–15 | B-3 plus relative +12: 037 crosses the octave at F06 |
| 16–18 | F04, 01F/0F1, then 000 |

`AmigaArpeggioTests` pins G25's shared remaining-tick selection, observed FT2
quantized periods, finetunes -128/-64/-1/0/+1/+64/+127, relative -12/0/+12,
source generations, no-owner behavior and both-rate whole/window/runtime plans.
App runtime tests additionally pin applied frames and retained-source cursor
continuity. Separate high/low edge controls preserve current G30 range policy;
no lookup, clamp, fixed-point conversion or portamento policy changes here.
Use Amiga Frequency Slides with the reference profile in
[audio-comparison.md](../../docs/audio-comparison.md). Automated comparison does
not establish listening evidence; generated reference WAVs stay outside git.

## Amiga tone-portamento consumer fixture

`generated/amiga-tone-portamento-consumers.xm` is project-generated Amiga XM:
12 channels, 24 rows, speed 3/BPM 125 initially, 120 ticks / 2.4 seconds.

| Rows | Control |
| --- | --- |
| 0–3 | Retained 504/F4, cold 504/F4 to exact sample1 note-only starts, A04/604/A24 to cold 500, seeded F0, explicit cold F4+C20, initialized empty Fx/5xy and completed/released ownership. |
| 4–8 | Earlier F01 and later F02/F06 with F03; speed-1 nonexecution, Fx speed admission, larger/mixed 5xy and shared 500 replay. |
| 9–13 | Mute before replacements, then finetune +127/relative +12 B-to-C targets; explicit target seeds isolate the existing 3xx authority. |
| 14–19 | Muted replacements, neutral exact reach/overshoot and already-reached continuation. |
| 20–23 | Muted valid-low/high boundary controls under existing G30 lookup/conversion policy. |

Cold continuations start real sources at carried zero gain; the explicit writer
and seeded upward 500 controls remain audible. Retained sources keep generation
and cursor while owned defaults/clocks reset. Initialized empty headers retain
volume 24/pan 80 before shared slides; later note-only uses the exact mapped
sample1 and carries the resulting volume 16/pan 80 independently of header metadata.
Model tests extend the byte, speed, tuning and memory matrix beyond this compact
fixture. Both-rate whole/window/runtime/host checks share the same event frames.
Matched FT2-profile controls pass with existing onset/interpolation/G30 residuals;
reference WAVs and generated diagnostics stay outside git. This is bounded
consumer closure, preserving the existing 3xx target-lifetime boundary across
ordinary note+instrument triggers and other unclosed pitch interactions.

## Cold tone-portamento initialization fixture

`generated/cold-tone-portamento-initialization.xm` is project-authored Linear XM,
15 channels, 16 rows, BPM 125: 44 ticks / 0.88 seconds. Amiga tests project the same
fixture while omitting stored 5xy/Fx cells to preserve this prerequisite baseline.
The G28 fixture above covers those Amiga consumers.

| Rows | Control |
| --- | --- |
| 0–3 | Cold 304/504/F4 and unseeded 300/500/F0, then exact note-only routes; separate 3xx/A40/F4 seeds feed 300/500/F0. Seeded upward 500 is audible. |
| 4–6 | F01 cold 304 and later note-only, then F03; no speed-1 slide execution. |
| 7–8 | Cold instrument-only, 304+column30 audible continuation, declared empty header, completed one-frame source and released source. |
| 9–12 | Empty/completed/released tone resets retain ownership/defaults. Mute before later note-only replacement to isolate retirement debt. |
| 13–15 | Ordinary note+instrument restores header volume 32, then explicit mute. |

Primary cold continuations start real mapped PCM at tracker gain zero. Header
volume 20 is refreshed metadata, not an extra multiplier or a channel-volume
setter. Tests separately pin source generations/cursors, state and PCM, including
both-rate whole/window/runtime delivery. Reference WAVs remain outside git.

## Tone-portamento retained-source reset fixture

`generated/tone-portamento-retained-source-reset.xm` uses project-authored PCM
and distinct source/target headers (volume 32/20, pan 96/192). It is stored in
Linear mode. Amiga 3xx tests project it into Amiga while omitting stored 5xy/Fx
cells to preserve this prerequisite baseline. The G28 fixture above covers
those Amiga consumers.

| Rows | Control |
| --- | --- |
| 0–3 | Tracker 64/cache 32, pan 240/cache 96; 304/300/504/F4 reset, cold/completed exclusions |
| 4–5 | Column volume/fine/pan and Cxx override the retained reset |
| 6–9 | Release, modulation, envelope/key/fadeout reset and 8xx override |
| 10–14 | Earlier/later F01/F02/F03/F06; speed-1 reset without movement |
| 15–20 | Instrument-only/note-only/empty exclusions; later ordinary note uses carried instrument 2, whose new cache becomes authoritative |
| 21–23 | Empty targets, no-owner protection and ordinary-trigger regression |

Focused tests add logical envelope segment/sustain/loop reconstruction, missing
targets, all supported surfaces and exact reset/tick/window splits. Runtime tests
pin frames, held targets and cursor/generation continuity at 44.1/48 kHz. Listen
to rows 0–14 for reset/writer behavior and rows 15–20 for retained versus carried
ownership. Automated checks do not establish listening; FT2 WAVs remain external.

## Bounded pitch conversion (G30A)

`bounded-pitch-conversion-linear.xm` and
`bounded-pitch-conversion-amiga.xm` are a matched 96-row, speed-3/BPM-125 pair.
The first 84 rows sustain six public sine voices for 5.04 seconds; the complete
fixtures last 5.76 seconds. Both use the same original 16-bit PCM recipes.

| Rows / channels | Control |
| --- | --- |
| 0–83, channel 0 | C-4, header finetune +1. Linear period 4608; Amiga 6848. |
| 0–83, channel 1 | C#4 with relative -1 and header -1: effective C-4. Linear 4612; Amiga 6872. |
| 0–83, channels 2–4 | Header +1 under E58, E50 and E5F: effective tuning 0, -128 and +112. |
| 0–83, channel 5 | C-3 with relative +12 and header +127: effective C-4. Linear 4548; Amiga 6488. |
| 84 | 037, 101, 201, 301, 448 and X11 exercise the shared conversion consumers. |
| 85–87 | E11/E21/X21/X11, 501, 600 and volume F1 retain their existing arithmetic, memory and schedule. |
| 88–91 | E57/E59, note-only and no-note E5 preserve exact routing and ordinary trigger ownership. |

[BoundedPitchConversionTests](../vtx_render_bounded_xm/BoundedPitchConversionTests.swift)
pins all signed Linear tuning groups, valid relative-note combinations, literal
reference steps/cursors, the full UInt16 conversion fingerprints, and the
separate known-wrong extreme-state fences. Runtime tests use the same pair at
44.1/48 kHz with whole/window/core/engine parity and exact event frames.

Reference comparisons use the pinned FT2 settings in
[the audio workflow](../../docs/audio-comparison.md): Float32 stereo, Linear
interpolation, volume ramping on, amplification 10, master 256, Precise BPM off.
Inspect periods and steps separately. G30A removes sustained conversion drift;
new-source onset and the reference's 15-bit interpolation fraction/integer PCM
rounding remain separate from VTX's Float interpolation. G30 remains open for
extreme admission, carried periods, signed arithmetic and target/direction policy.
No reference WAVs are included.
