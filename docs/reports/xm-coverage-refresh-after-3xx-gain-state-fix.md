# XM Effect / Parity Coverage Refresh After 3xx Gain-State Fix

Diagnostics-only local refresh after the focused same-cell `3xx`
instrument/default-volume gain-state fix. No XM effects, playback behavior,
parser behavior, tracker UI behavior, backend selection, or retired audio
backends were changed for this report.

## Local Artifact Scope

- Corpus labels: `xm-corpus-001` through `xm-corpus-026`
- Label source: reused the existing local-only corpus label map.
- Generated artifacts: kept in a local temporary diagnostics directory.
- Public safety: this report uses anonymized labels only; private modules,
  WAVs, JSON, Markdown summaries, logs, and the label map stayed out of git.

## Full Corpus Findings

The full local bounded diagnostics refresh covered 26 anonymized XM inputs.

| Metric | Count |
| --- | ---: |
| Detected commands | 222,392 |
| Applied commands | 215,060 |
| Deferred commands | 96 |
| Unsupported commands | 81 |
| No-op / effect-memory-deferred commands | 7,250 |
| Effect-memory reuses | 4,174 |
| Effect-memory missing cases | 1 |
| Unknown commands | 0 |

Remaining unsupported/deferred concrete buckets are now small:

| Command | Detected | Applied | Deferred | Unsupported | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `E0x` filter toggle | 72 | 0 | 72 | 72 | Still limited-usefulness deferral. |
| `E4x` vibrato control | 9 | 0 | 9 | 9 | Small concrete remaining pitch-control bucket. |
| `EDx` note delay | 616 | 600 | 15 | 0 | Remaining cases are no-note/deferred; one additional out-of-row no-op is counted in no-op totals. |

Traversal residuals:

| Command | Current result |
| --- | --- |
| `Dxx` pattern break | 30 detected, 29 applied, 1 out-of-range safe diagnostic. |
| `Bxx` position jump | No remaining `Bxx` occurrences in the refreshed selected traversal path. |
| `E6x` pattern loop | 28 traversal records: 3 applied, 14 loop-start marks, 11 loop-taken records. |
| `EEx` pattern delay | Not present in this refreshed selected traversal path. |

Pitch, volume-column, and memory residuals:

| Bucket | Current result |
| --- | --- |
| Volume-column vibrato / vibrato speed | Not present in the refreshed coverage summary. |
| `900` sample-offset memory | 2,686 detected; 2,685 reused/applied; 1 missing-memory no-op remains. |
| `9xx` sample offset | 8,196 detected and applied. |
| `4xy` vibrato memory | 1,110 detected/applied; 595 memory reuses; no missing-memory cases. |
| `6xy` vibrato + volume slide memory | 36 detected/applied; 36 memory reuses; no missing-memory cases. |
| `1xx` portamento up memory | 552 detected; 533 applied; 249 memory reuses; 19 no-op residuals, including 17 no-active-voice cases. |
| `2xx` portamento down memory | 1,342 detected; 1,298 applied; 609 memory reuses; 44 no-active-voice no-op residuals. |

Unresolved classification buckets:

| Bucket | Count | Notes |
| --- | ---: | --- |
| Note-off/key-off released active voice | 16,953 | Expected applied key-off handling. |
| Note-off/key-off with no active voice | 822 | No-active classification bucket. |
| `3xx` tone portamento with no active voice | 549 | No-active classification bucket. |
| `ECx` note cut with no active voice | 473 | No-active classification bucket. |
| `2xx` portamento down with no active voice | 44 | No-active classification bucket. |
| `1xx` portamento up with no active voice | 17 | No-active classification bucket. |
| `E2x` fine portamento down with no active voice | 10 | No-active classification bucket. |
| `0xy` arpeggio with no active voice | 1 | No-active classification bucket. |
| `EDx` note delay with no note | 15 | No-note deferred bucket. |

## Focused `xm-corpus-025` Findings

Focused diagnostics were rerun for order 1 / pattern 7 / channel 5, rows
`0x00...0x3F`.

- Order 1 maps to pattern 7.
- Same-cell `3xx` rows applied instrument state updates without sample-position
  resets.
- Same-cell `3xx` rows with instrument/default-volume restoration were present
  on rows `02`, `08`, `0E`, `14`, `1A`, `20`, `22`, `26`, `28`, `2E`, `34`,
  and `3A`.
- Volume-column set-volume rows with active-voice gain updates were present on
  rows `06`, `08`, `0C`, `0E`, `12`, `14`, `18`, `1A`, `1E`, `26`, `28`,
  `2C`, `2E`, `32`, `34`, `38`, `3A`, and `3E`.
- No same-cell `3xx` sample-position resets were reported.
- No volume-column set-volume rows lacked active-voice gain updates.
- Non-`3xx` replacement rows remained `04`, `0A`, `10`, `16`, `1C`, `2A`,
  `30`, `36`, and `3C`.

Optional MikMod/VTX comparison evidence was rerun with local-only WAV artifacts.
The simple `scripts/audio-compare.py` metric did not reproduce the earlier
approximately `0.929` focused correlation:

- First 30 seconds, auto-headroom candidate: normalized correlation
  `0.694009707`, no candidate clipping.
- Trimmed focused order 1 / pattern 7 / rows `0x00...0x3F` segment:
  normalized correlation `0.805447441`, no candidate clipping.
- The first-30-second comparison's largest mismatch windows were after the
  focused row `0x3F` end frame, including approximately `12.0...12.1`,
  `19.7...19.8`, `24.5...24.6`, `25.0...25.1`, and `27.4...27.5` seconds.

Treat the optional comparison numbers as local evidence only. The focused
diagnostics still show the intended no-retrigger `3xx` state-update behavior;
the lower plain WAV correlation suggests any audio follow-up should first
reproduce the earlier comparison settings or inspect the late-window mismatch
windows before changing playback behavior.

## Recommended Next PR

Recommended next PR: a focused `E4x` vibrato-control follow-up, unless the
maintainer prefers an explicitly diagnostics-only residual classification pass.

Rationale:

- `E0x` remains the largest unsupported/deferred count, but it is still a
  limited-usefulness filter-toggle deferral.
- `Dxx`/`Bxx`/`E6x` traversal no longer dominates the refreshed corpus evidence.
- `900`/`4xy`/`6xy`/`1xx`/`2xx` memory residuals are mostly covered or
  no-active/no-op classifications.
- `E4x` is the clearest small remaining concrete effect bucket with unsupported
  counts and a direct helper recommendation.
