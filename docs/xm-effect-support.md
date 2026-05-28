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

- Supported: implemented in the default CoreAudio C mixer runtime adapter path
  and the offline bounded C mixer render path.
- First-pass: deterministic behavior exists, but it is not claimed FT2-perfect.
- Deferred: known command, intentionally not implemented yet in the current
  runtime/offline C mixer adapter path.
- Classification-only: recognized for diagnostics or coverage reporting, but
  not a playback target yet.
- Not targeted for v1: OpenMPT / ModPlug hacks or non-FT2 extensions.

## Effect Column Commands

| Command | Name | Status | Effect memory | Runtime support | Offline support | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `0xy` | Arpeggio | Supported / first-pass | Deferred for broad memory | Yes | Yes | Deterministic tick-cycle sample-step updates; `000` is a no-op. |
| `1xx` | Portamento up | Supported / first-pass | `100` memory supported | Yes | Yes | Linear-frequency sample-step updates only. |
| `2xx` | Portamento down | Supported / first-pass | `200` memory supported | Yes | Yes | Linear-frequency sample-step updates only. |
| `3xx` | Tone portamento | Supported / first-pass | No broad memory claim | Yes | Yes | No-retrigger target setting and sample-step updates. |
| `4xy` | Vibrato | Supported / first-pass | `400` / zero-nibble memory supported | Yes | Yes | Uses supported `E4x` waveform state where available. |
| `5xy` | Tone portamento + volume slide | Supported / first-pass | Uses existing `3xx` tone target/speed; `500` reuses shared Axy-style volume-slide memory when available | Yes | Yes | Reuses `3xx` sample-step updates and `Axy` tick-level volume-slide policy; missing `500` volume-slide memory remains no-op/deferred. |
| `6xy` | Vibrato + volume slide | Supported / first-pass | Vibrato memory supported | Yes | Yes | Reuses vibrato memory plus current volume-slide gain path. |
| `7xy` | Tremolo | Deferred | Deferred | No | No | Legacy handler has decoder logic; default C mixer adapter support is not implemented. |
| `8xx` | Set panning | Supported / first-pass | Not applicable | Yes | Yes | Row-level panning state update. |
| `9xx` | Sample offset | Supported / first-pass | `900` memory supported | Yes | Yes | Same-cell note/sample starts; out-of-range offsets are skipped safely. |
| `Axy` | Volume slide | Supported / first-pass | `A00` reuses prior same-channel Axy-style volume-slide memory | Yes | Yes | Tick-level gain updates after tick 0; missing memory remains no-op/deferred. |
| `Bxx` | Position jump | Supported / first-pass | Not applicable | Yes | Yes | Focused traversal planning; broader tracker quirks remain deferred. |
| `Cxx` | Set volume | Supported / first-pass | Not applicable | Yes | Yes | Row-level channel-volume state update. |
| `Dxx` | Pattern break | Supported / first-pass | Not applicable | Yes | Yes | XM-style BCD row target with safe diagnostics. |
| `E0x` | Filter toggle | Deferred | Deferred | No | No | Limited usefulness for v1 compatibility. |
| `E1x` | Fine portamento up | Supported / first-pass | `E10` deferred/no-op | Yes | Yes | One row-level linear-period adjustment. |
| `E2x` | Fine portamento down | Supported / first-pass | `E20` deferred/no-op | Yes | Yes | One row-level linear-period adjustment. |
| `E3x` | Glissando control | Deferred | Deferred | No | No | No current C mixer adapter behavior. |
| `E4x` | Vibrato control | Supported / first-pass for `E40...E43` | State stored for later vibrato | Yes | Yes | Unsupported waveform/control values stay deferred. |
| `E5x` | Set finetune | Supported / first-pass | No-note memory deferred | Yes | Yes | Same-cell note triggers only; non-linear table behavior deferred. |
| `E6x` | Pattern loop | Supported / first-pass | Loop state supported for focused traversal | Yes | Yes | Missing loop starts are diagnosed without inventing playback. |
| `E7x` | Tremolo control | Deferred | Deferred | No | No | Deferred with `7xy`. |
| `E8x` | Set panning | Deferred | Deferred | No | No | `8xx` is the currently supported panning command. |
| `E9x` | Retrigger note | Supported / first-pass | `E90` deferred | Yes | Yes | Retrigger volume-change variants remain deferred. |
| `EAx` | Fine volume slide up | Supported / first-pass | `EA0` deferred/no-op | Yes | Yes | Row-level channel-volume adjustment. |
| `EBx` | Fine volume slide down | Supported / first-pass | `EB0` deferred/no-op | Yes | Yes | Row-level channel-volume adjustment. |
| `ECx` | Note cut | Supported / first-pass | Not applicable | Yes | Yes | Hard cut at requested row tick. |
| `EDx` | Note delay | Supported / first-pass | Not applicable | Yes | Yes | Delays same-cell normal note triggers; no-note residuals are diagnostic. |
| `EEx` | Pattern delay | Deferred | Deferred | No | No | Recognized as a traversal/timing hazard. |
| `EFx` | Invert loop / funk repeat | Deferred | Deferred | No | No | Not a current playback target. |
| `Fxx` | Speed / BPM | Supported / first-pass | Not applicable | Yes | Yes | Adapter timing supports XM speed/BPM changes. |
| `Gxx` | Global volume | Supported / first-pass | Not applicable | Yes | Yes | Clamped `0...64` global-volume state. |
| `Hxy` | Global volume slide | Supported / first-pass | `H00` no-op | Yes | Yes | Both-nibble parameters use diagnosed up-nibble precedence. |
| `Kxx` | Key off | Supported / first-pass | Not applicable | Yes | Yes | Schedules the existing key-off/release path; `K00` releases at row start. |
| `Lxx` | Set envelope position | Deferred | Deferred | No | No | Envelope position setting is a separate future foundation. |
| `Pxy` | Panning slide | Deferred | Deferred | No | No | Legacy handler support exists, but the default C mixer adapter path has no implementation yet. |
| `Rxy` | Multi retrigger | Supported / first-pass | `R00` deferred/no-op | Yes | Yes | Reuses the retrigger scheduler for active voices and applies a common-XM volume-change table with channel volume clamped to `0...64`. |
| `Txy` | Tremor | Deferred | Deferred | No | No | No current C mixer adapter behavior. |
| `X1x` / `X2x` | Extra fine portamento | Supported / first-pass | `X10`/`X20` deferred/no-op | Yes | Yes | Linear-frequency row-level adjustment only; other `X` subcommands remain deferred. |
| `X5x`, `X6x`, `X9x`, `XAx`, `Yxy`, `Zxx` | OpenMPT / ModPlug compatibility commands | Not targeted for v1 | Not targeted | No | No | Extension and hack families stay out of v1 unless a later compatibility target justifies them. |
| `Vxx`, `Wxx` | High-byte unknowns in current diagnostics | Classification-only | Not applicable | No | No | Kept visible as unsupported diagnostics; no playback behavior is inferred. |

`Rxy` volume mode handling is first-pass common XM behavior: modes `1...5`
subtract `1, 2, 4, 8, 16`, modes `6...7` scale by `2/3` and `1/2`, mode `8`
is no change, modes `9...D` add `1, 2, 4, 8, 16`, and modes `E...F` scale by
`3/2` and `2`. The result is clamped to the XM channel-volume range `0...64`.

## Volume Column Commands

| Command family | Status | Runtime support | Offline support | Notes |
| --- | --- | --- | --- | --- |
| Set volume (`10...50`) | Supported / first-pass | Yes | Yes | Sets channel volume for triggers and active voices. |
| Volume slide down/up (`60...7F`) | Supported / first-pass | Yes | Yes | Row-level approximation in the adapter path. |
| Fine volume slide down/up (`80...9F`) | Supported / first-pass | Yes | Yes | Row-level approximation in the adapter path. |
| Vibrato speed (`A0...AF`) | Deferred | No | No | Decoded for diagnostics only. |
| Vibrato depth (`B0...BF`) | Deferred | No | No | Decoded for diagnostics only. |
| Set panning (`C0...CF`) | Supported / first-pass | Yes | Yes | Maps XM panning to the C mixer pan range. |
| Panning slide left/right (`D0...EF`) | Supported / first-pass | Yes | Yes | Row-level approximation in the adapter path. |
| Tone portamento (`F0...FF`) | Deferred | No | No | Decoded for diagnostics only. |
| Unsupported / unknown volume-column bytes | Classification-only | No | No | Kept visible in diagnostics when encountered. |

## Frequency Table Support

- Linear frequency table: primary v1 target and currently supported by the
  runtime/offline C mixer adapter path.
- Amiga frequency table: deferred as a separate foundation target, including
  Amiga-table interactions with `2xx`/`3xx` and related pitch effects.
- The current private Amiga-table target is tracked locally as
  `xm-corpus-036`; do not publish private filenames or paths.

## Explicitly Deferred / Not V1

- `E0x` filter toggle.
- Amiga frequency-table pitch behavior.
- `7xy`, `E3x`, `E7x`, `E8x`, `EEx`, `EFx`, `Lxx`, `Pxy`, and
  `Txy` in the default C mixer adapter path.
- `X` subcommands other than `X1x` and `X2x`.
- OpenMPT / ModPlug hacks and non-v1 extensions unless explicitly promoted by
  a future compatibility decision.

## Maintenance Note

Update this page whenever an XM effect PR lands. Corpus coverage reports are
private/local evidence; public docs and PR summaries should use anonymized
labels only and should never include private module filenames or local paths.
